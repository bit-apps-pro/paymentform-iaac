# Dev Full-Flow Stress Test (Playwright)

Drives N parallel real-browser sessions through the complete signup
→ email-verify → tenant-provisioning → login → form-create → Stripe Connect
OAuth → render → submit chain against the dev docker-compose stack. Catches
failures that only surface under concurrent load: rate-limit breaches,
provisioning races, session pollution across guards, Stripe OAuth flakiness.

For a *pure* form create+render hammer against production (no signup, no
OAuth, no submit), see `iaac/loadtest/k6/form-create-render-prod.js`.

## Prerequisites

- Local dev stack up: `docker compose -f docker-compose.yml -f docker-compose.dev-local.yml up`
- `TRAEFIK_HOST` resolves on the runner (`/etc/hosts` or DNS) for at least
  `app.<host>`, `api.<host>`, `mailpit.<host>`, plus any tenant subdomain
  created during the run (`<slug>.<host>`).
- A Stripe **test-mode** account, ideally one dedicated to load testing.
  The OAuth flow needs the email + password.
- Node 20+.

## Setup

```sh
cd iaac/loadtest/playwright
cp .env.example .env       # fill TRAEFIK_HOST, port, Stripe creds
npm install
npm run install:browsers
```

## Run

```sh
# Single worker, headed (good for the first run and for debugging Stripe OAuth).
WORKERS=1 npm run test:headed

# Stress run — 10 parallel browser contexts, one full chain each.
WORKERS=10 ITERATIONS=1 npm test

# Heavier soak — 20 workers × 3 chains each = 60 full signup chains.
WORKERS=20 ITERATIONS=3 npm test
```

Reports land in `playwright-report/`. On failure, traces + screenshots + video
are captured automatically (`use.trace = 'retain-on-failure'`).

## Tuning

- `WORKERS` — parallel browser contexts. Each context holds one Chromium tab
  + one APIRequestContext. CPU-bound; treat as a per-runner ceiling.
- `ITERATIONS` — chains per worker. Use for soak runs that need to surface
  state that only leaks after many sequential users on the same worker.
- `MAILPIT_TIMEOUT_MS` / `WORKSPACE_TIMEOUT_MS` — bump if your machine is
  slow to provision tenants (cold DB, no caches).
- `REGISTRATION_PASSWORD` — pin the password globally; otherwise the
  generated default `Loadtest-Pa55!` is used.

## What this catches

| Symptom | Likely cause |
|---|---|
| Verification code not in mailpit within timeout | Queue worker stopped, mail driver misconfigured |
| `/workspace/status` never reaches `ready` | Tenant provisioning queue stuck |
| Form-create returns 401 in iteration #N (#0 passed) | Sanctum/session pollution between iterations |
| Form-render returns wrong tenant's form | Tenancy context leak (renderer pulled stale data) |
| Stripe OAuth lands on the wrong tenant URL | `FRONTEND_URL` / `STRIPE_REDIRECT_URI` misconfig |
| Multiple workers see "this email is taken" | Email-uniqueness collision (timestamp granularity too low) |

## What this does NOT do

- Stripe in non-test mode. The OAuth flow targets Stripe test-mode only;
  point it at a non-test account and it will create real Connect accounts.
- Submission with a real charge. The current spec stops at render. Add a
  submit step + Stripe test card if you want to exercise the full payment path.
- Customer/magic-link flows. These are out of scope; they live in the
  customer routes and have their own auth model.

## Troubleshooting

- **Stripe OAuth click selectors stale.** Stripe redesigns its Connect
  onboarding UI a few times a year. If the OAuth step times out, run
  `WORKERS=1 npm run test:debug` and pause at the OAuth step to identify
  the new selector, then update `lib/stripe-oauth.ts`.
- **`fetch failed` to mailpit.** The mailpit container's host must resolve.
  Confirm `curl http://mailpit.<TRAEFIK_HOST>:<port>/api/v1/info` from the
  runner.
- **TS errors before `npm install`.** Expected — the editor sees imports
  before deps land. Run `npm install` and they clear.
