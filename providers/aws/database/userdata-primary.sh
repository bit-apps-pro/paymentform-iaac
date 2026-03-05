#!/bin/bash
set -e

export DEBIAN_FRONTEND=noninteractive

# Format and mount data volume
DATA_VOLUME="${data_volume_device}"
MOUNT_POINT="/mnt/postgresql"

# Check if volume exists
if [ -b "${DATA_VOLUME}" ]; then
    # Format the volume
    mkfs -t ext4 ${DATA_VOLUME}
    
    # Create mount point
    mkdir -p ${MOUNT_POINT}
    
    # Mount the volume
    mount ${DATA_VOLUME} ${MOUNT_POINT}
    
    # Add to fstab for persistence
    echo "${DATA_VOLUME} ${MOUNT_POINT} ext4 defaults,nofail 0 2" >> /etc/fstab
    
    # Create postgres directory on data volume
    mkdir -p ${MOUNT_POINT}/data
    chown -R postgres:postgres ${MOUNT_POINT}
    chmod 700 ${MOUNT_POINT}/data
fi

# Install PostgreSQL
echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
apt-get update
apt-get install -y postgresql-$${postgres_version} postgresql-contrib-$${postgres_version} pgbackrest

# Configure PostgreSQL to use data volume
PGDATA_DIR="${MOUNT_POINT}/data"
PGCONF_FILE="/etc/postgresql/$${postgres_version}/main/postgresql.conf"

# Stop default PostgreSQL if running
systemctl stop postgresql || true

# Initialize data directory on volume if not exists
if [ ! -d "${PGDATA_DIR}" ]; then
    chown -R postgres:postgres ${MOUNT_POINT}
    chmod 700 ${MOUNT_POINT}/data
fi

# Update postgresql.conf for replication and pgbackrest
echo "data_directory = '$${PGDATA_DIR}'" >> "$$PGCONF_FILE"
echo "listen_addresses = '*'" >> "$$PGCONF_FILE"
echo "max_wal_senders = 3" >> "$$PGCONF_FILE"
echo "max_replication_slots = 3" >> "$$PGCONF_FILE"
echo "wal_level = replica" >> "$$PGCONF_FILE"
echo "hot_standby = on" >> "$$PGCONF_FILE"

# Configure pg_hba.conf for replication
echo "host     all             all             10.0.0.0/16           trust" >> /etc/postgresql/$${postgres_version}/main/pg_hba.conf
echo "host     replication     replicator      10.0.0.0/16           md5" >> /etc/postgresql/$${postgres_version}/main/pg_hba.conf

# Configure pgbackrest
mkdir -p /etc/pgbackrest
cat > /etc/pgbackrest/pgbackrest.conf <<'EOF'
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
db-path=${PGDATA_DIR}
db-port=5432
db-user=postgres
EOF

# Start PostgreSQL
systemctl enable postgresql
systemctl start postgresql

# Create database if not exists
su - postgres -c "psql -c \"CREATE DATABASE $${db_name};\" 2>/dev/null || true"

# Configure primary for replication
su - postgres -c "psql -c \"ALTER USER postgres WITH PASSWORD '${db_password}';\""

sleep 10

echo "PostgreSQL primary setup complete with data volume"
