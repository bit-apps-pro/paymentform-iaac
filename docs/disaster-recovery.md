# Disaster Recovery

End-to-end playbook for the four DR scenarios we plan against.

> **Companion docs**: [database-operations.md](database-operations.md) (replica promotion, restore), [db-backup.md](db-backup.md) (verifying backups), [db-replication.md](db-replication.md) (lag, monitoring), [database-tunnel-vpn.md](database-tunnel-vpn.md) (DB connectivity).

## Targets

| Tier | Loss tolerated (RPO) | Recovery time (RTO) | Strategy |
|---|---|---|---|
| Stateless (backend, renderer, client, admin) | 0 | < 10 min | Re-deploy from GHCR image to fresh instances |
| Postgres primary | ≤ 60 s | < 15 min | Promote in-region replica → DNS/pgbouncer cutover |
| Cloudflare R2 (uploads, ssl-config) | 0 | 0 | Region failover happens at edge; bucket lifecycle = preserve |
| Postgres full loss | ≤ 5 min (WAL archive interval) | < 60 min | `pgbackrest` restore from R2 onto new EC2 |

> RPO ≤ 60 s for the primary assumes streaming replication is healthy (lag < 30 s). Run `make state-list` after major changes and check `db-replication.md` weekly.

## Inventory

Before any DR move, confirm what is alive.

```bash
# 1. State sanity
cd iaac/environments/prod && tofu refresh -input=false

# 2. ASG health (backend + renderer)
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names paymentform-prod-backend-compute-asg paymentform-prod-renderer-compute-asg \
  --query 'AutoScalingGroups[].{name:AutoScalingGroupName,desired:DesiredCapacity,instances:Instances[].{id:InstanceId,health:HealthStatus,lifecycle:LifecycleState}}'

# 3. Primary + replica reachability
ssh ec2-user@postgres-primary 'pg_isready -h localhost'
ssh ec2-user@postgres-replica 'pg_isready -h localhost && psql -h localhost -U replicator -d postgres -c "SELECT now()-pg_last_xact_replay_timestamp() AS lag;"'

# 4. R2 buckets
aws s3 ls s3://paymentform-uploads-us --endpoint-url https://<ACCT>.r2.cloudflarestorage.com
```

Record what's reachable. If a node answers but is corrupted/diverged, treat it as down.

---

## Scenario 1 — Backend or renderer node loss

Cause: AZ failure, kernel panic, ASG terminates unhealthy instance.

### Detect

- ALB target group reports unhealthy targets
- CloudWatch alarm `paymentform-prod-backend-compute-requests-high` saturates on remaining nodes
- Cloudflare WAF logs show 502 spikes

### Recover

1. Confirm ASG sees the loss.
   ```bash
   aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names paymentform-prod-backend-compute-asg
   ```
   Healthy ASG behaviour: terminates unhealthy → launches replacement. No human action.

2. If ASG doesn't auto-replace (suspended process):
   ```bash
   aws autoscaling resume-processes --auto-scaling-group-name paymentform-prod-backend-compute-asg
   aws autoscaling set-desired-capacity --auto-scaling-group-name paymentform-prod-backend-compute-asg --desired-capacity <N>
   ```

3. Verify new instance pulled the right image:
   ```bash
   aws ssm send-command --instance-ids i-XXX \
     --document-name AWS-RunShellScript \
     --parameters 'commands=["docker ps --format \"{{.Image}}\""]'
   ```

4. If image is stale, force userdata refresh:
   ```bash
   make userdata-sync PROVIDER=aws
   ```

### Common issues

| Symptom | Cause | Fix |
|---|---|---|
| ASG stuck `Pending:Wait` | Lifecycle hook waiting on userdata SSM doc | `aws ssm describe-instance-information --filters Key=InstanceIds,Values=i-XXX` — confirm agent online. Force-complete hook only after manual verify. |
| New instance launches but ALB marks unhealthy | Health-check path 404s during boot | Wait full grace period (300s). If still fails: SSH in, `journalctl -u docker -n 200`, check `docker logs paymentform-backend`. |
| Repeated launch/terminate cycle | Userdata script erroring | Read `cloud-init-output.log` on the new instance. Most common: GHCR login fails → fix `GHCR_TOKEN` SSM parameter. |

---

## Scenario 2 — Postgres primary loss

Cause: EBS volume detach, kernel panic, AZ failure.

### Detect

- Backend logs: `SQLSTATE[08006] could not connect to server`
- pgbouncer logs: `S: server connection error`
- CloudWatch alarm on RDS-equivalent metric (custom: 5xx rate at ALB)

### Decide

- **Primary instance reachable but Postgres dead** → restart Postgres on the same volume (Scenario 2a).
- **Primary instance unreachable / EBS detached** → promote replica (Scenario 2b).
- **Volume corrupt / data lost** → restore from pgbackrest (Scenario 4).

### 2a. Restart Postgres on the same node

```bash
ssh ec2-user@postgres-primary
sudo systemctl status postgresql
sudo journalctl -u postgresql -n 200 --no-pager
sudo pg_lsclusters
sudo systemctl restart postgresql
psql -U postgres -c 'SELECT now();'
```

If it won't start: see `troubleshooting.md` → "PostgreSQL Shows `active (exited)`".

### 2b. Promote replica → primary

> Full procedure in `database-operations.md` § Promote Replica to Primary. Summarised:

1. Confirm replica caught up:
   ```bash
   ssh ec2-user@postgres-replica
   psql -U postgres -c 'SELECT pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn();'
   ```
   Receive LSN ≈ replay LSN (lag < 1 second) → safe to promote. If lag is high, see issues table below.

2. Promote:
   ```bash
   sudo -u postgres pg_ctl -D /var/lib/postgresql/17/main promote
   psql -U postgres -c 'SELECT pg_is_in_recovery();'   # should now return false
   ```

3. Update pgbouncer + backend writer host:
   ```bash
   # In ansible or directly:
   sudo sed -i 's/DB_HOST_WRITE=.*/DB_HOST_WRITE=<NEW-PRIMARY-IP>/' /etc/paymentform/backend.env
   sudo systemctl restart paymentform-backend
   ```

4. Re-point Hetzner replicas at the new primary — see `db-replication.md` § Re-attach replica after promotion.

5. Take a fresh base backup of the new primary into R2 (don't trust the old WAL chain):
   ```bash
   ssh ec2-user@new-primary 'sudo -u postgres pgbackrest --stanza=main backup --type=full'
   ```

### Common issues

| Symptom | Cause | Fix |
|---|---|---|
| Replica lag > 5 min when primary dies | WAL backlog from a long-running primary transaction | Decide: wait for catch-up, OR promote with data loss equal to lag. Document the choice. |
| `pg_ctl promote` returns "server is not in standby mode" | `standby.signal` already removed (replica already primary, or never was) | Inspect `pg_data/standby.signal` and `recovery.conf`. If absent and `pg_is_in_recovery()` returns false → already promoted. |
| Backend can't connect after cutover | pgbouncer config still points at old primary | `cat /etc/pgbouncer/pgbouncer.ini`; verify `databases.*.host`. Reload pgbouncer: `sudo systemctl reload pgbouncer`. |
| Cloudflare tunnel stale | tunnel-db still routing 5432 to old IP | `tofu apply -replace=module.tunnel_db.cloudflare_zero_trust_tunnel_cloudflared.tunnel` — see `database-tunnel-vpn.md`. |

---

## Scenario 3 — Region (us-east-1) loss

Worst plausible case. AWS region down for hours.

### Detect

- AWS Health Dashboard / status.aws.amazon.com
- All ALB targets `UnhealthyHostCount` = total
- VPC tunnel unreachable from Hetzner ⇒ replicas stop receiving WAL

### Recover

There is no hot DR region today. The plan is _read-only mode_ until us-east-1 returns.

1. **Switch reads to Hetzner replicas.** Backend supports `DB_HOST_READ` env; point it at hel1 replica via Cloudflare tunnel.
   ```bash
   # On each active backend host:
   sudo sed -i 's/DB_HOST_READ=.*/DB_HOST_READ=db-tunnel.paymentform.io/' /etc/paymentform/backend.env
   sudo systemctl restart paymentform-backend
   ```
2. **Disable writes** by routing `api.paymentform.io` to a static maintenance page via Cloudflare WAF / Workers (`status.paymentform.io` already runs on Workers and stays up).
3. **Communicate via status page**: post incident — `docs/cdn-worker.md` covers `status.*` admin API.
4. When us-east-1 returns: bring primary up, replicas catch up, lift write block, sync writes that arrived to admin app (Hetzner) if any.

### Future hardening (not yet implemented — flag in oracle reviews)

- Cross-region replica in us-west-2 with Route 53 health-checked failover (`providers/aws/route53-failover/` scaffold exists, not wired).
- Multi-master strategy via logical replication for tenant data.

### Common issues

| Symptom | Cause | Fix |
|---|---|---|
| Cloudflare tunnel still serves dead AWS IP | tunnel-db edge cache hasn't expired | `cloudflared tunnel route delete` + recreate; or `tofu apply -replace`. |
| Maintenance page not appearing | DNS still proxies api.* to ALB | Add Cloudflare Pages Rule or Worker that returns 503 for `api.paymentform.io/*`. |
| Hetzner replica becomes write target accidentally | someone ran `pg_ctl promote` on a Hetzner box | Demote: stop PG, re-pg_basebackup from primary once region returns. |

---

## Scenario 4 — Complete primary + replica loss (data recovery)

Cause: both AZs lost, EBS volumes destroyed, or catastrophic corruption.

### Recover from pgbackrest in R2

> Full procedure in `database-operations.md` § Restore from Barman-Cloud Backup. Step summary:

1. **Provision fresh Postgres EC2** via tofu (compute-only, no data volume yet):
   ```bash
   tofu apply -target=module.postgres_database.aws_instance.primary
   ```

2. **Attach new EBS volume**, mount at `/mnt/postgresql`:
   ```bash
   tofu apply -target=module.postgres_primary_volume
   ```

3. **Pull pgbackrest config + cipher pass from SSM:**
   ```bash
   aws ssm get-parameter --name /paymentform/prod/pgbackrest_cipher_pass --with-decryption
   aws ssm get-parameter --name /paymentform/prod/backup_storage_access_key_id --with-decryption
   ```

4. **Restore latest full + WAL:**
   ```bash
   sudo -u postgres pgbackrest --stanza=main --type=time \
     --target="2026-05-22 06:00:00" restore
   sudo systemctl start postgresql
   psql -U postgres -c 'SELECT pg_is_in_recovery(), pg_last_wal_replay_lsn();'
   ```

5. **Verify** by sampling a known recent record:
   ```bash
   psql -U postgres -d paymentform -c "SELECT max(created_at) FROM payments;"
   ```

6. **Re-bootstrap replicas** from the new primary (see `db-replication.md` § Initial sync of a new replica).

### Common issues

| Symptom | Cause | Fix |
|---|---|---|
| `pgbackrest restore` fails with `unable to read` from R2 | bucket creds expired or missing | Verify `BACKUP_STORAGE_ACCESS_KEY_ID` env on host matches SSM. Re-run after `systemctl daemon-reload`. |
| Restore completes but PG won't start, `LOG: invalid checkpoint record` | Missing WAL segments between full backup and target time | `pgbackrest info` to see actual WAL coverage. Pick a target_time within available WAL. |
| Sequences out of sync after restore | `pg_dump`-style restore (not point-in-time) | Re-issue `SELECT setval(...)` from a backup of `information_schema.sequences`. Or accept and let next inserts skip. |
| Permissions broken (`role "X" does not exist`) | Roles not restored | `pgbackrest` restores cluster-wide including roles. If using logical, manually `CREATE ROLE`. |

---

## Stateless redeploy (any service)

When backend / renderer / client / admin / status worker need to be re-rolled.

```bash
# Rebuild image, push to GHCR
cd backend && git tag v1.2.4 && git push --tags
# CI runs build-and-push-image.yml then deploy-release.yml

# Or push existing image to a fresh instance via Make:
make update-backend BACKEND_IMAGE=ghcr.io/bit-apps-pro/paymentform-backend:v1.2.4
make userdata-sync PROVIDER=aws
```

For Cloudflare Worker disasters (cdn-{us,eu,ap}, status): see `cdn-worker.md` § Re-deploy via tofu and `troubleshooting.md` § Worker deployment.

---

## Drills

Run quarterly. Log the results in a shared doc.

1. **Q-DR-1**: Force ASG instance termination → time to ALB re-healthy.
2. **Q-DR-2**: Promote in-region replica in staging → confirm RTO < 15 min.
3. **Q-DR-3**: `pgbackrest restore` to a throwaway instance against a known timestamp → byte-compare a sampled table.
4. **Q-DR-4**: Simulate primary unreachable from Hetzner (block 7844/cloudflared) → confirm Hetzner alerts.
