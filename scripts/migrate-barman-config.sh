#!/usr/bin/env bash
#
# migrate-barman-config.sh
#
# One-shot migration of the running PostgreSQL primary to:
#   - WAL archive compressed with --gzip
#   - archive_timeout = 12h (was 5min)
#   - 7-day RECOVERY WINDOW retention (was 15-day)
#   - Bucket purged of every base backup older than a freshly-taken gzipped anchor
#     and every WAL not needed by that anchor (REDUNDANCY 1 one-shot).
#
# Run as root on the primary EC2. Idempotent: re-running after success is a no-op
# except for taking another fresh backup and re-pruning to 1.
#
# Companion to iaac/providers/aws/database/userdata-primary.sh — that file owns the
# config for newly-provisioned instances; this script applies the same config to
# an already-running instance plus wipes the legacy uncompressed bucket contents.

set -euo pipefail

# ---- Required env (export before running, or edit defaults below) ----
: "${ENVIRONMENT:=prod}"
: "${BUCKET_NAME:?BUCKET_NAME must be set (R2 bucket holding postgresql/ prefix)}"
: "${R2_ENDPOINT:?R2_ENDPOINT must be set (e.g. https://<acct>.r2.cloudflarestorage.com)}"
: "${AWS_ACCESS_KEY_ID:?AWS_ACCESS_KEY_ID must be set}"
: "${AWS_SECRET_ACCESS_KEY:?AWS_SECRET_ACCESS_KEY must be set}"

BARMAN_SERVER_NAME="${ENVIRONMENT}-postgresql-primary"
BARMAN_DESTINATION="s3://${BUCKET_NAME}/postgresql"
BARMAN_COMMON_OPTS="--cloud-provider aws-s3 --endpoint-url ${R2_ENDPOINT}"

export AWS_REQUEST_CHECKSUM_CALCULATION=when_required
export AWS_RESPONSE_CHECKSUM_VALIDATION=when_required

PG_VERSION="$(pg_lsclusters -h | awk 'NR==1{print $1}')"
PGCONF="/etc/postgresql/${PG_VERSION}/main/postgresql.conf"

log() { printf '\n=== %s ===\n' "$*"; }

# Run a command as postgres, explicitly forwarding the R2 + boto env.
# `sudo -E` is blocked by default sudoers config on Ubuntu, so we use
# `sudo -u postgres env ...` and pass each variable inline.
# PGOPTIONS disables statement_timeout for the libpq connection barman opens,
# otherwise the managed `statement_timeout = 60s` kills pg_backup_stop.
as_postgres() {
    sudo -u postgres env \
        AWS_REQUEST_CHECKSUM_CALCULATION=when_required \
        AWS_RESPONSE_CHECKSUM_VALIDATION=when_required \
        AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" \
        AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" \
        PGOPTIONS="-c statement_timeout=0" \
        "$@"
}

# Set MIGRATE_BARMAN_NONINTERACTIVE=1 to skip the two confirmation prompts
# (required when running via SSM or any other non-TTY context).
confirm() {
    local prompt="$1"
    if [[ "${MIGRATE_BARMAN_NONINTERACTIVE:-0}" == "1" ]]; then
        echo "${prompt} [auto-confirmed via MIGRATE_BARMAN_NONINTERACTIVE]"
        return 0
    fi
    read -r -p "${prompt} [type YES to proceed]: " ans
    [[ "$ans" == "YES" ]] || { echo "Aborted."; exit 1; }
}

# ---- 0. Pre-flight: stale replication slot would refill WAL right back ----
log "Replication slots"
sudo -u postgres psql -c "
SELECT slot_name, active,
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS retained
FROM pg_replication_slots;"
echo "If any slot above is inactive with large 'retained', abort and drop it first:"
echo "  sudo -u postgres psql -c \"SELECT pg_drop_replication_slot('<slot>');\""
confirm "Slots are healthy, continue?"

# ---- 1. Apply new Postgres config (no restart) ----
log "Applying ALTER SYSTEM (archive_command + archive_timeout)"
# IMPORTANT: archive_command is run by the postgres daemon, which does NOT have
# AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY in its environment. The keys must be
# baked into the string as literals, not $VAR references — otherwise the archiver
# will fail every WAL upload, fill failed_count rapidly, and pg_backup_stop will
# hang indefinitely waiting for WAL to be archived.
NEW_ARCHIVE_CMD="AWS_REQUEST_CHECKSUM_CALCULATION=when_required AWS_RESPONSE_CHECKSUM_VALIDATION=when_required AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} barman-cloud-wal-archive --cloud-provider aws-s3 --endpoint-url ${R2_ENDPOINT} --gzip ${BARMAN_DESTINATION} ${BARMAN_SERVER_NAME} %p"

sudo -u postgres psql <<SQL
ALTER SYSTEM SET archive_timeout = '12h';
ALTER SYSTEM SET archive_command = '${NEW_ARCHIVE_CMD}';
SELECT pg_reload_conf();
SHOW archive_timeout;
SHOW archive_command;
SQL

# Cosmetic: strip the legacy direct lines so postgresql.conf doesn't drift from auto.conf
sed -i.bak -E '/^archive_timeout *=/d; /^archive_command *=/d' "$PGCONF"

# ---- 2. Update cron to use --gzip + 7-day retention going forward ----
log "Rewriting /etc/cron.d/barman-backup"
cat > /etc/cron.d/barman-backup <<CRON
0 2 * * * postgres AWS_REQUEST_CHECKSUM_CALCULATION=when_required AWS_RESPONSE_CHECKSUM_VALIDATION=when_required AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} barman-cloud-backup ${BARMAN_COMMON_OPTS} --gzip ${BARMAN_DESTINATION} ${BARMAN_SERVER_NAME} >> /var/log/barman-backup.log 2>&1
30 2 * * * postgres AWS_REQUEST_CHECKSUM_CALCULATION=when_required AWS_RESPONSE_CHECKSUM_VALIDATION=when_required AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} barman-cloud-backup-delete ${BARMAN_COMMON_OPTS} --retention-policy 'RECOVERY WINDOW OF 7 DAYS' ${BARMAN_DESTINATION} ${BARMAN_SERVER_NAME} >> /var/log/barman-backup.log 2>&1
CRON
chmod 644 /etc/cron.d/barman-backup

# ---- 3. Fresh gzipped anchor backup ----
log "Taking fresh gzipped base backup (this is the new recovery anchor)"
as_postgres barman-cloud-backup ${BARMAN_COMMON_OPTS} --gzip \
  "${BARMAN_DESTINATION}" "${BARMAN_SERVER_NAME}"

log "Backups after anchor"
as_postgres barman-cloud-backup-list ${BARMAN_COMMON_OPTS} \
  "${BARMAN_DESTINATION}" "${BARMAN_SERVER_NAME}"

# ---- 4. NUKE: keep ONLY the fresh anchor, delete everything older + orphan WALs ----
echo
echo "About to delete every base backup older than the fresh anchor and every WAL"
echo "not needed by the anchor. This is irreversible."
confirm "Proceed with REDUNDANCY 1 purge?"

log "Pruning to REDUNDANCY 1"
as_postgres barman-cloud-backup-delete ${BARMAN_COMMON_OPTS} \
  --retention-policy 'REDUNDANCY 1' \
  "${BARMAN_DESTINATION}" "${BARMAN_SERVER_NAME}"

# ---- 5. Verify ----
log "Backups remaining"
as_postgres barman-cloud-backup-list ${BARMAN_COMMON_OPTS} \
  "${BARMAN_DESTINATION}" "${BARMAN_SERVER_NAME}"

log "Remaining backup details (size shown per backup)"
LATEST_ID="$(as_postgres barman-cloud-backup-list ${BARMAN_COMMON_OPTS} --format json \
  "${BARMAN_DESTINATION}" "${BARMAN_SERVER_NAME}" \
  | jq -r '.backups_list | sort_by(.end_time) | last | .backup_id // empty')"
if [[ -n "${LATEST_ID}" ]]; then
    as_postgres barman-cloud-backup-show ${BARMAN_COMMON_OPTS} \
      "${BARMAN_DESTINATION}" "${BARMAN_SERVER_NAME}" "${LATEST_ID}" || true
fi

log "Done"
echo "Going forward, /etc/cron.d/barman-backup runs nightly at 02:00 / 02:30 UTC:"
echo "  - 02:00 barman-cloud-backup --gzip"
echo "  - 02:30 barman-cloud-backup-delete --retention-policy 'RECOVERY WINDOW OF 7 DAYS'"
