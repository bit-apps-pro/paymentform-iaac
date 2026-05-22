# Database Backup

Operational guide for the two backup systems we run:

1. **`pgbackrest`** — primary Postgres (us-east-1) → Cloudflare R2 bucket `paymentform-prod-db-backups`. Full + diff + WAL archive. Encrypted with AES-256 (cipher pass in SSM).
2. **`barman-cloud-backup`** — Hetzner admin server local Postgres → R2 bucket `prod-admin-db-backup`. Smaller dataset, simpler retention.

> Restoring is covered in [`database-operations.md`](database-operations.md) § Restore from Barman-Cloud Backup. Disaster scenarios in [`disaster-recovery.md`](disaster-recovery.md).

## Storage layout

| Source | Bucket | Jurisdiction | Stanza / scope |
|---|---|---|---|
| AWS primary Postgres | `paymentform-prod-db-backups` | default | `pgbackrest` stanza `main` |
| AWS replica (optional) | same | default | not backed up by default; replica is recoverable from primary |
| Hetzner admin local PG | `prod-admin-db-backup` | default | `barman-cloud-backup`, server name `admin` |

Credentials: shared `BACKUP_STORAGE_*` env (R2 S3-compatible) — see SSM `/paymentform/prod/backup_storage_*`.

## Schedule

Configured in userdata (`providers/aws/database/userdata-primary.sh`, `providers/hetzner/admin-server/userdata.sh`) — cron entries on each host.

| Job | Frequency | What |
|---|---|---|
| `pgbackrest` full backup | weekly (Sunday 02:00 UTC) | Full base backup |
| `pgbackrest` diff backup | daily (02:00 UTC) | Incremental diff vs last full |
| `pgbackrest` WAL archive | continuous | `archive_command` in postgresql.conf streams every WAL segment immediately |
| `barman-cloud-backup` (admin) | daily (03:00 UTC) | Full backup of small admin DB |
| `barman-cloud-wal-archive` (admin) | continuous | WAL archive |

Retention: pgbackrest = 4 full backups + WAL covering full retention window. Tweak in `/etc/pgbackrest/pgbackrest.conf`:

```
repo1-retention-full=4
repo1-retention-diff=14
repo1-retention-archive=14
```

## Step 1: Verify backups are running

```bash
# On the primary:
sudo -u postgres pgbackrest --stanza=main info

# Expected output has 'status: ok' and recent timestamps.
```

Look for:

- `status: ok` (not `error: backup/expire running` for long, not `error: missing archive`)
- A **full** entry from < 8 days ago
- A **diff** from today (or this morning UTC)
- WAL range that extends within minutes of `now()`

Also check on the admin server:

```bash
ssh root@admin 'barman-cloud-backup-list --cloud-provider aws-s3 \
  --endpoint-url https://<ACCT>.r2.cloudflarestorage.com \
  s3://prod-admin-db-backup admin'
```

## Step 2: List + inspect backups

```bash
# Detailed info on each pgbackrest set:
sudo -u postgres pgbackrest --stanza=main info --output=json | jq '.[].backup[] | {label, type, timestamp, size: .info.size, error}'

# Quick text view:
sudo -u postgres pgbackrest --stanza=main info
```

For barman-cloud:

```bash
barman-cloud-backup-show --cloud-provider aws-s3 \
  --endpoint-url https://<ACCT>.r2.cloudflarestorage.com \
  s3://prod-admin-db-backup admin <backup_id>
```

## Step 3: Trigger a manual backup (out-of-cycle)

Before a risky migration, schema change, or experiment. Don't replace the scheduled cycle.

```bash
# pgbackrest full:
sudo -u postgres pgbackrest --stanza=main backup --type=full --log-level-console=info

# diff:
sudo -u postgres pgbackrest --stanza=main backup --type=diff
```

Admin:

```bash
ssh root@admin 'sudo -u postgres barman-cloud-backup \
  --cloud-provider aws-s3 \
  --endpoint-url https://<ACCT>.r2.cloudflarestorage.com \
  s3://prod-admin-db-backup admin'
```

Confirm the new backup appears in `info` / `barman-cloud-backup-list`.

## Step 4: Verify a backup is restorable (drill)

Quarterly drill. Restore to a throwaway instance and sample-compare.

```bash
# 1. Provision a temp Postgres host (or use an existing dev box).
sudo systemctl stop postgresql
sudo -u postgres rm -rf /var/lib/postgresql/17/main/*

# 2. Pull pgbackrest config + cipher pass from SSM:
aws ssm get-parameter --name /paymentform/prod/pgbackrest_cipher_pass --with-decryption --query Parameter.Value --output text

# 3. Restore to a specific timestamp:
sudo -u postgres pgbackrest \
  --stanza=main \
  --type=time \
  --target="2026-05-22 02:30:00" \
  --target-action=promote \
  restore

sudo systemctl start postgresql

# 4. Sample-compare against current primary:
psql -U postgres -d paymentform -c "SELECT count(*), max(created_at) FROM payments WHERE created_at < '2026-05-22 02:30:00';"
```

Match the result against the same query on the live primary. Drift > 0 rows = WAL gap or restore target slightly off.

After drill, wipe the temp instance.

## Step 5: Point-in-time recovery (PITR) for production restore

See `database-operations.md` § Restore from Barman-Cloud Backup for the full procedure. Headline:

```bash
sudo -u postgres pgbackrest \
  --stanza=main \
  --type=time \
  --target="2026-05-22 06:00:00" \
  --target-action=promote \
  --delta \
  restore
```

`--delta` re-uses what's already on disk that matches the backup — fast for in-place restores. Drop it for a clean restore.

## Step 6: Rotate the encryption cipher pass

If the pgbackrest cipher pass leaks or rotates per policy.

```bash
# Generate new pass.
openssl rand -base64 48

# Update SSM:
aws ssm put-parameter --name /paymentform/prod/pgbackrest_cipher_pass --value '<NEW>' --type SecureString --overwrite

# On each Postgres host using pgbackrest:
sudo -u postgres pgbackrest --stanza=main stanza-upgrade --cipher-pass=<NEW> --no-online
```

> **Caveat**: existing backups remain encrypted under the **old** pass. To preserve restorability of old backups, keep the old pass alongside the new one in a separate SSM param until retention expires.

## Common issues

| Symptom | Cause | Resolution |
|---|---|---|
| `info` shows `status: error (backup/expire running)` for hours | Stale lockfile from killed run | `ls /var/spool/pgbackrest/lock/`; if no live pgbackrest process, `sudo rm /var/spool/pgbackrest/lock/main-*.lock`. Re-run. |
| `ERROR: [055]: unable to load WAL file` | `archive_command` failed silently; WAL not in R2 | Inspect `archive_command` in `postgresql.conf`. Run a manual `pgbackrest archive-push` against a missing segment. If permanent gap → next full backup re-bootstraps WAL chain. |
| Backups grow continuously, retention not pruning | `repo1-retention-*` not set OR pgbackrest can't delete from R2 | `pgbackrest info` shows count of full backups. If > `repo1-retention-full`, `pgbackrest expire --stanza=main` manually. Validate R2 token has `Delete` on the bucket. |
| `ERROR: [042]: missing repo password` | Stanza expects encryption but `--cipher-pass` not supplied | Confirm `repo1-cipher-type=aes-256-cbc` in conf AND that env / cmdline has the pass. systemd unit must export `PGBACKREST_REPO1_CIPHER_PASS`. |
| `info` reports `WAL archive lag` growing | Network to R2 saturated OR backup-storage creds rotated without restart | `systemctl restart postgresql`-style won't help. Check `journalctl -u postgresql -g archive_command`. Rotate creds via SSM, then `systemctl restart` PG. |
| `barman-cloud-backup` exits 0 but no new backup in R2 | Wrong bucket / endpoint passed | Re-run with `--log-level=debug`; verify `--endpoint-url` uses jurisdictional CF endpoint (default vs eu). |
| Restore says `directory not empty` | `--delta` not used and `pg_data` not pristine | Either `rm -rf` `pg_data/*` then re-run, or add `--delta`. |
| Restore completes but Postgres won't start, "checkpoint record refers to nonexistent WAL" | Restore target_time is past available WAL | Check `pgbackrest info` for actual WAL range; pick a `--target=...` within it. |
| Sequences after restore are behind: duplicate-key errors on next inserts | PITR captures sequence state at the timestamp, not current | Bump sequences post-restore: `SELECT setval(c.oid::regclass, (SELECT max(id)+1 FROM <table>)) FROM pg_class c WHERE relkind = 'S';` (script — see backend `db:fix-sequences` artisan if present). |
| `pgbackrest stanza-create` fails on a fresh instance | `archive_command` not configured first | Order matters: configure pgbackrest.conf + postgresql.conf `archive_command` → restart PG → `stanza-create` → `check`. |

## Wiring checklist (when standing up a new Postgres host)

A condensed version of `database-replica-setup.md` — for the backup side only.

1. Install `pgbackrest` (Ubuntu: `apt install pgbackrest`).
2. `/etc/pgbackrest/pgbackrest.conf` from userdata template. Confirm `repo1-s3-*` use R2 endpoint + creds.
3. Postgres `archive_mode=on`, `archive_command='pgbackrest --stanza=main archive-push %p'`.
4. Restart Postgres.
5. `sudo -u postgres pgbackrest --stanza=main stanza-create`.
6. `sudo -u postgres pgbackrest --stanza=main check` — confirms archive-push and repo are wired.
7. `sudo -u postgres pgbackrest --stanza=main backup --type=full` — initial full.
8. Install daily/weekly cron entries (`/etc/cron.d/pgbackrest`).
9. Add a monitoring entry (see `db-replication.md` § Alerts).

## Off-site copy (paranoid mode)

R2 is durable but single-region against you in the worst case (CF outage + R2 corruption together). If the business needs a second copy:

- Run a second pgbackrest repo to AWS S3 in us-west-2 (`repo2-*` entries).
- Or rclone the R2 bucket to a Backblaze B2 bucket daily.
- Track via `db-backup.md` updates and a runbook entry here.

Not yet implemented in tofu — flag if you need it.
