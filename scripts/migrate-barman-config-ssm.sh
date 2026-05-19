#!/usr/bin/env bash
#
# migrate-barman-config-ssm.sh
#
# Dispatches iaac/scripts/migrate-barman-config.sh to the running PostgreSQL
# primary via AWS SSM Run Command. Reads all required env vars from
# iaac/environments/<env>/terraform.tfvars so secrets stay out of this file.
#
# Requirements (on YOUR workstation, not the EC2):
#   - aws CLI v2, authenticated to the AWS account that owns the EC2
#   - jq
#   - The primary EC2 must have the SSM agent running + the
#     AmazonSSMManagedInstanceCore policy on its instance profile
#
# Usage:
#   ./migrate-barman-config-ssm.sh                          # defaults to env=prod
#   ENVIRONMENT=staging ./migrate-barman-config-ssm.sh

set -euo pipefail

ENVIRONMENT="${ENVIRONMENT:-prod}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IAAC_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TFVARS="${IAAC_ROOT}/environments/${ENVIRONMENT}/terraform.tfvars"
MIGRATION_SCRIPT="${SCRIPT_DIR}/migrate-barman-config.sh"

[[ -f "$TFVARS" ]] || { echo "tfvars not found: $TFVARS"; exit 1; }
[[ -f "$MIGRATION_SCRIPT" ]] || { echo "migration script not found: $MIGRATION_SCRIPT"; exit 1; }

# ---- Parse tfvars (simple key = "value" lines) ----
tfvar() {
    local key="$1"
    grep -E "^${key}\s*=" "$TFVARS" | head -1 | sed -E 's/^[^=]+=\s*"?([^"]*)"?\s*$/\1/'
}

BUCKET_NAME="$(tfvar backup_storage_bucket_name)"
ACCESS_KEY_ID="$(tfvar backup_storage_access_key_id)"
SECRET_KEY="$(tfvar backup_storage_access_key)"
CF_ACCOUNT_ID="$(tfvar cloudflare_account_id)"

[[ -n "$BUCKET_NAME"   ]] || { echo "missing backup_storage_bucket_name in tfvars";   exit 1; }
[[ -n "$ACCESS_KEY_ID" ]] || { echo "missing backup_storage_access_key_id in tfvars"; exit 1; }
[[ -n "$SECRET_KEY"    ]] || { echo "missing backup_storage_access_key in tfvars";    exit 1; }
[[ -n "$CF_ACCOUNT_ID" ]] || { echo "missing cloudflare_account_id in tfvars";        exit 1; }

R2_ENDPOINT="https://${CF_ACCOUNT_ID}.r2.cloudflarestorage.com"
AWS_REGION="${AWS_REGION:-us-east-1}"
PRIMARY_TAG_NAME="${PRIMARY_TAG_NAME:-paymentform-${ENVIRONMENT}-database-postgresql-primary}"

# ---- Resolve primary instance ID by Name tag ----
echo "Resolving instance ID for tag Name=${PRIMARY_TAG_NAME} in ${AWS_REGION}..."
INSTANCE_ID="$(aws ec2 describe-instances \
    --region "$AWS_REGION" \
    --filters "Name=tag:Name,Values=${PRIMARY_TAG_NAME}" \
              "Name=instance-state-name,Values=running" \
    --query 'Reservations[].Instances[].InstanceId' \
    --output text)"

[[ -n "$INSTANCE_ID" ]] || { echo "No running instance with Name=${PRIMARY_TAG_NAME}"; exit 1; }
[[ "$(echo "$INSTANCE_ID" | wc -w)" -eq 1 ]] || { echo "Expected 1 instance, got: $INSTANCE_ID"; exit 1; }
echo "Primary instance: $INSTANCE_ID"

# ---- Build SSM payload: export env vars + inline the migration script ----
# Heredoc-encoded so the script body can contain any quoting safely.
SCRIPT_BODY_B64="$(base64 -w0 "$MIGRATION_SCRIPT")"

SSM_COMMANDS=$(jq -n \
    --arg bucket    "$BUCKET_NAME" \
    --arg endpoint  "$R2_ENDPOINT" \
    --arg akid      "$ACCESS_KEY_ID" \
    --arg sk        "$SECRET_KEY" \
    --arg env       "$ENVIRONMENT" \
    --arg body64    "$SCRIPT_BODY_B64" \
    '[
        "export ENVIRONMENT=" + ($env|@sh),
        "export BUCKET_NAME=" + ($bucket|@sh),
        "export R2_ENDPOINT=" + ($endpoint|@sh),
        "export AWS_ACCESS_KEY_ID=" + ($akid|@sh),
        "export AWS_SECRET_ACCESS_KEY=" + ($sk|@sh),
        "export MIGRATE_BARMAN_NONINTERACTIVE=1",
        "TMP=$(mktemp /tmp/migrate-barman-XXXXXX.sh)",
        "trap \"shred -u $TMP 2>/dev/null || rm -f $TMP\" EXIT",
        "echo " + ($body64|@sh) + " | base64 -d > $TMP",
        "chmod 700 $TMP",
        "bash $TMP"
    ]')

# ---- Confirm before firing ----
cat <<EOF

About to send SSM command to:
  instance:   ${INSTANCE_ID}
  region:     ${AWS_REGION}
  env:        ${ENVIRONMENT}
  bucket:     ${BUCKET_NAME}
  endpoint:   ${R2_ENDPOINT}

This runs the migration NON-INTERACTIVELY (no confirmation prompts on the box).
The script will:
  1. Reload Postgres with archive_command=--gzip + archive_timeout=12h
  2. Rewrite /etc/cron.d/barman-backup (gzip + 7-day retention)
  3. Take a fresh gzipped base backup
  4. Run barman-cloud-backup-delete --retention-policy 'REDUNDANCY 1'
     (deletes EVERY older base backup + every WAL not needed by the anchor)

EOF
read -r -p "Type YES to dispatch: " confirm
[[ "$confirm" == "YES" ]] || { echo "Aborted."; exit 1; }

# ---- Send command ----
CMD_ID="$(aws ssm send-command \
    --region "$AWS_REGION" \
    --instance-ids "$INSTANCE_ID" \
    --document-name "AWS-RunShellScript" \
    --comment "barman migrate: gzip + 12h archive_timeout + 7d retention + REDUNDANCY 1 purge" \
    --timeout-seconds 1800 \
    --cloud-watch-output-config "CloudWatchOutputEnabled=true,CloudWatchLogGroupName=/aws/ssm/barman-migrate" \
    --parameters "commands=$(echo "$SSM_COMMANDS" | jq -c .),executionTimeout=1800" \
    --query 'Command.CommandId' \
    --output text)"

echo
echo "Command ID: $CMD_ID"
echo "Tailing output..."
echo

# ---- Poll until terminal ----
while :; do
    STATUS="$(aws ssm get-command-invocation \
        --region "$AWS_REGION" \
        --command-id "$CMD_ID" \
        --instance-id "$INSTANCE_ID" \
        --query 'Status' --output text 2>/dev/null || echo "Pending")"
    case "$STATUS" in
        Pending|InProgress|Delayed) sleep 5 ;;
        Success|Failed|Cancelled|TimedOut) break ;;
        *) sleep 5 ;;
    esac
done

aws ssm get-command-invocation \
    --region "$AWS_REGION" \
    --command-id "$CMD_ID" \
    --instance-id "$INSTANCE_ID" \
    --output json | jq -r '
        "=== STATUS: " + .Status,
        "=== STDOUT ===",
        .StandardOutputContent,
        "=== STDERR ===",
        .StandardErrorContent
    '

[[ "$STATUS" == "Success" ]] || exit 1
