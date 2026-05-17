#!/bin/bash
set -e

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

escape_pgpass_field() {
  printf '%s' "$1" | sed 's/[\\:]/\\&/g'
}

install_postgresql() {
  log "PostgreSQL not found, installing..."

  apt-get update -y
  apt-get install -y curl ca-certificates gnupg lsb-release

  curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /usr/share/keyrings/postgresql.gpg
  echo "deb [signed-by=/usr/share/keyrings/postgresql.gpg] http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgsql.list

  apt-get update -y
  apt-get install -y postgresql-${postgres_version} postgresql-client-${postgres_version} postgresql-contrib-${postgres_version}

  log "PostgreSQL installed successfully"
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

if systemctl is-active postgresql >/dev/null 2>&1; then
  systemctl stop postgresql || true
fi

DATA_VOLUME="${data_volume_device}"
MOUNT_POINT="/mnt/postgresql"
PGDATA_DIR="$MOUNT_POINT/data"

if ! getent group postgres >/dev/null; then
    POSTGRES_GID=""
    for candidate_gid in 26 490 491 492 493 494 495; do
        if ! getent group "$candidate_gid" >/dev/null 2>&1; then
            POSTGRES_GID="$candidate_gid"
            break
        fi
    done
    if [ -n "$POSTGRES_GID" ]; then
        groupadd --system --gid "$POSTGRES_GID" postgres
    else
        groupadd --system postgres
    fi
fi

if ! id postgres >/dev/null 2>&1; then
    POSTGRES_UID=""
    POSTGRES_GID_VAL="$(getent group postgres | cut -d: -f3)"
    for candidate_uid in 26 490 491 492 493 494 495; do
        if ! getent passwd "$candidate_uid" >/dev/null 2>&1; then
            POSTGRES_UID="$candidate_uid"
            break
        fi
    done
    if [ -n "$POSTGRES_UID" ]; then
        useradd --system --uid "$POSTGRES_UID" --gid postgres --home-dir /var/lib/pgsql --shell /bin/bash postgres
    else
        useradd --system --gid postgres --home-dir /var/lib/pgsql --shell /bin/bash postgres
    fi
fi

REQUESTED_DATA_VOLUME="$DATA_VOLUME"
DATA_VOLUME="$(resolve_data_volume "$REQUESTED_DATA_VOLUME" || true)"

if [ -n "$DATA_VOLUME" ] && [ -b "$DATA_VOLUME" ]; then
    log "Using data volume $DATA_VOLUME"
    if ! blkid "$DATA_VOLUME" >/dev/null 2>&1; then
        mkfs -t ext4 "$DATA_VOLUME"
    fi

    mkdir -p "$MOUNT_POINT"

    if ! mountpoint -q "$MOUNT_POINT"; then
        mount "$DATA_VOLUME" "$MOUNT_POINT"
    fi

    if ! grep -q "^$DATA_VOLUME $MOUNT_POINT ext4 defaults,nofail 0 2$" /etc/fstab; then
        echo "$DATA_VOLUME $MOUNT_POINT ext4 defaults,nofail 0 2" >> /etc/fstab
    fi

    mkdir -p "$PGDATA_DIR"
    chown postgres:postgres "$MOUNT_POINT"
    chown -R --no-dereference postgres:postgres "$PGDATA_DIR"
    chmod 700 "$PGDATA_DIR"
else
    log "Data volume $REQUESTED_DATA_VOLUME not found, using default location"
    PGDATA_DIR="/var/lib/pgsql/data"
    mkdir -p "$PGDATA_DIR"
    chown postgres:postgres /var/lib/pgsql
    chown -R --no-dereference postgres:postgres "$PGDATA_DIR"
    chmod 700 "$PGDATA_DIR"
fi

validate_pgdata_dir "$PGDATA_DIR"

mkdir -p "$PGDATA_DIR"
chown -R --no-dereference postgres:postgres "$PGDATA_DIR"
chmod 700 "$PGDATA_DIR"

mkdir -p "/etc/systemd/system/postgresql.service.d"
cat > "/etc/systemd/system/postgresql.service.d/override.conf" <<EOF
[Service]
Environment=PGDATA=$PGDATA_DIR
EOF
systemctl daemon-reload

PGCONF_FILE="$PGDATA_DIR/postgresql.conf"
PGPASS_FILE="/var/lib/pgsql/.pgpass"

install -d -o postgres -g postgres -m 0700 "$(dirname "$PGPASS_FILE")"
install -o postgres -g postgres -m 0600 /dev/null "$PGPASS_FILE"
printf '%s\n' "${primary_ip}:5432:replication:replicator:$(escape_pgpass_field "${db_password}")" > "$PGPASS_FILE"
chown postgres:postgres "$PGPASS_FILE"
chmod 600 "$PGPASS_FILE"

NEED_BASEBACKUP="true"
if [ -f "$PGDATA_DIR/PG_VERSION" ] && [ -f "$PGDATA_DIR/standby.signal" ] && grep -q "^primary_conninfo = '.*host=${primary_ip}.*user=replicator.*passfile=$${PGPASS_FILE}.*'" "$PGDATA_DIR/postgresql.auto.conf" 2>/dev/null; then
    NEED_BASEBACKUP="false"
    log "Existing standby data found in $PGDATA_DIR, skipping base backup"
fi

if [ "$NEED_BASEBACKUP" = "true" ]; then
    if [ -n "$(ls -A "$PGDATA_DIR" 2>/dev/null)" ]; then
        log "Existing data directory is not a valid standby, reseeding replica"
        rm -rf "$${PGDATA_DIR:?}"
    fi

    mkdir -p "$PGDATA_DIR"
    chown -R --no-dereference postgres:postgres "$PGDATA_DIR"
    chmod 700 "$PGDATA_DIR"

    # Drop any pre-existing replication slot on primary so `pg_basebackup -C`
    # below can recreate it idempotently. pg_hba trusts the VPC for regular
    # SQL, so replicator can manage slots without a password.
    log "Dropping any pre-existing replication slot 'paymentform_replica' on primary..."
    runuser -u postgres -- psql -X -h "${primary_ip}" -p 5432 -U replicator -d postgres -tAc \
      "SELECT pg_drop_replication_slot('paymentform_replica') FROM pg_replication_slots WHERE slot_name='paymentform_replica'" \
      || log "slot drop returned non-zero (may have been absent)"

    log "Starting base backup from primary ${primary_ip}..."
    runuser -u postgres -- env PGPASSFILE="$PGPASS_FILE" pg_basebackup -D "$PGDATA_DIR" -d "host=${primary_ip} port=5432 user=replicator dbname=replication passfile=$${PGPASS_FILE}" -v -P -w -R -C --slot=paymentform_replica
fi

if ! grep -q '^hot_standby = on$' "$PGCONF_FILE" 2>/dev/null; then
    echo "hot_standby = on" >> "$PGCONF_FILE"
fi

if grep -q "^data_directory" "$PGCONF_FILE" 2>/dev/null; then
    sed -i "s|^data_directory\s*=.*|data_directory = '$PGDATA_DIR'|" "$PGCONF_FILE"
fi

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

# Replica-specific
hot_standby_feedback = on
max_standby_streaming_delay = 30s
# === END MANAGED TUNING ===
PG_TUNING
fi

chown -R --no-dereference postgres:postgres "$PGDATA_DIR"
chmod 700 "$PGDATA_DIR"

systemctl enable postgresql
systemctl start postgresql

log "PostgreSQL replica setup complete"

# === pgbouncer install + auth_query setup (replica) ===
# On replica: role and lookup function come from primary via replication.
# We regenerate userlist.txt from local pg_shadow and start pgbouncer.
log "Installing pgbouncer on replica..."
apt-get install -y pgbouncer

# Wait for pgbouncer_auth role to be replicated from primary (up to 60s).
log "Waiting for pgbouncer_auth role to replicate from primary..."
for i in $(seq 1 60); do
  if sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='pgbouncer_auth'" 2>/dev/null | grep -q 1; then
    log "pgbouncer_auth role replicated after $${i}s"
    break
  fi
  sleep 1
done

if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='pgbouncer_auth'" 2>/dev/null | grep -q 1; then
  log "ERROR: pgbouncer_auth role did not replicate within 60s. pgbouncer will not start with valid auth."
  exit 1
fi

# Query pg_shadow to get the SCRAM-SHA-256 hash that postgres stored.
# This is exactly the format pgbouncer expects in userlist.txt.
mkdir -p /etc/pgbouncer
sudo -u postgres psql -t -A -c \
  "SELECT '\"'||usename||'\" \"'||passwd||'\"' FROM pg_shadow WHERE usename='pgbouncer_auth'" \
  > /etc/pgbouncer/userlist.txt

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

log "pgbouncer installed and started on replica"
