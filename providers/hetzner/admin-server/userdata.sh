#!/bin/bash
set -e

log() {
  echo "[ $(date '+%Y-%m-%d %H:%M:%S') ] $1"
}

needs_quotes() {
  case "$1" in
    *[[:space:]\#\"\$\&\;]*) return 0 ;;
    *) return 1 ;;
  esac
}

log "Starting Hetzner admin server setup (Traefik + admin + valkey)"

export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y docker.io curl

# OS user is created unconditionally — later steps (`chown $${os_username}:docker /opt/app`)
# rely on it existing. SSH-key write stays gated so a missing key doesn't break the build.
log "Creating OS user: ${os_username}"
id "${os_username}" &>/dev/null || (useradd -m -s /bin/bash "${os_username}" && passwd -d "${os_username}")

for grp in docker; do
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

systemctl enable docker
systemctl start docker

log "Installing Docker Compose (legacy binary + v2 plugin)"
COMPOSE_URL="https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)"
curl -L "$COMPOSE_URL" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
mkdir -p /usr/lib/docker/cli-plugins
cp /usr/local/bin/docker-compose /usr/lib/docker/cli-plugins/docker-compose

log "Logging into GHCR"
echo "${ghcr_token}" | docker login ghcr.io -u "${ghcr_username}" --password-stdin

log "Creating app directories"
mkdir -p /opt/app/data/traefik /opt/app/data/admin /opt/app/data/valkey /opt/app/data/admin-postgres
touch /opt/app/data/traefik/acme.json
chmod 600 /opt/app/data/traefik/acme.json

# Top-level + host-managed dirs go to the OS user. Container-managed data dirs
# (postgres, valkey) must keep their in-container uid — a broad
# `chown -R` would clobber the postgres data dir and break it with
# `FATAL: could not open file "global/pg_filenode.map": Permission denied`
# on every re-run of userdata.sh.
chown ${os_username}:docker /opt/app
chown -R ${os_username}:docker /opt/app/data/traefik /opt/app/data/admin

# postgres:17-alpine runs as uid 70; valkey/valkey:8-alpine runs as uid 999.
chown -R 70:70 /opt/app/data/admin-postgres
chown -R 999:999 /opt/app/data/valkey

chmod 600 /opt/app/data/traefik/acme.json

log "Writing compose substitution env file (/opt/app/.env)"
cat > /opt/app/.env <<'COMPOSEENV'
${compose_env_content}
COMPOSEENV
chmod 600 /opt/app/.env

log "Writing admin Laravel environment file (/opt/app/admin.env)"
cat > /opt/app/admin.env <<'ADMINENVEOF'
${admin_env_content}
ADMINENVEOF
chmod 600 /opt/app/admin.env

log "Writing docker-compose.yml"
cat > /opt/app/docker-compose.yml <<'COMPOSEEOF'
${compose_file_content}
COMPOSEEOF

log "Writing deploy script"
cat > /usr/local/bin/deploy-hetzner.sh <<'DEPLOYEOF'
${deploy_script_content}
DEPLOYEOF
chmod +x /usr/local/bin/deploy-hetzner.sh

log "Executing deploy script"
/usr/local/bin/deploy-hetzner.sh

log "Installing barman client tools"
apt-get install -y barman-cli barman-cli-cloud postgresql-client

log "Waiting for local postgres container to become reachable on 127.0.0.1:5432"
for i in $(seq 1 60); do
  pg_isready -h 127.0.0.1 -p 5432 -U "${local_db_username}" && break
  sleep 2
done

log "Creating barman_replica role on local postgres"
# Pass passwords via env vars + psql -v (same staging-via-tempfile pattern
# as userdata-primary.sh admin role section — handles arbitrary special chars).
BR_PASS_TMP=$(mktemp)
chmod 600 "$BR_PASS_TMP"
cat > "$BR_PASS_TMP" <<'BR_PASS_EOF'
${backup_replication_password}
BR_PASS_EOF
BR_PASS_VAR=$(cat "$BR_PASS_TMP")
rm -f "$BR_PASS_TMP"

LOCAL_PASS_TMP=$(mktemp)
chmod 600 "$LOCAL_PASS_TMP"
cat > "$LOCAL_PASS_TMP" <<'LOCAL_PASS_EOF'
${local_db_password}
LOCAL_PASS_EOF
LOCAL_PASS_VAR=$(cat "$LOCAL_PASS_TMP")
rm -f "$LOCAL_PASS_TMP"

PGPASSWORD="$LOCAL_PASS_VAR" psql -h 127.0.0.1 -U "${local_db_username}" -d postgres -v ON_ERROR_STOP=1 -v br_pass="$BR_PASS_VAR" <<'BR_SQL'
SELECT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'barman_replica') AS r \gset
\if :r
\echo 'barman_replica exists'
\else
CREATE ROLE barman_replica WITH REPLICATION LOGIN PASSWORD :'br_pass';
\endif
BR_SQL

log "Writing barman cron"
# Cron file is rendered with placeholders for the sensitive replication
# password; we then sed-inject the real password from a shell variable so the
# password never appears in the TF-rendered userdata (which is recoverable
# from /var/lib/cloud/instance/user-data.txt and the hcloud metadata API).
cat > /etc/cron.d/admin-db-backup <<'CRON'
${backup_schedule} root AWS_REQUEST_CHECKSUM_CALCULATION=when_required AWS_RESPONSE_CHECKSUM_VALIDATION=when_required AWS_ACCESS_KEY_ID='${backup_bucket_access_key_id}' AWS_SECRET_ACCESS_KEY='${backup_bucket_access_key}' PGPASSWORD='__BR_PASS_PLACEHOLDER__' barman-cloud-backup --cloud-provider aws-s3 --endpoint-url '${backup_bucket_endpoint}' --host 127.0.0.1 --user barman_replica --gzip 's3://${backup_bucket_name}/admin-postgres' '${backup_server_name}' >> /var/log/admin-db-backup.log 2>&1
30 3 * * 0 root AWS_REQUEST_CHECKSUM_CALCULATION=when_required AWS_RESPONSE_CHECKSUM_VALIDATION=when_required AWS_ACCESS_KEY_ID='${backup_bucket_access_key_id}' AWS_SECRET_ACCESS_KEY='${backup_bucket_access_key}' PGPASSWORD='__BR_PASS_PLACEHOLDER__' barman-cloud-backup-delete --cloud-provider aws-s3 --endpoint-url '${backup_bucket_endpoint}' --retention-policy 'RECOVERY WINDOW OF 28 DAYS' 's3://${backup_bucket_name}/admin-postgres' '${backup_server_name}' >> /var/log/admin-db-backup.log 2>&1
CRON

# Substitute placeholder using `|` delimiter so a `/` in the password doesn't
# break sed. The shell variable expands at runtime; the cron-file heredoc
# above used `__BR_PASS_PLACEHOLDER__` (not a TF interpolation), so the
# replication password is never written into the rendered cron file body.
sed -i "s|__BR_PASS_PLACEHOLDER__|$BR_PASS_VAR|g" /etc/cron.d/admin-db-backup
chmod 600 /etc/cron.d/admin-db-backup
chown root:root /etc/cron.d/admin-db-backup

unset BR_PASS_VAR LOCAL_PASS_VAR
log "Weekly barman-cloud-backup configured (schedule: ${backup_schedule}, retention 28 days)"

log "Admin server setup complete"
