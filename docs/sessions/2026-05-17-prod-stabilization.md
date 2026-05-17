# Prod stabilization, 2026-05-17 (us-east-1)

## Context

Backend was running on NLB+t4g.small with no MixedInstancesPolicy, no pgbouncer, and no replica. Primary DB had never been tuned from defaults. Backups to R2 had silently broken 16 days prior; WAL archival was failing at ~1.5-sec intervals. Read replica was non-functional. Goal of this session: cut over to ALB, harden DB with pgbouncer and tuning, and fix the backup pipeline. Work was performed across three modules (compute, database, provider configs) with zero downtime cutover.

---

## Issues & fixes (chronological)

### 1. Cloudflare CNAME conflict on ACM validation

**Symptom:** `tofu apply` errored on `cloudflare_dns_record.validation["api.paymentform.io"]` with `failed to make http request` (CF v5 provider wraps "record already exists" as a generic HTTP error).

**Diagnosis:**
Read the error from `tofu apply` — `failed to make http request` on the ACM validation `cloudflare_dns_record`. Tested whether the record actually exists in CF:

```bash
curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?name=_<hash>.api.paymentform.io&type=CNAME" \
  | jq '.result[] | {id, name, content}'
```

Returned exactly one record. The `content` field matched the value AWS expected from `aws_acm_certificate.this.domain_validation_options[].resource_record_value` — confirming it was an orphan from a prior bootstrap, not a wrong-value collision. Safe to import.

**Root cause:** A previous partial apply had created the ACM validation CNAME but rolled back without cleanup. New apply tried `POST`; CF rejected because the record was orphaned in the zone.

**Fix:** 
```bash
tofu import 'module.paymentform_acm_backend.cloudflare_dns_record.validation["api.paymentform.io"]' "$ZONE_ID/$RECORD_ID"
```
Subsequent plan showed update-in-place (TTL + comment field), then apply continued.

**Lesson:** When CF v5 provider says "failed to make http request" with a POST/PATCH, suspect "already exists" before suspecting network.

---

### 2. AWS rejected SG description with non-ASCII

**Symptom:** `aws_security_group.alb` create error: `Character sets beyond ASCII are not supported`.

**Diagnosis:**
AWS returned a specific error: `InvalidParameterValue: ... Character sets beyond ASCII are not supported`. Grepped for the offender in the module:

```bash
grep -n "—" providers/aws/alb/main.tf
```

Six matches — five in comments (harmless) and one on line 62 in the `aws_security_group.alb` resource's `description` argument (the one AWS actually sees). Only the argument needed the fix.

**Root cause:** SG description contained an em-dash (—).

**Fix:** Replaced em-dash with hyphen in `providers/aws/alb/main.tf` line 62.

**Lesson:** AWS SG name/description fields are strict ASCII. Don't smart-quote tofu strings.

---

### 3. ASG churn loop on new backend instances

**Symptom:** ASG kept launching c7g.large-aspiring instances; ELB health check failed within grace period; ASG terminated and re-launched in a loop.

**Diagnosis:**
ASG showed two healthy instances flapping between `InService` and `Terminating`:

```bash
aws autoscaling describe-scaling-activities \
  --auto-scaling-group-name paymentform-prod-backend-compute-asg-... \
  --max-records 6
```

The activity log alternated `launched in response to an unhealthy instance` and `taken out of service in response to an ELB system health check failure` every ~5 min. Target groups confirmed it: only the old instance was healthy, the new one was failing both NLB and ALB `/health` checks. With the cause unknown and the loop ongoing, suspended ASG processes first to investigate without churn.

**Root cause:** Combined effect of two real bugs (see #4 and #5) — root container never came up healthy.

**Fix:** Suspended `ReplaceUnhealthy`, `HealthCheck`, `Launch`, and `Terminate` processes on the ASG to stop the churn while diagnosing.
```bash
aws autoscaling suspend-processes --auto-scaling-group-name paymentform-backend \
  --scaling-processes ReplaceUnhealthy HealthCheck Launch Terminate
```
Resumed all after root causes fixed.

**Lesson:** First move in an ASG churn loop is to *stop the churn*. Diagnose with the patient alive.

---

### 4. Env file path mismatch between userdata and deploy script

**Symptom:** Backend container started but `/health` 502'd — DB env vars not loaded.

**Diagnosis:**
SSM-probed a backend instance to see what env the container actually had:

```bash
docker exec paymentform-backend printenv DB_PASSWORD       # empty
ls -la /etc/app.env                                         # exists, empty
ls -la /etc/backend.env                                     # exists, populated
grep ^ENV_PATH /etc/cloud-init/user-data.sh                 # /etc/${service_type}.env
grep -E 'ENV_FILE|-v.*\.env' backend/.github/scripts/deploy-ec2.sh
# → ENV_FILE=/etc/app.env, mounted /etc/app.env:/app/.env
```

Userdata wrote `/etc/backend.env`. deploy-ec2.sh mounted `/etc/app.env`. Container got an empty env file. App started but had no DB credentials.

**Root cause:** `compute-alb/userdata.sh` and `compute-nlb/userdata.sh` wrote env to `/etc/${service_type}.env` (e.g. `/etc/backend.env`), but `backend/.github/scripts/deploy-ec2.sh` mounted `/etc/app.env` into the container as `/app/.env`. Different files; app saw an empty mount.

**Fix:** Normalized both userdata scripts to `ENV_PATH="/etc/app.env"`. Also fixed deploy-ec2.sh to use `${ENV_FILE}` instead of the hardcoded `/etc/app.env` literal (the variable was defined but unused).

**Lesson:** If two scripts in two repos share a path, they share a variable — never two literals that "happen to match."

---

### 5. SSM agent offline on new instance blocked null_resource

**Symptom:** `null_resource.ssm_apply_userdata` `local-exec` failed with `InvalidInstanceId: Instances not in a valid state for account`.

**Diagnosis:**
Tried to query the failing instance:

```bash
aws ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=i-09be286c86e3927e8" \
  --query 'InstanceInformationList[0].PingStatus'
# → ConnectionLost
```

Primary DB instance showed `Online` from the same SSM call — confirming the issue was instance-specific, not account-wide. The new ASG instance had registered SSM briefly (~25 sec) then dropped during userdata. Got the EC2 console output as fallback (`aws ec2 get-console-output --latest`) but cloud-init had already finished, so the deeper logs on disk were unreachable without SSM.

**Root cause:** The null_resource sends SSM commands to ALL instances in the ASG. One of those was a freshly-launched instance whose SSM agent hadn't registered yet (or had crashed mid-bootstrap).

**Fix:** Terminated the bad instance, waited for ASG to remove from membership (briefly re-enabled `HealthCheck` + `Terminate` processes), then re-applied. Long term: the null_resource should filter to only `Online` SSM instances.

**Lesson:** `aws ssm send-command` against a mixed-availability target list is all-or-nothing. Filter for `Online` PingStatus first.

---

### 6. Replica down → app DB reads failing

**Symptom:** App errors on reads, with `DB_HOST_READ=10.0.2.216` (replica IP) refusing connections.

**Diagnosis:**
First checked the primary side for streaming status:

```bash
sudo -u postgres psql -c 'SELECT client_addr, state, sync_state FROM pg_stat_replication'   # 0 rows
sudo -u postgres psql -c 'SELECT slot_name, active FROM pg_replication_slots'               # 0 rows
```

No replica was connected. From a backend instance, TCP probe to the replica IP:

```bash
timeout 3 bash -c '> /dev/tcp/10.0.2.216/5432' && echo OPEN || echo CLOSED   # CLOSED
```

Then SSM to the replica itself:

```bash
systemctl is-active postgresql        # inactive
sudo tail /var/log/postgresql/*.log   # "received fast shutdown request" right after first start
```

PG had started at boot, run 12 seconds, then been told to shut down — and never started again. Userdata bailed somewhere after the stop.

**Root cause:** Replica EC2 was running, but PG service had been stopped 12s after first boot and never restarted — userdata-replica.sh had bailed on a missing directory (see #7). PG data dir was just initdb output, no streaming.

**Fix (hotfix):** SSM-edited `/etc/app.env` on both backend instances, `DB_HOST_READ=10.0.1.94` (primary), then sequential `docker restart paymentform-backend`. NLB kept 1 healthy throughout. Real fix tracked separately (replica recreate).

**Lesson:** For read/write split apps, the read host pointer should fall back to write host when replica is unreachable. We did this manually; the wiring should do it automatically.

---

### 7. Replica userdata-replica.sh: install -o without parent dir

**Symptom:** Cloud-init exited with `install: invalid target '/var/lib/pgsql/.pgpass': No such file or directory`.

**Diagnosis:**
Read cloud-init output on the broken replica via SSM:

```bash
sudo tail -100 /var/log/cloud-init-output.log | grep -E 'ERROR|invalid|exit'
```

Found the exact line:
```
install: invalid target '/var/lib/pgsql/.pgpass': No such file or directory
```

Then verified the script's intent by reading line 195-200 of `userdata-replica.sh`:

```bash
PGPASS_FILE="/var/lib/pgsql/.pgpass"
install -o postgres -g postgres -m 0600 /dev/null "$PGPASS_FILE"
```

`/var/lib/pgsql/` was the intended home dir but never created (Debian/Ubuntu uses `/var/lib/postgresql/`). `install` doesn't auto-create parents.

**Root cause:** Line 197 used `install -o postgres /dev/null /var/lib/pgsql/.pgpass` but `/var/lib/pgsql/` didn't exist (Ubuntu uses `/var/lib/postgresql/`; the script chose `/var/lib/pgsql/` as a convention but never `mkdir -p`'d it). `set -e` exited the whole script before pg_basebackup.

**Fix:** Added pre-step directory creation:
```bash
install -d -o postgres -g postgres -m 0700 "$(dirname "$PGPASS_FILE")"
```
before the `install` of the .pgpass file.

**Lesson:** `install` doesn't auto-create parent dirs without `-D` (file) or explicit `install -d` (directory). With `set -e`, one missing dir kills everything downstream.

---

### 8. pgbouncer_auth role missing on primary blocks replica bootstrap

**Symptom:** Replica userdata-replica.sh waited 60s for pgbouncer_auth role to replicate from primary, then `exit 1`. PG started but not streaming; SSM agent dropped during the failed bootstrap window.

**Diagnosis:**
After fixing #7 and recreating the replica, the slot existed on primary but never went active. Probed primary's log for any connection attempts from the new replica IP:

```bash
sudo grep -E '10\.0\.2\.81' /var/log/postgresql/*.log    # no entries
```

Zero hits — replica never even tried to connect. Read `userdata-replica.sh` more carefully and found the wait-loop for `pgbouncer_auth` role with `exit 1` if not found within 60 sec. Verified on primary:

```bash
sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='pgbouncer_auth'"   # empty
sudo -u postgres psql -tAc "SELECT proname FROM pg_proc WHERE proname='lookup_pg_user'"  # empty
```

Neither the role nor the function existed on the running primary — the DB-opt commit's primary userdata had never been applied here.

**Root cause:** The DB-opt commit's primary userdata creates `pgbouncer_auth` role + `lookup_pg_user` function — but that commit hadn't been applied to the running primary yet. Replica needs them via replication.

**Fix:** Ran the same SQL manually on primary via SSM:
```sql
CREATE ROLE pgbouncer_auth WITH LOGIN PASSWORD '<random>';
CREATE OR REPLACE FUNCTION public.lookup_pg_user(uname text) 
  RETURNS TABLE(usename text, passwd text) LANGUAGE sql 
  SECURITY DEFINER AS $$ 
    SELECT usename::text, passwd::text FROM pg_shadow WHERE usename = uname; 
$$;
REVOKE ALL ON FUNCTION public.lookup_pg_user(text) FROM public;
GRANT EXECUTE ON FUNCTION public.lookup_pg_user(text) TO pgbouncer_auth;
```

**Lesson:** Replica bootstrap shouldn't depend on primary-only role state in a way that silently breaks if primary userdata is older. Either make the wait soft-fail, or bootstrap the dependency before triggering replica creation.

---

### 9. pg_basebackup -C not idempotent

**Symptom:** Second replica recreate attempt failed: `replication slot "paymentform_replica" already exists`. Dropping the slot via psql before basebackup worked — but mid-flight a NEW slot was being created by the in-progress basebackup, racing with the drop.

**Diagnosis:**
Re-apply after #8 failed with:
```
ERROR: replication slot "paymentform_replica" already exists
```

Looked at the primary log timestamps. Dropped the slot manually:

```bash
sudo -u postgres psql -c "SELECT pg_drop_replication_slot('paymentform_replica')"
```

Re-ran apply. Same error came back 40 seconds later. Two pg_basebackup connections from `[608523]` and `[608528]` appeared in the log — `pg_basebackup -C` opens multiple connections and the second one tried to create a slot the first had just made. Not retryable; needed an idempotent pre-drop in the script itself, not at apply time.

**Root cause:** `pg_basebackup -C --slot=paymentform_replica` creates the slot atomically; if it already exists, fails. Previous failed bootstraps had left orphan slots.

**Fix:** Added idempotent pre-step to userdata-replica.sh — drop the slot from primary side:
```bash
psql -h primary -U replicator -d postgres \
  -c "SELECT pg_drop_replication_slot('paymentform_replica') 
      FROM pg_replication_slots WHERE slot_name='paymentform_replica'"
```
The `replicator` role has REPLICATION attribute and pg_hba `trust` from VPC, so no password needed for this maintenance call.

**Lesson:** `-C` in pg_basebackup is convenient but not retryable. Idempotent wrapper: drop-if-exists → create.

---

### 10. pgbouncer SCRAM auth failure (SCRAM secret vs cleartext)

**Symptom:** Connecting to pgbouncer:6432 as the app user got `FATAL: SASL authentication failed`. Logs showed: `password is SCRAM secret but client authentication did not provide SCRAM keys`.

**Diagnosis:**
First test from a backend container:

```bash
docker run --rm -e PGPASSWORD="$DBPASS" postgres:17-alpine \
  psql -h 10.0.1.94 -p 6432 -U payment4dm1n -d paymentform -c 'SELECT 1'
# → FATAL: server login failed: wrong password type
```

Read pgbouncer's journal:

```bash
sudo journalctl -u pgbouncer --no-pager -n 30
```

Showed the exact reason:
```
S-...: paymentform/pgbouncer_auth@127.0.0.1:5432 cannot do SCRAM authentication:
password is SCRAM secret but client authentication did not provide SCRAM keys
```

userlist.txt held the SCRAM verifier read from `pg_shadow.passwd`. pgbouncer can't form a SCRAM client request to PG from just the verifier — it needs the actual cleartext (or its own SCRAM secret entry, which it doesn't have).

**Root cause:** Userdata wrote `userlist.txt` by reading the SCRAM verifier from `pg_shadow`. pgbouncer needs cleartext (or its own SCRAM secret entry) to authenticate to PG for the `auth_query` lookup. Just the verifier is insufficient.

**Fix:** Changed userdata to ALTER ROLE the pgbouncer_auth password to a known cleartext on each run, and write that cleartext to userlist.txt. Other users continue to be looked up dynamically via `auth_query`.

**Lesson:** Storing SCRAM verifiers in userlist.txt only works for *client* auth. The pgbouncer-to-PG auth_user needs cleartext, period.

---

### 11. pgbouncer auth_query in wrong database

**Symptom:** pgbouncer error `function public.lookup_pg_user(unknown) does not exist`.

**Diagnosis:**
After fixing #10, new error:

```
S: error in auth_query: ERROR: function public.lookup_pg_user(unknown) does not exist
C-: paymentform/(nouser)@... pooler error: bouncer config error
```

Verified where the function actually lived:

```bash
sudo -u postgres psql -d postgres -tAc "SELECT proname FROM pg_proc WHERE proname='lookup_pg_user'"     # found
sudo -u postgres psql -d paymentform -tAc "SELECT proname FROM pg_proc WHERE proname='lookup_pg_user'"  # empty
```

Function was in `postgres` db only. pgbouncer's default behavior is to connect to the client-requested db (`paymentform`) for the auth_query. `auth_dbname` overrides this.

**Root cause:** pgbouncer's auth_query connects to whichever db the client is requesting (e.g. `paymentform`). The function only existed in `postgres` db.

**Fix:** Added `auth_dbname = postgres` to pgbouncer.ini.

**Lesson:** With auth_query and per-tenant databases, pin `auth_dbname` so the lookup function only needs to live in one place.

---

### 12. Password mismatch between /etc/app.env and pg_shadow

**Symptom:** pgbouncer client auth still failing after #10 + #11 were fixed.

**Diagnosis:**
After #10 and #11 fixes, still got `SASL authentication failed`. Suspected the app's password didn't actually match what was in `pg_shadow`. Direct probe from backend on port 5432 worked — but pg_hba revealed why:

```bash
sudo grep -E '^host' /etc/postgresql/17/main/pg_hba.conf
# → host all all 10.0.0.0/16 trust          ← bypasses password
```

The trust line made VPC connections invisible to password mismatch. Tested with the actual password against the SCRAM-required path:

```bash
PGPASSWORD="$DBPASS" psql -h 127.0.0.1 -p 5432 -U payment4dm1n -c 'SELECT 1'
# → password authentication failed
```

Confirmed: /etc/app.env and pg_shadow had different passwords for `payment4dm1n` and had been silently diverged behind trust auth.

**Root cause:** pg_hba had `host all all 10.0.0.0/16 trust` — VPC connections bypassed password check. The password the app was using and the password stored in pg_shadow had silently diverged at some point and nobody noticed.

**Fix:** `ALTER ROLE payment4dm1n WITH PASSWORD '<value from /etc/app.env>'`. Aligned DB to app.

**Lesson:** Trust auth makes password drift invisible. Whenever you introduce strict auth (here: pgbouncer SCRAM), expect surprises. Long term: drop trust, require SCRAM everywhere.

---

### 13. CloudWatch Agent install: dpkg vs rpm

**Symptom:** Renderer userdata cloud-init errored with `dpkg: command not found`. `set -e` exited the script; CW Agent never installed.

**Diagnosis:**
Renderer instance refresh reached 75% then SSM dropped on the new instance. Got console output as fallback:

```bash
aws ec2 get-console-output --instance-id <new> --latest | tail -50
```

Found the error:
```
[2026-05-17 ...] Installing CloudWatch Agent
/var/lib/cloud/instance/scripts/part-001: line 183: dpkg: command not found
cc_scripts_user.py[WARNING]: Failed to run module scripts-user
```

The cloud-init version (`v. 22.2.2`) was Amazon Linux's, not Ubuntu's (which would be v.26+). AMI mismatch: the userdata block was written assuming Ubuntu but ran on AL.

**Root cause:** The AMI for renderer is Amazon Linux (rpm-based), not Ubuntu (deb-based). Userdata hardcoded `dpkg -i`.

**Fix:** Switched to runtime detection:
```bash
if command -v rpm >/dev/null && ! command -v dpkg >/dev/null; then
  # rpm path
else
  # dpkg path
fi
```

**Lesson:** AMI family changes between modules. Don't hardcode package-manager binaries in shared userdata.

---

### 14. MixedInstancesPolicy duplicate override

**Symptom:** `tofu apply` error: `Cannot add same instance type override more than once. Remove these duplicates: [c7g.large]`.

**Diagnosis:**
`tofu apply` error:
```
ValidationError: Cannot add same instance type override more than once.
Remove these duplicates from the request and try again: [c7g.large]
```

Looked at the generated `mixed_instances_policy.launch_template` block in `compute-alb/main.tf` — it had a static `override { instance_type = var.instance_type }` followed by a `dynamic "override" { for_each = var.spot_instance_types }`. Both contained `c7g.large` (the primary type was also the first Spot diversification option), so AWS got two duplicate entries.

**Root cause:** `override` block listed `var.instance_type` separately, then `dynamic "override"` iterated over `var.spot_instance_types` which also contained `c7g.large`.

**Fix:** Switched to a single dynamic block over `distinct(concat([var.instance_type], var.spot_instance_types))`.

**Lesson:** When AWS rejects duplicates, `distinct()` in Terraform is your friend.

---

### 15. CF API token couldn't read Zone Settings

**Symptom:** `curl /zones/<id>/settings/security_header` → `9109 Unauthorized to access requested resource`.

**Diagnosis:**
Tried to read HSTS state via API to know what to change:

```bash
curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/settings/security_header"
# → {"success":false,"errors":[{"code":9109,"message":"Unauthorized to access requested resource"}]}
```

Same 9109 on `/settings/ssl`. The token was scoped to DNS edits but not Zone Settings (HSTS, SSL mode). Confirmed via `/user/tokens/verify` which showed only DNS permissions. Switched to the CF dashboard for this one — quicker than minting a new token.

**Root cause:** The CF API token has DNS scope but not Zone Settings scope. Couldn't read HSTS or SSL mode programmatically.

**Fix:** Did the dashboard click for HSTS. For DNS record changes (DNS scope), API worked fine.

**Lesson:** CF token scopes are fine-grained. If you want Zone Settings via API, mint a token with that scope. We didn't need to here; dashboard sufficed.

---

### 16. Phase 3 cutover: TTL irrelevant for proxied records

**Symptom:** Prior runbook said "wait 24h after lowering TTL before flipping DNS".

**Diagnosis:**
The earlier runbook step said "wait 24h after lowering TTL". Verified the record's proxy state in CF:

```bash
curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?name=api.paymentform.io" \
  | jq '.result[0] | {type, content, proxied}'
# → {"type": "CNAME", "content": "...nlb...", "proxied": true}
```

`proxied: true` confirmed orange-cloud. Clients connect to CF anycast edge, not the origin directly — TTL clock irrelevant. Also the ALB SG only allows CF IPs (`alb_ingress_443_cf_v4/v6`), so a non-proxied flip would have broken the connection anyway. Cross-check that the SG ingress rules were in place reassured us the architecture *required* proxied.

**Root cause / clarification:** That's true for grey-cloud (DNS-only) records where external resolvers cache. For orange-cloud (proxied) records, clients connect to CF edge IPs; CF resolves origin internally; CNAME change propagates inside CF's network in seconds.

**Fix:** Flipped `api.paymentform.io` CNAME from NLB to ALB DNS immediately via API. NLB drained to ~0 bytes within 6 min, ALB ramped, zero 5xx.

**Lesson:** Proxied = swap origin live, no TTL clock. Grey-cloud = TTL matters.

---

### 17. Barman R2 backup 401 for ~16 days

**Symptom:** Primary PG log spamming `ERROR: An error occurred (Unauthorized) when calling the PutObject operation: Unauthorized` every 1.5 sec. `pg_stat_archiver.failed_count = 62634`, `last_archived_wal` stuck at one from May 1.

**Diagnosis:**
First test from a backend container:

```bash
docker run --rm -e PGPASSWORD="$DBPASS" postgres:17-alpine \
  psql -h 10.0.1.94 -p 6432 -U payment4dm1n -d paymentform -c 'SELECT 1'
# → FATAL: server login failed: wrong password type
```

Primary log was spamming the same error every ~1.5 sec:

```
ERROR: An error occurred (Unauthorized) when calling the PutObject operation: Unauthorized
```

Extracted the keys from the live `archive_command`:

```bash
ACMD=$(sudo -u postgres psql -X -tAc "SHOW archive_command")
KEY=$(echo "$ACMD" | grep -oP 'AWS_ACCESS_KEY_ID=\K[^ ]+')
SEC=$(echo "$ACMD" | grep -oP 'AWS_SECRET_ACCESS_KEY=\K[^ ]+')
```

Compared with tfvars: `MATCH`. So the keys in code matched what was deployed — token rotation/revocation at the CF side was the only remaining cause. Confirmed with a direct call:

```bash
AWS_ACCESS_KEY_ID=$KEY AWS_SECRET_ACCESS_KEY=$SEC \
  aws --endpoint-url https://...r2.cloudflarestorage.com \
  s3api head-bucket --bucket paymentform-prod-db-backups
# → 401 Unauthorized
```

Even bucket HEAD failed. Token had to be regenerated. Inspected damage:

```bash
sudo -u postgres psql -c 'SELECT archived_count, failed_count, last_archived_wal, last_failed_wal FROM pg_stat_archiver'
# → archived_count=45, failed_count=62634, last_archived_wal stuck on May 1 file
```

16 days of accumulated failed archives. Local pg_wal had 1404 files (~22 GB) still on disk waiting — no data loss yet.

**Root cause:** The R2 access keys baked into `archive_command` had been revoked or had had their bucket scope removed sometime after May 1. Backup was silently broken for over 2 weeks. No alert was wired.

**Fix:**
1. Created new R2 token in CF dashboard with Object Read & Write for the bucket.
2. Updated tfvars locally.
3. Tested via `barman-cloud-check-wal-archive` + `barman-cloud-backup-list` with new keys.
4. Live swap of archive_command on running PG:
   ```sql
   ALTER SYSTEM SET archive_command = '<new cmd with new keys>';
   SELECT pg_reload_conf();
   ```
   No PG restart needed.
5. Watched `pg_stat_archiver.archived_count` climb. 1093 `.ready` files drained at ~1/sec.

**Lesson:** Backup mechanism needs a monitor. A CW alarm on `last_failed_time > 1 hour ago` would have caught this on day one. PG holds WAL locally on archive failure (good — data safe) but a 22 GB local WAL pile is *almost* the EBS limit.

---

### 18. PG primary running pure defaults — tuning never applied

**Symptom:** `shared_buffers = 128 MB`, `random_page_cost = 4` (HDD!), `effective_io_concurrency = 1`, `wal_compression = off`, `pg_stat_statements` not loaded — all defaults on a payments DB.

**Diagnosis:**
Sampled live config via SSM:

```bash
sudo -u postgres psql -X -c "SELECT name, setting, source FROM pg_settings WHERE name IN
  ('shared_buffers','effective_cache_size','work_mem','max_connections',
   'random_page_cost','wal_compression','shared_preload_libraries',
   'log_min_duration_statement','statement_timeout')"
```

Every value showed `source = default`. shared_buffers was 128 MB on a 4 GB instance. `random_page_cost = 4` (HDD planner) on a gp3 SSD. `shared_preload_libraries` empty → no `pg_stat_statements`. The tuning block in `userdata-primary.sh` had been written months ago in the DB-opt commit but the primary was bootstrapped *before* that commit and userdata had never re-run.

**Root cause:** The tuning block from the DB-opt commit lives in `userdata-primary.sh` but the running primary was bootstrapped on 2026-04-30, before that commit. Userdata never re-ran.

**Fix:** Applied via `ALTER SYSTEM SET` for each tuning, `pg_reload_conf()` for SIGHUP-able settings, then one `systemctl restart postgresql` (~13s) for `shared_buffers`/`max_connections`/`shared_preload_libraries`/`wal_buffers`. Created the pg_stat_statements extension after restart.

**Lesson:** Tuning that lives in userdata only applies on fresh bootstrap. For changes to long-lived instances, either trigger a userdata re-run via SSM or apply directly via ALTER SYSTEM (and remember to update userdata for state-correctness).

---

### 19. NLB removal: must -target to avoid unrelated CDN-domain replacements

**Symptom:** `tofu plan` after removing the NLB module also wanted to replace 3 `cloudflare_workers_custom_domain` resources (for cdn-us, cdn-eu, cdn-ap subdomains) due to a provider-schema drift.

**Diagnosis:**
First plan after removing the NLB module showed:
```
Plan: 6 to add, 2 to change, 16 to destroy.
```

The 16 destroys were the expected NLB stack, but the 6 adds + 2 changes included surprises:

```bash
grep -E "must be replaced|will be created" /tmp/plan-nlb.out
# → cloudflare_workers_custom_domain.cdn_domain["ap"] must be replaced
# → cloudflare_workers_custom_domain.cdn_domain["eu"] must be replaced
# → cloudflare_workers_custom_domain.cdn_domain["us"] must be replaced
# → ... null_resource.ssm_apply_userdata replacements
```

CF provider v5 had unset `environment = "production"` on the `cloudflare_workers_custom_domain` resources, forcing replacement of all three CDN domains — completely unrelated to NLB removal. Scoped the apply with `-target` to only the NLB resources to avoid pulling those in.

**Root cause:** CF provider v5 unsets `environment = "production"` on `cloudflare_workers_custom_domain` resources, forcing replace. Unrelated to NLB.

**Fix:** Applied with explicit targets to isolate the NLB destroy from the CDN-domain churn:
```bash
tofu apply -target=module.paymentform_nlb_backend \
  -target=module.paymentform_backend.aws_autoscaling_group.compute \
  -target=module.paymentform_security
```

**Lesson:** Long-lived branches accumulate provider drift. Either fix drift as you find it (and commit), or `-target` carefully to scope each apply.

---

### 20. Backend NLB → ALB cutover sequencing

**Diagnosis:**
Pre-flight checks before flipping live DNS:

```bash
aws elbv2 describe-load-balancers --names paymentform-prod-backend-alb \
  --query 'LoadBalancers[0].{State:State.Code,DNS:DNSName}'           # State:active
aws elbv2 describe-target-health --target-group-arn $TG_ARN          # both healthy
aws acm describe-certificate --certificate-arn $CERT_ARN \
  --query 'Certificate.Status'                                       # ISSUED
```

Captured rollback (the original NLB content) before the PATCH so we could revert in one command. After flip, monitored both LBs side-by-side:

```bash
aws cloudwatch get-metric-statistics --namespace AWS/ApplicationELB \
  --metric-name RequestCount ...                                     # rising
aws cloudwatch get-metric-statistics --namespace AWS/NetworkELB \
  --metric-name ProcessedBytes ...                                   # decaying
aws cloudwatch get-metric-statistics --namespace AWS/ApplicationELB \
  --metric-name HTTPCode_Target_5XX_Count ...                        # zero
```

CF edge propagation took 5-6 min. NLB went to 0 bytes; ALB to ~30 req/min on normal load; no 5xx during or after.

Verified ALB stack already built (ACM cert ISSUED, listeners up, both backends dual-attached to NLB+ALB target groups). Confirmed proxied DNS → flip is live, not gated on TTL. Captured rollback command (PATCH back to NLB DNS). PATCHed `api.paymentform.io` CNAME to ALB DNS via CF API. Watched NLB ProcessedBytes drain to ~0 in 6 min; ALB RequestCount ramp; zero 5xx. After stable, removed `module.paymentform_nlb_backend` via tofu (see #19). Caddyfile `:443` block in backend repo is now unused but left in place for now — separate PR.

---

## Final architecture

```
[client] 
  → [Cloudflare HTTPS proxied] 
  → [ALB :443 ACM] 
  → [backend c7g.large × 2 :80 Caddy]
       ↓
  [pgbouncer 6432 on primary]
       ↓
  [PG 5432 primary, t4g.medium, 1 GB shared_buffers, EBS 4000 IOPS/250 MB/s]
```

- **Backend:** 2 × c7g.large On-Demand (Savings Plan covers), MixedInstancesPolicy allows Spot above base; `min=2, max=8`; capacity_rebalance on; ALB only (NLB removed).
- **Renderer:** 1 × c7g.medium; NLB (custom-domain tenant sites require Caddy on-demand TLS); memory-based ASG scaling via CW Agent publishing `mem_used_percent` per ASG.
- **Primary DB:** pgbouncer (transaction pool, 25 backend connections, scram-sha-256, auth_query to lookup_pg_user, auth_dbname=postgres); WAL archive to R2 with new keys, backlog drained; cloudflared admin tunnel disabled (use SSM Session Manager); replica disabled pending hardening.
- **Renderer NLB:** Stays in place (custom-domain SaaS pattern; ALB SNI doesn't scale to thousands of tenant domains).

---

## Open follow-ups

- Re-enable replica when userdata-replica.sh is hardened end-to-end (idempotent slot drop already in place; remaining: rotate pgbouncer_auth password mechanism on read-only standby).
- Re-enable HSTS at CF edge or in Caddy `:80` block.
- Drop the now-unused Caddyfile `:443` block from backend image.
- CW alarm on Barman archive failure (so we don't go 2 weeks blind again).
- pgbouncer pool size tuning based on `SHOW POOLS` data over the next week.
- Clean up tainted `null_resource.ssm_apply_userdata` (backend + renderer) in tofu state.
- Phase 4 polishing: drop the dual-LB target_group_arns logic; `compute-alb` module no longer needs to support both.
