# renderer-static

R2 bucket + native public custom domain that fronts the Next.js renderer's
`_next/static/*` tree at `cdn-assets.paymentform.io`.

Pairs with `renderer/.github/workflows/build-and-push-conatinaer-image.yml`'s
`renderer-upload-assets` job, which mirrors `.next/static/` 1:1 into
`r2://<bucket>/_next/static/` via `rclone` on every push to `main` / release /
manual dispatch.

**`public/` is NOT uploaded here.** Next.js `assetPrefix` does not rewrite
`/public/*` URLs (per Next.js docs) — those files are served from the
in-image `COPY public ./public` tree by `node server.js` (origin). Adding
`public/` to the CDN would require source-level URL rewrites plus a
Cloudflare edge rule and is out of scope.

## Why not the `cdn-worker` pattern?

`cdn-ap.paymentform.io` (tenant-uploaded assets) routes through
`../cdn-worker/`, a Cloudflare Worker that fronts the R2 bucket and rewrites
headers per request. This module deliberately skips that layer.

| Concern | `cdn-ap` (Worker) | `cdn-assets` (this module) |
|---|---|---|
| Cache-Control | rewritten per request in the Worker | set on object upload |
| Range / 304 revalidation | Worker logic | edge-handled against R2 origin |
| Content-Type | sniffed/overridden in the Worker | inferred by R2 from extension |
| Operational surface | Worker script + binding | bucket only |

For content-hashed, immutable static assets the Worker buys us nothing —
upload-time headers are sufficient and there's no per-request transformation
to perform. One fewer Worker = one less moving part to operate, monitor, and
roll back.

If `cdn-assets` ever needs per-request logic (signed URLs, geo restrictions,
header injection), this module should grow a sibling Worker resource rather
than route through `cdn-worker/` to keep the two CDN responsibilities
isolated.

## Cache strategy

| Prefix | Cache-Control | Set by | Why |
|---|---|---|---|
| `_next/static/chunks/<hash>.{js,css}` | `public, max-age=31536000, immutable` | CI rclone `--header-upload` | Next.js content-hashes every chunk; the URL changes whenever bytes change. Year-long browser cache is safe and the `immutable` directive skips revalidation entirely. |
| `_next/static/media/<hash>.<ext>` | `public, max-age=31536000, immutable` | CI rclone `--header-upload` | Same content-hash guarantee for fonts / images / etc. |
| `_next/static/<buildId>/_buildManifest.js` etc. | `public, max-age=31536000, immutable` | CI rclone `--header-upload` | Per-build manifests; replaced on every new build under a new buildId path. |

The bucket's lifecycle rule deletes `_next/static/...` objects whose R2
`LastModified` is older than `var.static_retention_days` (default 30).
CI uses `rclone copy --no-check-dest` so every chunk in the build's output
gets its `LastModified` refreshed every run — eviction only targets chunks
that have NOT appeared in any build for the retention window.

## Rollback

Three levers, fastest first. Detailed in
`docs/plans/2026-05-23-item-4-r2-cdn-assets-plan.md`; quick reference:

1. **Disable CDN for new HTML, keep R2 in place.** Set `CDN_URL: ""` in
   `renderer/.github/workflows/build-and-push-conatinaer-image.yml`, push to
   `main`, deploy. New HTML embeds relative `/_next/static/...` paths served
   by the in-image bundle. R2 stays populated but unreferenced. Safest
   rollback — the in-image static files are always present.
2. **Deploy a known-good prior image.** `gh workflow run deploy-release.yml
   -f image_tag=<v1.x.y>`. The prior image's chunks live at the same
   `_next/static/chunks/<hash>.{js,css}` paths as today's build (content-
   hashed filenames coexist without collision); they're retained as long as
   *some* recent build still produces those bytes, plus `static_retention_days`
   of inactivity after they stop appearing. `latest-1` is only tagged on
   `release` events; pin a concrete version tag for hotfix rollbacks off
   `push:main` deploys.
3. **DNS cutover off the CDN.** Cloudflare dashboard: disable the R2 custom
   domain binding. Returning browsers see network errors for
   `cdn-assets.paymentform.io` until Level 1 deploys complete. **Last
   resort** — only if the CDN is actively serving wrong cache-control or is
   compromised.

## Wrangler fallback (if Terraform provider drift)

The lifecycle / CORS / custom-domain resources rely on the
`cloudflare/cloudflare ~> 5.19` schema. Before any apply that touches this
module, verify the schema:

```
terraform providers schema -json \
  | jq '.provider_schemas["registry.terraform.io/cloudflare/cloudflare"].resource_schemas | keys[]' \
  | grep r2
```

If a resource is renamed or unavailable, comment out the affected
`cloudflare_r2_bucket_*` resource and apply the rest via Terraform, then run
the equivalent Wrangler command out-of-band:

**Lifecycle (delete `_next/static/` objects older than 30 days):**

```
wrangler r2 bucket lifecycle add prod-paymentform-renderer-static \
  --id expire-old-next-static \
  --prefix _next/static/ \
  --expire-days 30
```

**CORS (public GET/HEAD with revalidation headers):**

```
cat > /tmp/cors.json <<'JSON'
[
  {
    "AllowedOrigins": ["*"],
    "AllowedMethods": ["GET", "HEAD"],
    "AllowedHeaders": ["Range", "If-None-Match", "If-Modified-Since"],
    "ExposeHeaders": ["ETag", "Content-Length", "Content-Range", "Accept-Ranges"],
    "MaxAgeSeconds": 86400
  }
]
JSON
wrangler r2 bucket cors put prod-paymentform-renderer-static --file /tmp/cors.json
```

**Custom domain (native public-bucket binding):**

```
wrangler r2 bucket domain add prod-paymentform-renderer-static \
  --domain cdn-assets.paymentform.io \
  --zone-id "$CF_ZONE_ID" \
  --min-tls 1.2
```

Open a follow-up issue tracking the Terraform convergence and remove the
Wrangler block from the runbook once the provider catches up.

## Inputs

See `variables.tf`. Notable defaults:

- `cors_origins = ["*"]` — tenant canonical hostnames are not enumerable at
  apply time and assets are public anyway.
- `static_retention_days = 30` — rollback window for `_next/static/...`.
- `location = "wnam"` — matches the application-storage US bucket.

## Outputs

- `bucket_name` — fully-qualified bucket name with `${environment}-` prefix.
  Pass to CI as `R2_BUCKET`.
- `custom_domain_url` — `https://<custom_domain>`. Pass to the renderer as
  `NEXT_PUBLIC_CDN_URL` at build time.

## Pre-merge operator checklist

The CI workflow that consumes this module needs the following set up before
the first run on `main`:

1. **Terraform applied.** `prod-paymentform-renderer-static` bucket + custom
   domain live. Confirm `curl -I https://cdn-assets.paymentform.io/_next/static/chunks/nonexistent.js`
   returns 404 (not 5xx).
2. **R2 API token.** Cloudflare dashboard → R2 → Manage R2 API Tokens →
   create with `Object Read & Write` permission scoped to **only** this
   bucket. No global account scope.
3. **GitHub `production` environment.** Renderer repo Settings →
   Environments → create `production` if missing. Optionally add required
   reviewers if deploy approvals are desired.
4. **Environment secrets** on `production`:
   - `R2_RENDERER_STATIC_ACCESS_KEY_ID`
   - `R2_RENDERER_STATIC_SECRET_ACCESS_KEY`
   - `CLOUDFLARE_ACCOUNT_ID` (if not already at repo/org level).
