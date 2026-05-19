#!/usr/bin/env bash
# Roll out Postgres tuning + pgbouncer to existing AWS US prod DB.
#
# Usage:
#   ./db-rollout.sh status                  # show nodes + replication lag
#   ./db-rollout.sh apply-primary           # in-place SSM re-apply on primary (idempotent)
#   ./db-rollout.sh restart-primary         # restart postgres on primary (for restart-required settings)
#   ./db-rollout.sh promote-replica         # promote replica (replica-first failover step 1)
#   ./db-rollout.sh demote-old-primary      # stop pg on old primary (failover step 2)
#   ./db-rollout.sh verify-pgbouncer        # confirm pgbouncer is serving on :6432
#
# In-place update (simpler, ~5s brief restart):
#   ./db-rollout.sh status
#   tofu -chdir=environments/prod apply           # creates/replaces replica only
#   ./db-rollout.sh apply-primary
#   ./db-rollout.sh restart-primary               # ~5s pg restart for shared_buffers et al
#   ./db-rollout.sh verify-pgbouncer
#
# Replica-first failover (zero downtime):
#   ./db-rollout.sh status
#   tofu -chdir=environments/prod apply           # replica comes up tuned
#   ./db-rollout.sh promote-replica               # replica is now primary
#   # update primary_endpoint references in env / DNS to point at promoted node
#   ./db-rollout.sh demote-old-primary
#   tofu -chdir=environments/prod taint module.postgres_database.aws_instance.postgresql_primary
#   tofu -chdir=environments/prod apply           # old primary recreated as new replica

set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
PRIMARY_NAME="${PRIMARY_NAME:-paymentform-prod-database-postgresql-primary}"
REPLICA_NAME="${REPLICA_NAME:-paymentform-prod-database-postgresql-replica}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USERDATA_PRIMARY="$SCRIPT_DIR/../providers/aws/database/userdata-primary.sh"

require_aws_cli() {
  command -v aws >/dev/null || { echo "aws CLI required"; exit 1; }
  aws sts get-caller-identity --region "$REGION" >/dev/null \
    || { echo "AWS credentials not configured for region $REGION"; exit 1; }
}

resolve_id() {
  local name="$1" id
  id=$(aws ec2 describe-instances --region "$REGION" \
    --filters "Name=tag:Name,Values=$name" "Name=instance-state-name,Values=running" \
    --query 'Reservations[].Instances[].InstanceId' --output text)
  [ -n "$id" ] && [ "$id" != "None" ] || { echo "instance not found: $name" >&2; return 1; }
  echo "$id"
}

ssm_run() {
  local iid="$1" cmd="$2" cid out
  cid=$(aws ssm send-command --region "$REGION" --instance-ids "$iid" \
    --document-name AWS-RunShellScript \
    --parameters "commands=[\"$cmd\"]" \
    --query 'Command.CommandId' --output text)
  aws ssm wait command-executed --command-id "$cid" --instance-id "$iid" --region "$REGION" || true
  out=$(aws ssm get-command-invocation --command-id "$cid" --instance-id "$iid" --region "$REGION" \
    --query 'StandardOutputContent' --output text)
  echo "$out"
}

ssm_run_script() {
  local iid="$1" script_path="$2" cid
  local b64; b64=$(base64 -w0 "$script_path")
  cid=$(aws ssm send-command --region "$REGION" --instance-ids "$iid" \
    --document-name AWS-RunShellScript \
    --parameters "commands=[\"echo $b64 | base64 -d > /tmp/userdata-rerun.sh\",\"chmod +x /tmp/userdata-rerun.sh\",\"bash /tmp/userdata-rerun.sh 2>&1 | tail -80\"]" \
    --query 'Command.CommandId' --output text)
  aws ssm wait command-executed --command-id "$cid" --instance-id "$iid" --region "$REGION" || true
  aws ssm get-command-invocation --command-id "$cid" --instance-id "$iid" --region "$REGION" \
    --query 'StandardOutputContent' --output text
}

cmd_status() {
  require_aws_cli
  local pid rid pip rip
  pid=$(resolve_id "$PRIMARY_NAME")
  pip=$(aws ec2 describe-instances --region "$REGION" --instance-ids "$pid" \
    --query 'Reservations[].Instances[].PrivateIpAddress' --output text)
  echo "Primary: $pid ($pip)"

  if rid=$(resolve_id "$REPLICA_NAME" 2>/dev/null); then
    rip=$(aws ec2 describe-instances --region "$REGION" --instance-ids "$rid" \
      --query 'Reservations[].Instances[].PrivateIpAddress' --output text)
    echo "Replica: $rid ($rip)"
  else
    echo "Replica: (not running)"
  fi

  echo
  echo "=== pg_stat_replication (on primary) ==="
  ssm_run "$pid" "sudo -u postgres psql -x -c 'SELECT application_name, client_addr, state, sync_state, write_lag, flush_lag, replay_lag FROM pg_stat_replication;'"
}

cmd_apply_primary() {
  require_aws_cli
  [ -f "$USERDATA_PRIMARY" ] || { echo "userdata not found: $USERDATA_PRIMARY"; exit 1; }
  local pid; pid=$(resolve_id "$PRIMARY_NAME")
  echo "Re-applying userdata-primary.sh on $pid (idempotent — sentinel-guarded)..."
  ssm_run_script "$pid" "$USERDATA_PRIMARY"
  echo
  echo "Done. Run: ./db-rollout.sh restart-primary  (to activate restart-required settings)"
}

cmd_restart_primary() {
  require_aws_cli
  local pid; pid=$(resolve_id "$PRIMARY_NAME")
  echo "Restarting postgres on primary $pid..."
  ssm_run "$pid" "sudo systemctl restart postgresql && sleep 3 && sudo -u postgres psql -tAc 'SHOW shared_buffers' && sudo -u postgres psql -tAc 'SHOW max_connections'"
}

cmd_promote_replica() {
  require_aws_cli
  local rid; rid=$(resolve_id "$REPLICA_NAME")
  local rip; rip=$(aws ec2 describe-instances --region "$REGION" --instance-ids "$rid" \
    --query 'Reservations[].Instances[].PrivateIpAddress' --output text)
  echo "Promoting replica $rid ($rip)..."
  ssm_run "$rid" "sudo -u postgres psql -tAc 'SELECT pg_promote(true, 60);'"
  echo
  echo "Promoted. New primary IP: $rip"
  echo "Update Terraform DB_HOST / DNS / Cloudflare tunnel to point here, then:"
  echo "  ./db-rollout.sh demote-old-primary"
}

cmd_demote_old_primary() {
  require_aws_cli
  local pid; pid=$(resolve_id "$PRIMARY_NAME")
  echo "Stopping postgres on old primary $pid..."
  ssm_run "$pid" "sudo systemctl stop postgresql && sudo systemctl disable postgresql"
  echo
  echo "Old primary stopped. Now in Terraform:"
  echo "  tofu -chdir=environments/prod taint module.postgres_database.aws_instance.postgresql_primary"
  echo "  tofu -chdir=environments/prod apply   # recreates as new replica"
}

cmd_verify_pgbouncer() {
  require_aws_cli
  local pid; pid=$(resolve_id "$PRIMARY_NAME")
  echo "Checking pgbouncer on primary $pid..."
  ssm_run "$pid" "sudo systemctl is-active pgbouncer && sudo ss -tlnp | grep :6432 && sudo -u postgres psql -h 127.0.0.1 -p 6432 -U postgres -c 'SHOW POOLS;' pgbouncer 2>&1 | head -20"
}

case "${1:-}" in
  status)              cmd_status ;;
  apply-primary)       cmd_apply_primary ;;
  restart-primary)     cmd_restart_primary ;;
  promote-replica)     cmd_promote_replica ;;
  demote-old-primary)  cmd_demote_old_primary ;;
  verify-pgbouncer)    cmd_verify_pgbouncer ;;
  *)                   sed -n '2,28p' "$0"; exit 1 ;;
esac
