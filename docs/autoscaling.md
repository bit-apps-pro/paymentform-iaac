# Autoscaling

Operational guide for the backend and renderer AWS Auto Scaling Groups (ASGs). Stateless tiers only — DB and admin are single-instance and do **not** autoscale.

> Module sources: `providers/aws/compute-alb` (backend), `providers/aws/compute-nlb` (renderer). Cloudwatch alarms live in those modules.

## Inventory

| ASG | Module | Min | Max | Health-check target |
|---|---|---|---|---|
| `paymentform-prod-backend-compute-asg` | `aws/compute-alb` | 1 | 6 | ALB target group `/health` |
| `paymentform-prod-renderer-compute-asg` | `aws/compute-nlb` | 1 | 4 | NLB TCP 443 |

Inspect at runtime:

```bash
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names paymentform-prod-backend-compute-asg paymentform-prod-renderer-compute-asg \
  --query 'AutoScalingGroups[].{name:AutoScalingGroupName,min:MinSize,max:MaxSize,desired:DesiredCapacity,inst:Instances[].InstanceId}'
```

## Scaling triggers

Backend uses CPU + ALB-request-count target tracking. Renderer uses CPU + network alarms.

Inspect alarms:

```bash
aws cloudwatch describe-alarms \
  --alarm-name-prefix paymentform-prod-backend \
  --query 'MetricAlarms[].{name:AlarmName,state:StateValue,threshold:Threshold,metric:MetricName}'
```

Common alarms (backend):

| Alarm | Triggers | Action |
|---|---|---|
| `paymentform-prod-backend-compute-requests-high` | ALB request count per target > N | Scale **up** |
| `paymentform-prod-backend-compute-requests-low` | ALB request count per target < M | Scale **down** |

Renderer:

| Alarm | Triggers | Action |
|---|---|---|
| `paymentform-prod-renderer-compute-mem-high` | Mem util > 75% | Scale **up** |
| `paymentform-prod-renderer-compute-mem-low` | Mem util < 30% | Scale **down** |

## Step 1: Verify autoscaling is healthy

```bash
# 1. Are processes suspended? Should be empty in normal state.
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names paymentform-prod-backend-compute-asg \
  --query 'AutoScalingGroups[0].SuspendedProcesses'

# 2. Recent scaling activity (last 24h).
aws autoscaling describe-scaling-activities \
  --auto-scaling-group-name paymentform-prod-backend-compute-asg \
  --max-items 10 \
  --query 'Activities[].{start:StartTime,status:StatusCode,cause:Cause}'

# 3. Lifecycle hook status — ASG sometimes stalls on these.
aws autoscaling describe-lifecycle-hooks \
  --auto-scaling-group-name paymentform-prod-backend-compute-asg
```

## Step 2: Manual scale (when you trust your judgement more than the alarms)

Temporarily set desired capacity. ASG will keep this until an alarm forces it elsewhere.

```bash
# Scale backend to 4 instances now.
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name paymentform-prod-backend-compute-asg \
  --desired-capacity 4 \
  --honor-cooldown
```

To pin the value (e.g., during a known traffic event), raise `MinSize` so alarms can't scale you down:

```bash
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name paymentform-prod-backend-compute-asg \
  --min-size 4 --desired-capacity 4
```

Don't leave `MinSize` raised permanently — change it back in tofu so future applies match reality.

## Step 3: Tune from tofu (durable changes)

For permanent changes, edit `providers/aws/compute-alb/variables.tf` or the call-site in `environments/prod/main.tf`:

```hcl
module "paymentform_backend" {
  source = "../../providers/aws/compute-alb"
  ...
  min_size                  = 2     # was 1
  max_size                  = 8     # was 6
  desired_capacity          = 2
  scale_up_cooldown         = 60
  scale_down_cooldown       = 300
}
```

Apply:

```bash
make plan
make apply
```

Pre-warm before applying if you expect the new desired capacity to be larger than current — alarms will catch up but you may briefly see saturation.

## Step 4: Roll the ASG (replace instances)

When userdata changes (new AMI, new env, new SSM doc):

```bash
# Easiest: bump the launch template version (tofu does this on apply).
make plan
make apply

# Then trigger an instance refresh (rolling replacement).
aws autoscaling start-instance-refresh \
  --auto-scaling-group-name paymentform-prod-backend-compute-asg \
  --strategy Rolling \
  --preferences '{"MinHealthyPercentage":50,"InstanceWarmup":120}'
```

Watch progress:

```bash
aws autoscaling describe-instance-refreshes \
  --auto-scaling-group-name paymentform-prod-backend-compute-asg
```

Abort if it's misbehaving:

```bash
aws autoscaling cancel-instance-refresh \
  --auto-scaling-group-name paymentform-prod-backend-compute-asg
```

## Step 5: Userdata sync (no instance replacement)

Sometimes you change the userdata script but want to re-run it on **existing** instances (e.g. update env, swap image tag) without rolling.

```bash
make userdata-sync PROVIDER=aws
# uses scripts/render-userdata.sh + SSM SendCommand under the hood
```

Verify on each instance:

```bash
aws ssm send-command \
  --instance-ids i-XXX \
  --document-name AWS-RunShellScript \
  --parameters 'commands=["docker ps --format \"{{.Image}}\""]'
```

## Common issues

| Symptom | Likely cause | Fix |
|---|---|---|
| ASG desired count won't change | `SuspendedProcesses` contains `Launch` or `Terminate` | `aws autoscaling resume-processes --auto-scaling-group-name ... --scaling-processes Launch Terminate` |
| Scaling activity shows `Failed`, "no spot capacity" | Mixed-instance policy can't find spot | Inspect launch template `InstanceMarketOptions`; either widen instance types or remove spot bias |
| Instances launch but ALB never marks them healthy | Health-check path wrong, or app boots > grace period | Confirm `health_check_path` in module input. Increase `health_check_grace_period`. Tail boot: `aws ssm session ... → less /var/log/cloud-init-output.log` |
| Alarms in `INSUFFICIENT_DATA` | Metric not flowing (CW agent dead, no traffic) | Check `paymentform-prod-backend-cwagent` status on the instance. For request-count alarms, low traffic = expected — set `EvaluateLowSampleCountPercentile` |
| ASG flaps up/down every 5 min | Scale-up and scale-down thresholds too close | Widen the gap, or increase cooldowns |
| `cancel-instance-refresh` ignored, instance still terminating | Refresh already past `Pending` state | Wait it out; you can't abort an instance once it's in `Terminating` |
| New instances inherit old image | userdata pulls `:latest`, GHCR returned cached layer | Pin to immutable tag (`@sha256:`) in `BACKEND_IMAGE`. Re-run `make update-backend`. |
| Backend `503` during scale-up | New instances pass health-check before warm-up is done (composer cache, opcache) | Add a warm-up endpoint to `/health` that fails until app is ready; bump `InstanceWarmup` in instance-refresh preferences |

## Pre-event checklist

Before a known traffic event (campaign launch, demo, partner integration go-live):

1. `make state-list | grep asg` — verify expected ASGs in state.
2. `aws autoscaling describe-scaling-activities` — confirm no failures in last 24h.
3. Raise `MinSize` to your floor for the event window.
4. Pre-warm by setting `DesiredCapacity` 30–60 min before event.
5. Disable scale-**down** alarms during the event:
   ```bash
   aws cloudwatch disable-alarm-actions --alarm-names paymentform-prod-backend-compute-requests-low
   ```
   Re-enable after.
6. Tail `journalctl -u paymentform-backend -f` on one node to catch the first 5xx.

## Hetzner servers (non-AWS) — manual only

`providers/hetzner/server` and `providers/hetzner/database` provision **single** instances. They do not autoscale. To add capacity:

1. Add a new module call in `environments/prod/main.tf` (e.g. `hetzner_backend_hel1_b`).
2. Apply.
3. Update upstream load balancer / DNS to include the new IP.

No alarms exist for Hetzner today — operate by manual inspection or `hcloud server list`.
