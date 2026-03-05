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

# Stop PostgreSQL initially
systemctl stop postgresql || true

# Configure PostgreSQL to use data volume
PGDATA_DIR="${MOUNT_POINT}/data"
PGCONF_FILE="/etc/postgresql/$${postgres_version}/main/postgresql.conf"

# Clear existing data directory
rm -rf "$${PGDATA_DIR}"
mkdir -p "$${PGDATA_DIR}"
chown -R postgres:postgres "$${PGDATA_DIR}"

# Configure as hot standby
echo "hot_standby = on" >> "$$PGCONF_FILE"

# Setup replication from primary
su - postgres -c "pg_basebackup -h $${primary_ip} -D $${PGDATA_DIR} -U replicator -v -P"

# Create recovery configuration
cat > "$${PGDATA_DIR}/postgresql.auto.conf" <<'EOF'
primary_conninfo = 'host=$${primary_ip} port=5432 user=replicator password=$${db_password}'
primary_slot_name = ''
hot_standby = on
EOF

chown -R postgres:postgres "$${PGDATA_DIR}"
chmod 700 "$${PGDATA_DIR}"

# Start PostgreSQL as replica
systemctl enable postgresql
systemctl start postgresql

echo "PostgreSQL replica setup complete with data volume"
