#!/bin/bash
set -e

log() {
  echo "[ $(date '+%Y-%m-%d %H:%M:%S') ] $1"
}

DATA_VOLUME="${data_volume_device}"
MOUNT_POINT="/mnt/postgresql"
PGDATA_DIR="$MOUNT_POINT/data"

if ! getent group postgres >/dev/null; then
    groupadd --system postgres
fi

if ! id postgres >/dev/null 2>&1; then
    useradd --system --gid postgres --home-dir /var/lib/pgsql --shell /bin/bash postgres
fi

if [ -b "$DATA_VOLUME" ]; then
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
    chown -R postgres:postgres "$MOUNT_POINT"
    chmod 700 "$PGDATA_DIR"
else
    log "Data volume $DATA_VOLUME not found, using default location"
    PGDATA_DIR="/var/lib/pgsql/data"
    mkdir -p "$PGDATA_DIR"
    chown -R postgres:postgres /var/lib/pgsql
    chmod 700 "$PGDATA_DIR"
fi
dnf update -y

mkdir -p "$PGDATA_DIR"
chown -R postgres:postgres $(dirname $PGDATA_DIR)
chmod 700 "$PGDATA_DIR"

mkdir -p "/etc/systemd/system/postgresql.service.d"
cat > "/etc/systemd/system/postgresql.service.d/override.conf" <<EOF
[Service]
Environment=PGDATA=$PGDATA_DIR
EOF
systemctl daemon-reload

PGCONF_FILE="$PGDATA_DIR/postgresql.conf"

mkdir -p /etc/pgbackrest
cat > /etc/pgbackrest/pgbackrest.conf <<EOF
[global]
repo1-type=s3
repo1-s3-bucket=${r2_bucket_name}
repo1-s3-endpoint=${r2_endpoint}
repo1-s3-key=${r2_access_key}
repo1-s3-key-secret=${r2_secret_key}
repo1-cipher-pass=${pgbackrest_cipher_pass}
repo1-retention-diff=7
repo1-retention-full=7

[db]
db-path=$PGDATA_DIR
db-port=5432
db-user=postgres
EOF

RESTORE_BACKUP_VAL="false"
if [ -z "$(ls -A $PGDATA_DIR 2>/dev/null)" ]; then
    log "Data directory is empty, checking for backups..."
    if pgbackrest info 2>/dev/null | grep -q "backup"; then
        RESTORE_BACKUP_VAL="true"
    fi
fi

if [ "$RESTORE_BACKUP_VAL" = "true" ]; then
    log "Restoring from pgbackrest backup..."
    chown -R postgres:postgres $(dirname $PGDATA_DIR)
    chmod 700 $PGDATA_DIR
    
    su - postgres -c "pgbackrest restore --type=latest --force"
    log "Backup restored successfully"
else
    log "Initializing new PostgreSQL data directory..."
    su - postgres -c "initdb -D '$PGDATA_DIR'"
    chown -R postgres:postgres $(dirname $PGDATA_DIR)
    chmod 700 $PGDATA_DIR
fi

echo "data_directory = '$PGDATA_DIR'" >> "$PGCONF_FILE"
echo "listen_addresses = '*'" >> "$PGCONF_FILE"
echo "max_wal_senders = 3" >> "$PGCONF_FILE"
echo "max_replication_slots = 3" >> "$PGCONF_FILE"
echo "wal_level = replica" >> "$PGCONF_FILE"
echo "hot_standby = on" >> "$PGCONF_FILE"

PG_HBA_FILE="$PGDATA_DIR/pg_hba.conf"
echo "host     all             all             10.0.0.0/16           trust" >> $PG_HBA_FILE
echo "host     replication     replicator      10.0.0.0/16           md5" >> $PG_HBA_FILE
${peer_vpc_cidrs_hba}

systemctl enable postgresql
systemctl start postgresql

sleep 5

if [ "$RESTORE_BACKUP_VAL" = "true" ]; then
    log "PostgreSQL restored from backup and started"
else
    su - postgres -c "psql -c \"CREATE DATABASE ${db_name};\" 2>/dev/null || true"
    su - postgres -c "psql -c \"ALTER USER postgres WITH PASSWORD '${db_password}';\""
su - postgres -c "psql -c \"CREATE USER replicator WITH REPLICATION PASSWORD '${db_password}';\" 2>/dev/null || true"
    log "PostgreSQL primary setup complete"
fi
