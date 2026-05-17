#!/bin/bash
set -e

mkdir -p /usr/local/lib
cat > /usr/local/lib/pg-utils.sh <<'PG_UTILS'
log() {
  echo "[ $(date '+%Y-%m-%d %H:%M:%S') ] $1"
}

validate_pgdata_dir() {
  case "$1" in
    /mnt/postgresql/data|/var/lib/pgsql/data) ;;
    *)
      log "Refusing to operate on unexpected PGDATA_DIR: $1"
      exit 1
      ;;
  esac
}

resolve_data_volume() {
  local requested="$1"
  local alternate=""
  local root_source=""
  local root_disk=""
  local candidate=""
  local disk_path=""
  local disk_name=""
  local disk_type=""

  if [[ "$requested" == /dev/sd* ]]; then
    alternate="/dev/xvd$${requested#/dev/sd}"
  elif [[ "$requested" == /dev/xvd* ]]; then
    alternate="/dev/sd$${requested#/dev/xvd}"
  fi

  root_source="$(findmnt -n -o SOURCE / 2>/dev/null || true)"
  if [ -n "$root_source" ]; then
    root_disk="$(lsblk -no PKNAME "$root_source" 2>/dev/null || true)"
    if [ -z "$root_disk" ]; then
      root_disk="$(basename "$root_source")"
    fi
  fi

  for _ in $(seq 1 24); do
    for candidate in "$requested" "$alternate"; do
      if [ -n "$candidate" ] && [ -b "$candidate" ]; then
        printf '%s\n' "$candidate"
        return 0
      fi
    done

    for candidate in /dev/disk/by-id/nvme-Amazon_Elastic_Block_Store_vol*; do
      [ -e "$candidate" ] || continue
      disk_path="$(readlink -f "$candidate")"
      if [ -b "$disk_path" ] && [ "$(basename "$disk_path")" != "$root_disk" ]; then
        printf '%s\n' "$disk_path"
        return 0
      fi
    done

    while read -r disk_name disk_type; do
      [ "$disk_type" = "disk" ] || continue
      [ "$disk_name" = "$root_disk" ] && continue
      disk_path="/dev/$disk_name"
      if [ -b "$disk_path" ]; then
        printf '%s\n' "$disk_path"
        return 0
      fi
    done < <(lsblk -dn -o NAME,TYPE 2>/dev/null)

    sleep 5
  done

  return 1
}
PG_UTILS
chmod +x /usr/local/lib/pg-utils.sh
source /usr/local/lib/pg-utils.sh

install_postgresql() {
  log "PostgreSQL not found, installing..."

  apt-get update -y
  apt-get install -y curl ca-certificates gnupg lsb-release

  curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /usr/share/keyrings/postgresql.gpg
  echo "deb [signed-by=/usr/share/keyrings/postgresql.gpg] http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgsql.list

  apt-get update -y

  apt-get install -y postgresql-${postgres_version} postgresql-client-${postgres_version} postgresql-contrib-${postgres_version}
  apt-get install -y barman barman-cli barman-cli-cloud jq

  log "PostgreSQL and barman installed successfully"
}

install_ssm_agent() {
  if systemctl is-active amazon-ssm-agent >/dev/null 2>&1; then
    log "SSM agent already running"
    return 0
  fi
  log "Installing AWS SSM agent"
  local arch
  arch="$(dpkg --print-architecture)"
  local pkg_url
  case "$arch" in
    amd64) pkg_url="https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/debian_amd64/amazon-ssm-agent.deb" ;;
    arm64) pkg_url="https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/debian_arm64/amazon-ssm-agent.deb" ;;
    *) log "Unknown arch $arch — skipping SSM agent install"; return 0 ;;
  esac
  curl -fsSL "$pkg_url" -o /tmp/amazon-ssm-agent.deb
  dpkg -i /tmp/amazon-ssm-agent.deb
  rm -f /tmp/amazon-ssm-agent.deb
  systemctl enable amazon-ssm-agent
  systemctl start amazon-ssm-agent
  log "SSM agent installed and started"
}

check_postgresql_installed() {
  if command -v psql >/dev/null 2>&1; then
    return 0
  fi
  if compgen -G "/usr/lib/postgresql/*/bin/psql" >/dev/null; then
    return 0
  fi
  return 1
}

if ! check_postgresql_installed; then
  install_postgresql
else
  log "PostgreSQL is already installed"
fi

install_ssm_agent

if systemctl is-active postgresql >/dev/null 2>&1; then
  systemctl stop postgresql || true
fi

DATA_VOLUME="${data_volume_device}"
MOUNT_POINT="/mnt/postgresql"
PGDATA_DIR="$MOUNT_POINT/data"

if ! getent group postgres >/dev/null; then
    groupadd --system postgres
fi

if ! id postgres >/dev/null 2>&1; then
    useradd --system --gid postgres --home-dir /var/lib/pgsql --shell /bin/bash postgres
fi

REQUESTED_DATA_VOLUME="$DATA_VOLUME"
DATA_VOLUME="$(resolve_data_volume "$REQUESTED_DATA_VOLUME" || true)"

cat > /usr/local/bin/mount-postgresql-data.sh <<'MOUNT_SCRIPT'
#!/bin/bash
set -e
source /usr/local/lib/pg-utils.sh

MOUNT_POINT="/mnt/postgresql"
REQUESTED_DATA_VOLUME="$1"
DATA_VOLUME="$(resolve_data_volume "$REQUESTED_DATA_VOLUME" || true)"

if [ -z "$DATA_VOLUME" ] || [ ! -b "$DATA_VOLUME" ]; then
  echo "Data volume not found"
  exit 1
fi

echo "Using data volume $DATA_VOLUME"

if ! blkid "$DATA_VOLUME" >/dev/null 2>&1; then
  mkfs -t ext4 "$DATA_VOLUME"
fi

mkdir -p "$MOUNT_POINT"

if ! mountpoint -q "$MOUNT_POINT"; then
  mount "$DATA_VOLUME" "$MOUNT_POINT"
fi

FSTAB_SOURCE="$(blkid -s UUID -o value "$DATA_VOLUME" 2>/dev/null || true)"
if [ -n "$FSTAB_SOURCE" ]; then
  FSTAB_SOURCE="UUID=$FSTAB_SOURCE"
else
  FSTAB_SOURCE="$DATA_VOLUME"
fi

if ! grep -qF "$MOUNT_POINT" /etc/fstab; then
  echo "$FSTAB_SOURCE $MOUNT_POINT ext4 defaults,nofail 0 2" >> /etc/fstab
fi

mkdir -p "$MOUNT_POINT/data"
chown postgres:postgres "$MOUNT_POINT"
chown -R postgres:postgres "$MOUNT_POINT/data"
chmod 700 "$MOUNT_POINT/data"

echo "Mount complete"
MOUNT_SCRIPT

chmod +x /usr/local/bin/mount-postgresql-data.sh

cat > /etc/systemd/system/postgresql-data-mount.service <<EOF
[Unit]
Description=Mount PostgreSQL data volume
Before=postgresql.service

[Service]
Type=oneshot
RemainAfterExit=yes
ConditionPathIsMountPoint=!/mnt/postgresql
ExecStart=/usr/local/bin/mount-postgresql-data.sh $REQUESTED_DATA_VOLUME
EOF

systemctl daemon-reload
systemctl enable postgresql-data-mount.service

log "Starting postgresql-data-mount.service..."
if systemctl start postgresql-data-mount.service; then
  log "Data volume mount service completed"
else
  log "Data volume mount service failed or timed out"
fi

if mountpoint -q "$MOUNT_POINT"; then
  PGDATA_DIR="$MOUNT_POINT/data"
  chown postgres:postgres "$MOUNT_POINT"
  chown -R postgres:postgres "$PGDATA_DIR"
  chmod 700 "$PGDATA_DIR"
else
  log "Data volume $REQUESTED_DATA_VOLUME not found or not mounted, using default location"
  PGDATA_DIR="/var/lib/pgsql/data"
  mkdir -p "$PGDATA_DIR"
  chown postgres:postgres /var/lib/pgsql
  chown -R postgres:postgres "$PGDATA_DIR"
  chmod 700 "$PGDATA_DIR"
fi

validate_pgdata_dir "$PGDATA_DIR"

# Avoid full system upgrades during first boot; they can leave core packages
# in a bad state if cloud-init is interrupted or a reboot is deferred.

mkdir -p "$PGDATA_DIR"
chown -R postgres:postgres "$PGDATA_DIR"
chmod 700 "$PGDATA_DIR"

mkdir -p "/etc/systemd/system/postgresql.service.d"

UNIT_SECTION=""
if [ "$PGDATA_DIR" = "$MOUNT_POINT/data" ]; then
    UNIT_SECTION="[Unit]
After=postgresql-data-mount.service
Requires=postgresql-data-mount.service
"
fi

cat > "/etc/systemd/system/postgresql.service.d/override.conf" <<EOF
$UNIT_SECTION
[Service]
Environment=PGDATA=$PGDATA_DIR
EOF
systemctl daemon-reload

PGCONF_FILE="/etc/postgresql/${postgres_version}/main/postgresql.conf"
PG_HBA_SYSTEM_FILE="/etc/postgresql/${postgres_version}/main/pg_hba.conf"

BARMAN_SERVER_NAME="${environment}-postgresql-primary"
BARMAN_DESTINATION="s3://${database_backup_bucket_name}/postgresql"
BARMAN_COMMON_OPTS="--cloud-provider aws-s3 --endpoint-url ${database_backup_bucket_endpoint}"

export AWS_REQUEST_CHECKSUM_CALCULATION=when_required
export AWS_RESPONSE_CHECKSUM_VALIDATION=when_required
export AWS_ACCESS_KEY_ID="${database_backup_bucket_access_key_id}"
export AWS_SECRET_ACCESS_KEY="${database_backup_bucket_access_key}"

RESTORE_BACKUP_VAL="false"
if [ -z "$(ls -A $PGDATA_DIR 2>/dev/null)" ]; then
    log "Data directory is empty, checking for barman backups..."
    LATEST_BACKUP_ID="$(sudo -u postgres \
      AWS_REQUEST_CHECKSUM_CALCULATION=when_required \
      AWS_RESPONSE_CHECKSUM_VALIDATION=when_required \
      AWS_ACCESS_KEY_ID="${database_backup_bucket_access_key_id}" \
      AWS_SECRET_ACCESS_KEY="${database_backup_bucket_access_key}" \
      barman-cloud-backup-list $BARMAN_COMMON_OPTS --format json "$BARMAN_DESTINATION" "$BARMAN_SERVER_NAME" 2>/dev/null \
      | jq -r '.backups_list | sort_by(.end_time) | last | .backup_id // empty')"
    if [ -n "$LATEST_BACKUP_ID" ]; then
        RESTORE_BACKUP_VAL="true"
    fi
fi

if [ "$RESTORE_BACKUP_VAL" = "true" ]; then
    log "Restoring from barman backup..."
    chown -R postgres:postgres "$PGDATA_DIR"
    chmod 700 "$PGDATA_DIR"

    systemctl stop postgresql 2>/dev/null || true

    sudo -u postgres \
      AWS_REQUEST_CHECKSUM_CALCULATION=when_required \
      AWS_RESPONSE_CHECKSUM_VALIDATION=when_required \
      AWS_ACCESS_KEY_ID="${database_backup_bucket_access_key_id}" \
      AWS_SECRET_ACCESS_KEY="${database_backup_bucket_access_key}" \
      barman-cloud-restore $BARMAN_COMMON_OPTS "$BARMAN_DESTINATION" "$BARMAN_SERVER_NAME" "$LATEST_BACKUP_ID" "$PGDATA_DIR"
    log "Backup restored successfully"
else
    log "Initializing new PostgreSQL data directory..."
    PG_INITDB=$(find /usr/lib/postgresql -name initdb -type f 2>/dev/null | head -1)

    if [ -n "$PG_INITDB" ]; then
        su - postgres -c "$PG_INITDB -D '$PGDATA_DIR'"
    else
        pg_createcluster ${postgres_version} main -- -D "$PGDATA_DIR" || true
    fi

    chown -R postgres:postgres "$PGDATA_DIR"
    chmod 700 "$PGDATA_DIR"
fi

echo "data_directory = '$PGDATA_DIR'" >> "$PGCONF_FILE"
echo "listen_addresses = '*'" >> "$PGCONF_FILE"
echo "max_wal_senders = 3" >> "$PGCONF_FILE"
echo "max_replication_slots = 3" >> "$PGCONF_FILE"
echo "wal_level = replica" >> "$PGCONF_FILE"
echo "hot_standby = on" >> "$PGCONF_FILE"
echo "archive_mode = on" >> "$PGCONF_FILE"
echo "archive_command = 'AWS_REQUEST_CHECKSUM_CALCULATION=when_required AWS_RESPONSE_CHECKSUM_VALIDATION=when_required AWS_ACCESS_KEY_ID=${database_backup_bucket_access_key_id} AWS_SECRET_ACCESS_KEY=${database_backup_bucket_access_key} barman-cloud-wal-archive --cloud-provider aws-s3 --endpoint-url ${database_backup_bucket_endpoint} s3://${database_backup_bucket_name}/postgresql ${environment}-postgresql-primary %p'" >> "$PGCONF_FILE"
echo "archive_timeout = 300" >> "$PGCONF_FILE"

if ! grep -q '^# === BEGIN MANAGED TUNING ===' "$PGCONF_FILE" 2>/dev/null; then
cat >> "$PGCONF_FILE" <<'PG_TUNING'
# === BEGIN MANAGED TUNING ===
# Memory
shared_buffers = 1GB
effective_cache_size = 3GB
work_mem = 8MB
maintenance_work_mem = 256MB
huge_pages = try

# Connections
max_connections = 200

# WAL / Checkpoints
wal_buffers = 16MB
checkpoint_timeout = 15min
checkpoint_completion_target = 0.9
min_wal_size = 1GB
max_wal_size = 4GB
wal_keep_size = 1GB
wal_compression = on

# Storage / IO (gp3 SSD)
random_page_cost = 1.1
effective_io_concurrency = 200

# Parallelism (2 vCPU instance)
max_worker_processes = 4
max_parallel_workers = 2
max_parallel_workers_per_gather = 1

# Safety — do NOT relax for a payments app
synchronous_commit = on
statement_timeout = 60s
idle_in_transaction_session_timeout = 60s

# Observability
log_min_duration_statement = 500
log_checkpoints = on
log_lock_waits = on
track_io_timing = on
shared_preload_libraries = 'pg_stat_statements'
pg_stat_statements.track = top
pg_stat_statements.max = 10000
# === END MANAGED TUNING ===
PG_TUNING
fi

echo "host     all             all             10.0.0.0/16           trust" >> $PG_HBA_SYSTEM_FILE
echo "host     all             all             127.0.0.1/32          scram-sha-256" >> $PG_HBA_SYSTEM_FILE
echo "host     replication     replicator      10.0.0.0/16           md5" >> $PG_HBA_SYSTEM_FILE
echo "host     replication     replicator      127.0.0.1/32          md5" >> $PG_HBA_SYSTEM_FILE
${peer_vpc_cidrs_hba}
${hetzner_cidrs_hba}

systemctl enable postgresql
systemctl start postgresql

# === pgbouncer install + auth_query setup ===
log "Installing pgbouncer..."
apt-get install -y pgbouncer

# Generate a random password for the internal pgbouncer auth user.
# This user only authenticates pgbouncer -> postgres for the credential lookup.
PGBOUNCER_AUTH_PASS=$(openssl rand -hex 32)

# Create (or rotate) the pgbouncer_auth role and the lookup function.
# SECURITY DEFINER lets pgbouncer_auth read pg_shadow via this function only,
# without granting pg_shadow access directly. The role's cleartext password
# is written to userlist.txt below so pgbouncer can authenticate to Postgres
# itself via scram-sha-256 (pgbouncer cannot derive a SCRAM client response
# from just the stored verifier — it needs the cleartext, or its own SCRAM
# secret entry, neither of which exists if we only read pg_shadow).
if sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='pgbouncer_auth'" | grep -q 1; then
  # Rotate password to match this run so userlist.txt below is in sync.
  sudo -u postgres psql -v ON_ERROR_STOP=1 -c "ALTER ROLE pgbouncer_auth WITH PASSWORD '$${PGBOUNCER_AUTH_PASS}'"
else
  sudo -u postgres psql -v ON_ERROR_STOP=1 <<SQL
CREATE ROLE pgbouncer_auth WITH LOGIN PASSWORD '$${PGBOUNCER_AUTH_PASS}';
SQL
fi

# Function lives in the postgres db (lookups go through auth_dbname=postgres
# below). CREATE OR REPLACE so updating the function signature is idempotent.
sudo -u postgres psql -v ON_ERROR_STOP=1 <<'SQL'
CREATE OR REPLACE FUNCTION public.lookup_pg_user(uname text)
RETURNS TABLE(usename text, passwd text)
LANGUAGE sql SECURITY DEFINER AS $$
    SELECT usename::text, passwd::text
    FROM pg_shadow
    WHERE usename = uname;
$$;

REVOKE ALL ON FUNCTION public.lookup_pg_user(text) FROM public;
GRANT EXECUTE ON FUNCTION public.lookup_pg_user(text) TO pgbouncer_auth;
SQL

# userlist.txt for pgbouncer client auth + its own server auth.
# CLEARTEXT for pgbouncer_auth so pgbouncer can run SCRAM with PG.
# Other users are looked up dynamically via auth_query.
mkdir -p /etc/pgbouncer
printf '"pgbouncer_auth" "%s"\n' "$${PGBOUNCER_AUTH_PASS}" > /etc/pgbouncer/userlist.txt

chown postgres:postgres /etc/pgbouncer/userlist.txt
chmod 640 /etc/pgbouncer/userlist.txt

cat > /etc/pgbouncer/pgbouncer.ini <<'INI'
[databases]
* = host=127.0.0.1 port=5432

[pgbouncer]
listen_addr = 0.0.0.0
listen_port = 6432
auth_type = scram-sha-256
auth_file = /etc/pgbouncer/userlist.txt
auth_user = pgbouncer_auth
auth_query = SELECT usename, passwd FROM public.lookup_pg_user($1)
auth_dbname = postgres
pool_mode = transaction
max_client_conn = 1000
default_pool_size = 25
reserve_pool_size = 5
reserve_pool_timeout = 3
server_idle_timeout = 600
server_lifetime = 3600
log_connections = 0
log_disconnections = 0
log_pooler_errors = 1
stats_period = 60
admin_users = postgres
INI

chown postgres:postgres /etc/pgbouncer/pgbouncer.ini
chmod 640 /etc/pgbouncer/pgbouncer.ini

systemctl enable pgbouncer
systemctl restart pgbouncer

log "pgbouncer installed and started"

%{ if tunnel_token != "" ~}
log "Installing cloudflared for DB tunnel"
curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | gpg --dearmor -o /usr/share/keyrings/cloudflare.gpg
echo "deb [signed-by=/usr/share/keyrings/cloudflare.gpg] https://pkg.cloudflare.com/cloudflared any main" > /etc/apt/sources.list.d/cloudflared.list
apt-get update -y
apt-get install -y cloudflared

mkdir -p /etc/cloudflared
chmod 700 /etc/cloudflared

cat > /etc/cloudflared/token.env <<'ENVEOF'
TUNNEL_TOKEN=${tunnel_token}
ENVEOF
chmod 600 /etc/cloudflared/token.env

cat > /etc/systemd/system/cloudflared.service <<'SYSTEMDEOF'
[Unit]
Description=Cloudflare Tunnel
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
Restart=on-failure
RestartSec=10
StartLimitInterval=60
StartLimitBurst=3

EnvironmentFile=/etc/cloudflared/token.env
ExecStart=/usr/bin/cloudflared tunnel --no-autoupdate run
ExecReload=/bin/kill -HUP $MAINPID

NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/etc/cloudflared /tmp /var/tmp
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictSUIDSGID=true
RestrictRealtime=true
RestrictNamespaces=true
LockPersonality=true
MemoryDenyWriteExecute=true
SystemCallArchitectures=native
SystemCallFilter=@system-service
CapabilityBoundingSet=

LimitNOFILE=65536
LimitNPROC=4096

[Install]
WantedBy=multi-user.target
SYSTEMDEOF

systemctl daemon-reload
systemctl enable cloudflared
systemctl start cloudflared

cat > /usr/local/bin/cloudflared-healthcheck.sh <<'HEALTHEOF'
#!/bin/bash
set -e

pgrep -x cloudflared >/dev/null || {
  logger -t cloudflared "Health check failed: process not running"
  exit 1
}

if command -v curl >/dev/null 2>&1; then
  curl -fsS http://localhost:35679/metrics >/dev/null 2>&1 || {
    logger -t cloudflared "Health check warning: metrics endpoint not reachable"
  }
fi
HEALTHEOF
chmod +x /usr/local/bin/cloudflared-healthcheck.sh

echo "* * * * * root /usr/local/bin/cloudflared-healthcheck.sh || systemctl restart cloudflared" > /etc/cron.d/cloudflared-healthcheck
chmod 644 /etc/cron.d/cloudflared-healthcheck

log "cloudflared DB tunnel started"
%{ endif ~}

sleep 5

if [ "$RESTORE_BACKUP_VAL" = "true" ]; then
    log "PostgreSQL restored from backup and started"
else
    su - postgres -c "psql -c \"CREATE DATABASE ${db_name};\" 2>/dev/null || true"
    su - postgres -c "psql -c \"ALTER USER postgres WITH PASSWORD '${db_password}';\""
    su - postgres -c "psql -c \"CREATE USER ${db_user} WITH LOGIN PASSWORD '${db_password}';\" 2>/dev/null || true"
    su - postgres -c "psql -c \"GRANT ALL PRIVILEGES ON DATABASE ${db_name} TO ${db_user};\""
    su - postgres -c "psql -d ${db_name} -c \"GRANT ALL ON SCHEMA public TO ${db_user};\""
    su - postgres -c "psql -c \"CREATE USER replicator WITH REPLICATION PASSWORD '${db_password}';\" 2>/dev/null || true"
    log "PostgreSQL primary setup complete"
fi

if [ "$RESTORE_BACKUP_VAL" = "false" ]; then
    log "Creating initial barman backup..."
    sudo -u postgres \
      AWS_REQUEST_CHECKSUM_CALCULATION=when_required \
      AWS_RESPONSE_CHECKSUM_VALIDATION=when_required \
      AWS_ACCESS_KEY_ID="${database_backup_bucket_access_key_id}" \
      AWS_SECRET_ACCESS_KEY="${database_backup_bucket_access_key}" \
      barman-cloud-backup $BARMAN_COMMON_OPTS "$BARMAN_DESTINATION" "$BARMAN_SERVER_NAME" || log "Initial backup failed"
fi

BARMAN_ENV="AWS_REQUEST_CHECKSUM_CALCULATION=when_required AWS_RESPONSE_CHECKSUM_VALIDATION=when_required AWS_ACCESS_KEY_ID=${database_backup_bucket_access_key_id} AWS_SECRET_ACCESS_KEY=${database_backup_bucket_access_key}"
BARMAN_BACKUP_CMD="$BARMAN_ENV barman-cloud-backup $BARMAN_COMMON_OPTS $BARMAN_DESTINATION $BARMAN_SERVER_NAME"
BARMAN_CLEANUP_CMD="$BARMAN_ENV barman-cloud-backup-delete $BARMAN_COMMON_OPTS --retention-policy 'RECOVERY WINDOW OF 15 DAYS' $BARMAN_DESTINATION $BARMAN_SERVER_NAME"
cat > /etc/cron.d/barman-backup <<CRON
0 2 * * * postgres $BARMAN_BACKUP_CMD >> /var/log/barman-backup.log 2>&1
30 2 * * * postgres $BARMAN_CLEANUP_CMD >> /var/log/barman-backup.log 2>&1
CRON
chmod 644 /etc/cron.d/barman-backup
log "Nightly barman backup + 15-day retention cleanup cron configured (02:00/02:30 UTC)"
