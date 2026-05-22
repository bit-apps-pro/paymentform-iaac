# Backend Stress Tests (k6)

Two scripts live here:

| Script | Goal | Typical target |
|---|---|---|
| `session-pollution.js` | Auth-guard / tenancy state leak between concurrent requests | staging or prod |
| `form-create-render-prod.js` | Form create + renderer fetch under load, with cross-tenant leak detector | prod |

For a full end-to-end browser flow (signup → mailpit verify → tenant
provisioning → Stripe OAuth → render), see
`iaac/loadtest/playwright/dev-full-flow.spec.ts` — that one drives the dev
docker-compose stack via real browsers.

## Session-pollution test

Verifies Laravel Octane / FrankenPHP worker-mode request isolation under load.
Drives many concurrent virtual users, each pinned to a distinct
`(user_id, tenant_id, token)` triple, and asserts on every response that the
server-resolved identity still matches the caller. Any drift = pollution.

## What it catches

| Symptom on the wire | What's broken |
|---|---|
| `GET /me` returns user B for VU using user A's token | Auth-guard singleton leak |
| `GET /{tenant}/me` returns wrong `tenant_id` | Tenancy context not reset between requests |
| `GET /{tenant}/forms` returns a form tagged by another user | DB connection / tenant scope leak |
| `WITH_WRITES=1` and a write lands in another tenant's DB | Write-path tenancy leak |

## Files

- `session-pollution.js` — the k6 script. No external deps beyond k6 itself.
- `fixtures.example.json` — shape of the fixtures file each VU draws from.
- `seed-fixtures.tinker.php` — optional helper to seed N users / M tenants
  and emit a populated `fixtures.json` (adapt to your `User`/`Tenant` model).

## Quick start (staging)

```sh
# 1. Install k6 (one-time): https://grafana.com/docs/k6/latest/set-up/install-k6/
brew install k6                          # macOS
# or
sudo gpg -k && sudo gpg --no-default-keyring \
  --keyring /usr/share/keyrings/k6-archive-keyring.gpg \
  --keyserver hkp://keyserver.ubuntu.com:80 \
  --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69
echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" \
  | sudo tee /etc/apt/sources.list.d/k6.list
sudo apt-get update && sudo apt-get install k6   # Debian/Ubuntu

# 2. Seed fixtures (one-time per environment; reruns rotate tokens)
SEED_COUNT=20 SEED_TENANTS=5 \
  API_BASE=https://api.dev.paymentform.io \
  TENANT_API_TEMPLATE='https://%s.api.dev.paymentform.io' \
  php artisan tinker --execute="$(cat iaac/loadtest/k6/seed-fixtures.tinker.php)"

# 3. Run the soak — reads
k6 run iaac/loadtest/k6/session-pollution.js \
  --env FIXTURES_FILE=iaac/loadtest/k6/fixtures.json \
  --env VUS=100 --env DURATION=5m

# Same thing with read+write mix
k6 run iaac/loadtest/k6/session-pollution.js \
  --env FIXTURES_FILE=iaac/loadtest/k6/fixtures.json \
  --env VUS=100 --env DURATION=5m \
  --env WITH_WRITES=1

# Retarget the same fixtures at a different environment from the CLI.
# API_BASE_URL overrides each fixture's api_base_url.
# TENANT_BASE_URL_TEMPLATE overrides tenant_base_url; %s is substituted per
# fixture's tenant_id at runtime, so you can use one fixture file across envs.
k6 run iaac/loadtest/k6/session-pollution.js \
  --env FIXTURES_FILE=iaac/loadtest/k6/fixtures.json \
  --env API_BASE_URL=https://api.dev.paymentform.io \
  --env TENANT_BASE_URL_TEMPLATE='https://%s.api.dev.paymentform.io' \
  --env VUS=100 --env DURATION=5m
```

A `summary.json` lands in the working dir, plus a one-screen verdict to stdout.
Exit code is non-zero if `pollution_events > 0` or `http_req_failed >= 5%`.

## Diagnostic A/B with `OCTANE_ENABLED`

The whole point: confirm whether Octane worker-mode is the source of suspected
state leaks.

```sh
# A) Worker mode (current)
OCTANE_ENABLED=true  # in the backend container's env, then redeploy
k6 run iaac/loadtest/k6/session-pollution.js ... > worker-mode.txt

# B) Classic mode (FrankenPHP without worker — see backend/.docker/start.sh)
OCTANE_ENABLED=false
k6 run iaac/loadtest/k6/session-pollution.js ... > classic-mode.txt

diff <(jq .metrics.pollution_events.values.count worker-mode.json) \
     <(jq .metrics.pollution_events.values.count classic-mode.json)
```

If pollution drops to 0 in classic mode but is non-zero in worker mode, the
bug is in worker-boundary state cleanup — see the audit notes under
`docs/specs/octane-session-pollution.md` (if present) for the prime suspects:
tenancy-end listener, `LibSQLConnection` singleton, Sanctum guard config.

If both modes show pollution, the bug is below the worker layer — cookie
domain misconfig, session driver, or Sanctum guard caching.

## Tuning

- `VUS` should comfortably exceed `OCTANE_WORKERS × NUM_THREADS` so every
  worker hosts multiple identities sequentially — that's the condition
  state-pollution needs to surface. Prod runs 6 × 16 = 96 slots, so start
  at `VUS=150`.
- `DURATION` of 2–5 min is usually enough; rare bugs may need 15 min+.
- For CI gating, set `--env DURATION=60s` and rely on the thresholds (k6
  exits non-zero on any threshold breach).

## What this does NOT catch

- Pollution where the *same* user sees stale data of their own past
  requests (e.g., a per-user cache that doesn't invalidate). Identity-echo
  looks correct.
- Pollution that only manifests across background jobs or websocket
  channels — those aren't exercised here.
- Pollution in code paths that are not reached by the four endpoints above.
  Extend the VU function if your bug suspects live elsewhere.

---

## Form create + render hammer (production)

`form-create-render-prod.js` exercises the tenant form write path + renderer
read path at production scale. Each VU loops:

1. `POST /{tenant_id}/form/create` — uniquely tagged with the VU id
2. `GET <render_base>/f/{form_uuid}` — pulls the page via the renderer service
3. `DELETE /{tenant_id}/form/delete/{id}` — cleanup, best-effort

No submission, no payment. The point is to load the write path and surface
cross-tenant rendering leaks (a VU rendering a form tagged by a different VU
is a fail).

### Fixtures

Seed authenticated tokens + tenant ids into `form-fixtures.json` (see
`form-fixtures.example.json`). One way: extend
`seed-fixtures.tinker.php` to also emit `tenant_render_base_url` for each
fixture, then copy / rename.

### Run

```sh
k6 run iaac/loadtest/k6/form-create-render-prod.js \
  --env FIXTURES_FILE=iaac/loadtest/k6/form-fixtures.json \
  --env VUS=100 --env DURATION=5m

# Retarget the same fixtures at a different env with overrides.
k6 run iaac/loadtest/k6/form-create-render-prod.js \
  --env FIXTURES_FILE=iaac/loadtest/k6/form-fixtures.json \
  --env API_BASE_URL=https://api.paymentform.io \
  --env TENANT_RENDER_TEMPLATE='https://%s.paymentform.io' \
  --env VUS=200 --env DURATION=10m
```

Outputs `create-render-summary.json` + a stdout verdict line. Thresholds:

- `form_create_success > 0.995`
- `form_render_success > 0.995`
- `cross_tenant_leaks == 0`
- `http_req_failed < 0.005`
- `p(95)` for both create and render < 2000ms

Any breach makes k6 exit non-zero.
