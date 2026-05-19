# Performance Observability & Tuning Runbook (Server, DB, Redis)

Step-by-step runbook for observing and tuning PaymentForm production performance.

Scope:
- Backend API on AWS ASG (`module.paymentform_backend`)
- PostgreSQL (primary/replica)
- Redis/Valkey cache + queue

Current backend baseline (from Terraform):
- Instance type: `c7g.large` (2 vCPU, 4 GiB RAM)
- ASG: `min=2`, `desired=2`, `max=8`
- App concurrency: `OCTANE_WORKERS=6`, `NUM_THREADS=16`

Source of truth:
- `iaac/environments/prod/main.tf`
  - backend ASG + instance type: around `module "paymentform_backend"`
  - caddy env vars: `OCTANE_WORKERS`, `NUM_THREADS`
- `backend/.docker/Caddyfile` (FrankenPHP worker/thread directives)
- `backend/.docker/supervisord.conf` (queue/reverb/scheduler side processes)

---

## 1) Define SLO and guardrails first

Before tuning, lock targets for your peak window:

- API p95 latency target (example: `< 300ms`)
- Error rate target (example: `< 1%`)
- Queue lag target (example: no sustained backlog growth)
- DB CPU target (example: `< 70%` sustained)
- Redis CPU target (example: `< 70%` sustained)

Do not tune blindly. Every change must map to one target.

---

## 2) Build one observation window

Pick a representative 24-hour window (include peak traffic).

Collect these together (same timeframe):

### Server / ALB
- EC2 CPUUtilization (avg + p95)
- EC2 memory usage (CloudWatch agent or host metrics)
- ALB RequestCountPerTarget
- ALB TargetResponseTime (p50/p95)
- ALB HTTP 5xx, target 5xx
- ASG InService instance count

### Application
- Octane worker restarts/crashes
- Queue depth + processing rate + failed jobs
- Reverb connection count and errors

### PostgreSQL
- CPU, free memory
- Connections used vs max
- Read/write latency
- Slow query count / top slow queries
- Lock wait / deadlock events

### Redis/Valkey
- CPU, memory used
- evictions (must stay near zero)
- command latency
- connected clients
- keyspace hit ratio

Store this as **Baseline v1**.

---

## 3) Identify bottleneck class (decision gate)

Use baseline to classify primary bottleneck:

1. **CPU-bound app**
   - EC2 CPU high, latency rises with CPU.
2. **I/O-bound app**
   - EC2 CPU low/moderate, latency high, DB/Redis/network waits dominate.
3. **DB-bound**
   - DB CPU/latency/locks high, app CPU lower.
4. **Redis-bound**
   - Redis latency/evictions/CPU high, queue/cache delays propagate.

Only tune the bottleneck you actually measured.

---

## 4) Tuning order (safe sequence)

Always tune in this order to avoid masking root cause:

1. **Queries and DB waits** (biggest win usually)
2. **Redis latency/memory policy**
3. **App concurrency (`OCTANE_WORKERS`, `NUM_THREADS`)**
4. **ASG capacity / instance size**

Reason: infra scaling hides inefficiencies and increases cost.

---

## 5) Server tuning procedure (Octane + EC2)

Change one knob at a time.

### 5.1 Edit config
In `iaac/environments/prod/main.tf` under backend `caddy_env_vars`:
- `OCTANE_WORKERS`
- `NUM_THREADS`

### 5.2 Recommended step sizes
- Workers: `+1` or `+2` per test (example `6 -> 8` max for one iteration)
- Threads: `+2` or `+4` per test (example `16 -> 20`)

### 5.3 Deploy
- Apply Terraform and let rollout stabilize.

### 5.4 Observe for 24h
Must compare to baseline on:
- p95 latency
- error rate
- memory headroom / OOM
- DB connection count + DB latency
- Redis command latency

### 5.5 Accept / rollback
- Keep only if p95 improves and no downstream pressure spike.
- Roll back immediately if DB/Redis pressure worsens or error rate climbs.

---

## 6) DB tuning procedure (PostgreSQL)

### 6.1 Observe first
- Capture top slow queries and lock waits.

### 6.2 Tune in this order
1. Add/fix indexes for top slow queries.
2. Remove N+1 query paths.
3. Trim payload columns (avoid `SELECT *`).
4. Move expensive reads to replica where safe.
5. Re-evaluate connection pool pressure.

### 6.3 Validate
- Same 24h comparison window.
- Check p95 latency + DB CPU + lock waits.

---

## 7) Redis tuning procedure

### 7.1 Observe first
- command latency, memory usage, evictions, client count, hit ratio.

### 7.2 Tune in this order
1. Fix hot keys / oversized values.
2. Add TTL where keys are unbounded.
3. Reduce unnecessary round trips (pipeline/batch where possible).
4. Revisit queue throughput and worker balance.

### 7.3 Validate
- Ensure evictions do not increase.
- Confirm queue lag and API latency improve.

---

## 8) Capacity and cost right-sizing

After app/DB/Redis tuning, decide capacity:

### Keep current if
- p95 stable and low
- error rate healthy
- DB/Redis healthy
- headroom needed for traffic spikes

### Scale down if
- sustained low CPU and low memory usage
- stable p95 and low error rate

Possible knobs:
- Reduce backend ASG desired (`desired_capacity`)
- Smaller instance type (validate ARM compatibility and memory headroom)

### Scale up if
- p95 climbs with queue growth and DB/Redis are healthy
- app saturation visible (run queue, worker saturation)

Possible knobs:
- Increase `OCTANE_WORKERS` first
- then ASG desired or instance type if needed

---

## 9) Change log template (use every iteration)

For each tuning iteration, record:

1. **Hypothesis** (what should improve and why)
2. **Single change** (exact variable diff)
3. **Time window** (start/end UTC)
4. **Result** (p95, error rate, DB/Redis impact)
5. **Decision** (keep / rollback)

Do not merge multiple knobs in one test.

---

## 10) Quick reference: where to change what

- Backend compute size + ASG:
  - `iaac/environments/prod/main.tf` → `module "paymentform_backend"`
  - `instance_type`, `min_size`, `max_size`, `desired_capacity`
- App concurrency:
  - `iaac/environments/prod/main.tf` → backend `caddy_env_vars`
  - `OCTANE_WORKERS`, `NUM_THREADS`
- Runtime wiring:
  - `iaac/providers/aws/compute-alb/userdata.sh`
  - `backend/.docker/Caddyfile`
  - `backend/.docker/supervisord.conf`

---

## 11) Current recommendation from observed state

Given reported backend CPU around ~10% (likely I/O-bound):

- Keep current `OCTANE_WORKERS=6`, `NUM_THREADS=16` initially.
- Prioritize DB and Redis latency reduction first.
- Increase workers only if queue/latency indicates app-side concurrency limits.
- If cost optimization is priority, test ASG desired reduction during off-peak with strict rollback thresholds.

---

## 12) Common issues during tuning (concise)

| Issue | Likely cause | Fast fix |
|------|---|---|
| p95 latency worse after raising workers | DB/Redis became bottleneck, not CPU | Roll back workers; optimize top slow queries and Redis hot paths first |
| DB connections spike after concurrency increase | More app workers opening connections | Reduce `OCTANE_WORKERS`; add pooling/connection limits; re-test |
| Redis command latency jumps | Too many concurrent queue/cache ops | Lower app concurrency; batch/pipeline hot paths; check key TTL/hot keys |
| Memory pressure/OOM after tuning | Too many workers/threads per instance | Reduce workers/threads or move to larger instance |
| Queue lag keeps growing | Worker count mismatch for queue load | Increase queue capacity (or separate queue nodes); verify slow jobs |
| No measurable improvement after scaling app | Root cause is I/O (DB/network/external API) | Keep app sizing; focus on query/index/external-call latency |
