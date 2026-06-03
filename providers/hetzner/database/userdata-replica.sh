#!/bin/bash
set -e

log() {
  echo "[ $(date '+%Y-%m-%d %H:%M:%S') ] $1"
}

escape_pgpass_field() {
  printf '%s' "$1" | sed 's/[\\:]/\\&/g'
}

export DEBIAN_FRONTEND=noninteractive

log "Creating OS user: ${os_username}"
id "${os_username}" &>/dev/null || useradd -m -s /bin/bash "${os_username}"

for grp in docker sudo; do
  if getent group "$grp" >/dev/null 2>&1; then
    usermod -aG "$grp" "${os_username}"
  fi
done

%{ if os_user_public_key != "" ~}
mkdir -p /home/${os_username}/.ssh
chmod 700 /home/${os_username}/.ssh
cat > /home/${os_username}/.ssh/authorized_keys <<'SSHEOF'
${os_user_public_key}
SSHEOF
chmod 600 /home/${os_username}/.ssh/authorized_keys
chown -R ${os_username}:${os_username} /home/${os_username}/.ssh

log "OS user ${os_username} created with SSH key"
%{ else ~}
log "OS user ${os_username} created (no SSH public key supplied; root-only login)"
%{ endif ~}

log "Installing PostgreSQL 17"
apt-get update -y
apt-get install -y curl gnupg lsb-release

curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /usr/share/keyrings/postgresql.gpg
echo "deb [signed-by=/usr/share/keyrings/postgresql.gpg] https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list
apt-get update -y
apt-get install -y postgresql-17

systemctl stop postgresql || true

MOUNT_POINT="/mnt/postgresql"
PGDATA_DIR="$MOUNT_POINT/data"

if mountpoint -q "$MOUNT_POINT" 2>/dev/null || [ -d "$MOUNT_POINT" ]; then
  log "Data volume already mounted at $MOUNT_POINT"
else
  DATA_DEVICE=""
  for _ in $(seq 1 12); do
    for dev in /dev/disk/by-id/scsi-0HC_Volume_* /dev/sdb /dev/sdc /dev/xvdb; do
      [ -e "$dev" ] || continue
      resolved="$(readlink -f "$dev" 2>/dev/null || echo "$dev")"
      if [ -b "$resolved" ]; then
        DATA_DEVICE="$resolved"
        break 2
      fi
    done
    sleep 5
  done

  if [ -n "$DATA_DEVICE" ]; then
    log "Using data device $DATA_DEVICE"
    if ! blkid "$DATA_DEVICE" >/dev/null 2>&1; then
      mkfs -t ext4 "$DATA_DEVICE"
    fi
    mkdir -p "$MOUNT_POINT"
    mount "$DATA_DEVICE" "$MOUNT_POINT"
    grep -q "^$DATA_DEVICE $MOUNT_POINT" /etc/fstab || echo "$DATA_DEVICE $MOUNT_POINT ext4 defaults,nofail 0 2" >> /etc/fstab
  else
    log "No separate data device found, using default location"
    PGDATA_DIR="/var/lib/postgresql/17/main"
  fi
fi

mkdir -p "$PGDATA_DIR"
chown -R postgres:postgres "$PGDATA_DIR"
chmod 700 "$PGDATA_DIR"

mkdir -p "/etc/systemd/system/postgresql.service.d"
cat > "/etc/systemd/system/postgresql.service.d/override.conf" <<EOF
[Service]
Environment=PGDATA=$PGDATA_DIR
EOF
systemctl daemon-reload

PGPASS_FILE="/var/lib/postgresql/.pgpass"
install -o postgres -g postgres -m 0600 /dev/null "$PGPASS_FILE"
printf '%s\n' "${primary_host}:${primary_port}:replication:replicator:$(escape_pgpass_field "${db_password}")" > "$PGPASS_FILE"
chmod 600 "$PGPASS_FILE"

NEED_BASEBACKUP="true"
if [ -f "$PGDATA_DIR/PG_VERSION" ] && [ -f "$PGDATA_DIR/standby.signal" ] && \
   grep -q "^primary_conninfo = '.*host=${primary_host}.*user=replicator.*'" "$PGDATA_DIR/postgresql.auto.conf" 2>/dev/null; then
  NEED_BASEBACKUP="false"
  log "Existing standby data found, skipping base backup"
fi

if [ "$NEED_BASEBACKUP" = "true" ]; then
  if [ -n "$(ls -A "$PGDATA_DIR" 2>/dev/null)" ]; then
    log "Reseeding replica — wiping existing data"
    rm -rf "$${PGDATA_DIR:?}"
  fi

  mkdir -p "$PGDATA_DIR"
  chown -R postgres:postgres "$PGDATA_DIR"
  chmod 700 "$PGDATA_DIR"

  log "Starting base backup from ${primary_host}:${primary_port}"
  BASEBACKUP_ATTEMPTS=0
  BASEBACKUP_MAX=10
  until runuser -u postgres -- env PGPASSFILE="$PGPASS_FILE" \
      pg_basebackup -D "$PGDATA_DIR" \
      -d "host=${primary_host} port=${primary_port} user=replicator dbname=replication passfile=$${PGPASS_FILE}" \
      -v -P -w -R; do
    BASEBACKUP_ATTEMPTS=$((BASEBACKUP_ATTEMPTS + 1))
    if [ "$BASEBACKUP_ATTEMPTS" -ge "$BASEBACKUP_MAX" ]; then
      log "pg_basebackup failed after $BASEBACKUP_MAX attempts — aborting"
      exit 1
    fi
    log "pg_basebackup attempt $BASEBACKUP_ATTEMPTS failed, retrying in 30s (tunnel may not be ready)..."
    rm -rf "$${PGDATA_DIR:?}"
    mkdir -p "$PGDATA_DIR"
    chown -R postgres:postgres "$PGDATA_DIR"
    chmod 700 "$PGDATA_DIR"
    sleep 30
  done
fi

PGCONF_FILE="$PGDATA_DIR/postgresql.conf"

grep -q '^hot_standby = on$' "$PGCONF_FILE" 2>/dev/null || echo "hot_standby = on" >> "$PGCONF_FILE"

if grep -q "^data_directory" "$PGCONF_FILE" 2>/dev/null; then
  sed -i "s|^data_directory\s*=.*|data_directory = '$PGDATA_DIR'|" "$PGCONF_FILE"
fi

chown -R postgres:postgres "$PGDATA_DIR"
chmod 700 "$PGDATA_DIR"

systemctl enable postgresql
systemctl start postgresql

log "PostgreSQL replica setup complete"
