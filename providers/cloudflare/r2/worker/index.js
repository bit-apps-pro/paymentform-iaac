export default {
  async fetch(request, env, ctx) {
    return handleRequest(request, env, ctx);
  }
};

const PAID_TIERS = new Set(['pro', 'business', 'enterprise']);
const ALLOWED_WIDTHS = new Set([400, 800, 1200, 1600, 2400]);
const TIER_CACHE_TTL_SECONDS = 300;
const TRANSFORM_QUALITY = 85;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
// 512 covers nested invoice / dated paths
// (e.g. `invoices/2026/05/invoice-INV-...-{uuid}.pdf` runs ~83 chars; deeper
// sub-org or per-region trees stay under 512). R2 key hard limit is 1024.
const MAX_FILENAME_LENGTH = 512;
// Hard cap on source image size we will hand to cf.image. Anything larger is
// either non-image (already transform-rejected) or an over-resolution outlier
// that risks blowing the per-request 128MB Worker memory ceiling when buffered.
const MAX_SOURCE_BYTES = 25 * 1024 * 1024;

// Per-isolate single-flight map. Coalesces concurrent first-viewers of the
// same variant within one isolate so we bill at most one cf.image transform
// per (variantKey, isolate-lifetime). Cross-isolate dedupe needs Durable
// Object — out of scope; this catches the common burst case.
const inflightTransforms = new Map();

async function handleRequest(request, env, ctx) {
  const url = new URL(request.url);
  const path = url.pathname.slice(1);

  if (request.method === 'OPTIONS') {
    return handleCorsPreflight();
  }

  if (request.method !== 'GET' && request.method !== 'HEAD') {
    return new Response('Method not allowed', {
      status: 405,
      headers: getCorsHeaders(),
    });
  }

  if (!isPublicPath(path)) {
    return new Response('Not found', {
      status: 404,
      headers: getCorsHeaders(),
    });
  }

  // Self-fetch loop guard for cf.image sub-request. The inner fetch carries
  // `__raw=1` + a magic token header so it always serves bytes from R2 and
  // never re-enters transform. External `__raw=1` requests are rejected to
  // prevent unauthed bucket rip via shareable CDN URLs (R2 Class B drain).
  if (url.searchParams.get('__raw') === '1') {
    const presented = request.headers.get('X-CDN-Self-Token') || '';
    if (!env.SELF_FETCH_TOKEN || !constantTimeEqual(presented, env.SELF_FETCH_TOKEN)) {
      return new Response('Forbidden', { status: 403, headers: getCorsHeaders() });
    }
    return serveOriginal(env, request, path);
  }

  const transformParams = parseTransformParams(url.searchParams);
  if (transformParams.error) {
    return new Response(transformParams.error, {
      status: 400,
      headers: {
        ...getCorsHeaders(),
        'Cache-Control': 'public, max-age=3600',
      },
    });
  }

  if (!transformParams.requested) {
    return serveOriginal(env, request, path);
  }

  // Tier check before rate limit: free tenants never enter transform path,
  // so don't burn rate budget on their (harmless) traffic.
  const tenantId = path.split('/')[0];
  const tier = await getTenantTier(env, tenantId);
  if (!canTransform(tier)) {
    return serveOriginal(env, request, path);
  }

  // Fail closed: missing limiter binding = uncapped transform billing. Bail.
  if (!env.ABUSE_LIMITER) {
    console.warn('abuse_limiter_missing', { tenantId, path });
    return serveOriginal(env, request, path);
  }

  const ip = request.headers.get('CF-Connecting-IP') || 'unknown';
  const limit = await env.ABUSE_LIMITER.limit({ key: `${ip}:${tenantId}` });
  if (!limit.success) {
    return new Response('Rate limited', {
      status: 429,
      headers: {
        ...getCorsHeaders(),
        'Retry-After': '60',
      },
    });
  }

  return transformAndCache(env, ctx, request, url, path, transformParams);
}

function parseTransformParams(searchParams) {
  const widthRaw = searchParams.get('w');
  if (widthRaw === null) {
    return { requested: false };
  }

  const width = parseInt(widthRaw, 10);
  if (!Number.isFinite(width) || !ALLOWED_WIDTHS.has(width)) {
    return { error: 'Invalid width' };
  }

  return { requested: true, width };
}

function negotiateFormat(request) {
  const accept = request.headers.get('Accept') || '';
  if (accept.includes('image/avif')) return 'avif';
  // Anything else (incl. older Safari sending */*) → webp. Universal support
  // since iOS 14 / Safari 14; collapses the "auto" branch so we don't fragment
  // the R2 variant namespace across clients with random Accept headers.
  return 'webp';
}

async function getTenantTier(env, tenantId) {
  if (!env.TENANT_KV) {
    return { tier: 'free', exp: 0 };
  }

  // KV's native edge cache via cacheTtl — survives across isolates per colo.
  // Avoids the silent-drop quirks of caches.default against synthetic hosts.
  const raw = await env.TENANT_KV.get(`tenant:${tenantId}`, {
    cacheTtl: TIER_CACHE_TTL_SECONDS,
  });
  return safeParseTier(raw);
}

function safeParseTier(raw) {
  if (!raw) return { tier: 'free', exp: 0 };
  try {
    const parsed = JSON.parse(raw) || {};
    return {
      tier: typeof parsed.tier === 'string' ? parsed.tier.toLowerCase() : 'free',
      exp: Number.isFinite(parsed.exp) ? parsed.exp : 0,
    };
  } catch {
    return { tier: 'free', exp: 0 };
  }
}

function canTransform({ tier, exp }) {
  const nowSeconds = Math.floor(Date.now() / 1000);
  if (PAID_TIERS.has(tier) && exp <= nowSeconds) {
    // Paid tenant past their subscription expiry — silent free-tier downgrade
    // without a log makes "why are images suddenly unoptimized" untriagable.
    console.log('tier_expired', { tier, exp, now: nowSeconds });
  }
  return exp > nowSeconds && PAID_TIERS.has(tier);
}

async function transformAndCache(env, ctx, request, url, path, { width }) {
  const format = negotiateFormat(request);
  const variantKey = buildVariantKey(path, width, format);

  const cached = await env.R2_BUCKET.get(variantKey);
  if (cached) {
    return serveR2Object(cached, variantKey, { vary: true });
  }

  // Single-flight: if another request in this isolate is already transforming
  // this exact variant, await it then re-check R2 (the in-flight write will
  // have completed). Bounds cold-start double-billing within an isolate.
  if (inflightTransforms.has(variantKey)) {
    try {
      await inflightTransforms.get(variantKey);
    } catch {
      // First flight failed — fall through to a fresh attempt.
    }
    const cachedAfterFlight = await env.R2_BUCKET.get(variantKey);
    if (cachedAfterFlight) {
      return serveR2Object(cachedAfterFlight, variantKey, { vary: true });
    }
  }

  const flight = runTransform(env, ctx, url, path, variantKey, width, format);
  inflightTransforms.set(variantKey, flight);
  try {
    return await flight;
  } finally {
    inflightTransforms.delete(variantKey);
  }
}

async function runTransform(env, ctx, url, path, variantKey, width, format) {
  // Fail closed when the magic-token binding is missing — the inner self-fetch
  // would 403 anyway, but cf.image still bills the dispatch attempt. Bail.
  if (!env.SELF_FETCH_TOKEN) {
    console.warn('self_fetch_token_missing', { path });
    return serveOriginal(env, null, path);
  }

  // Source-size guard. cf.image will accept large inputs but we'll buffer the
  // *output* in worker memory; cap at MAX_SOURCE_BYTES as a proxy for sane
  // outputs. Cheap HEAD avoids the bill on oversized sources before they fan
  // out to the transform stage. Missing `size` is treated as oversized — R2
  // should always populate it; absence is anomaly, not opportunity to bypass.
  try {
    const head = await env.R2_BUCKET.head(path);
    if (!head) {
      return new Response('File not found', { status: 404, headers: getCorsHeaders() });
    }
    if (head.size == null || head.size > MAX_SOURCE_BYTES) {
      console.warn('source_too_large_or_unknown', { path, size: head.size ?? null, cap: MAX_SOURCE_BYTES });
      return serveOriginal(env, null, path);
    }
  } catch (error) {
    console.error('source_head_error', { path, error: error.message });
    return serveOriginal(env, null, path);
  }

  const originUrl = buildSelfUrl(env, url, path);
  const subRequest = new Request(originUrl, {
    method: 'GET',
    headers: { 'X-CDN-Self-Token': env.SELF_FETCH_TOKEN },
  });

  let transformed;
  try {
    transformed = await fetch(subRequest, {
      cf: { image: { width, format, quality: TRANSFORM_QUALITY, fit: 'scale-down' } },
    });
  } catch (error) {
    console.error('cf_image_transform_fetch_error', {
      path, width, format, error: error.message,
    });
    return serveOriginal(env, null, path);
  }

  if (!transformed.ok || !transformed.body) {
    console.error('cf_image_transform_non_ok', {
      path, width, format, status: transformed.status,
    });
    return serveOriginal(env, null, path);
  }

  const contentType = transformed.headers.get('content-type') || getContentType(path);

  // Buffer in memory (bounded by MAX_SOURCE_BYTES guard above + cf.image
  // output sizing). Avoids ReadableStream.tee() backpressure on slow clients
  // holding the R2 put open. Defensive slice ensures R2's put-consumer doesn't
  // detach the underlying ArrayBuffer from the client Response.
  const buffer = await transformed.arrayBuffer();

  ctx.waitUntil(env.R2_BUCKET.put(variantKey, buffer.slice(0), {
    httpMetadata: { contentType },
  }));

  const headers = new Headers(getCorsHeaders());
  headers.set('Content-Type', contentType);
  headers.set('Cache-Control', 'public, max-age=31536000, immutable');
  headers.set('Vary', 'Accept');
  headers.set('Content-Length', String(buffer.byteLength));
  return new Response(buffer, { status: 200, headers });
}

function buildVariantKey(path, width, format) {
  const parts = path.split('/');
  const tenantId = parts[0];
  const fileId = parts[2];
  const filename = parts.slice(3).join('/');
  return `${tenantId}/public/${fileId}/.variants/${filename}.w${width}.${format}`;
}

function buildSelfUrl(env, url, path) {
  const host = env.SELF_HOST || url.host;
  return `https://${host}/${path}?__raw=1`;
}

async function serveOriginal(env, request, path) {
  try {
    const headObject = await env.R2_BUCKET.head(path);
    if (!headObject) {
      return new Response('File not found', {
        status: 404,
        headers: getCorsHeaders(),
      });
    }

    if (request && isNotModified(request, headObject)) {
      return new Response(null, {
        status: 304,
        headers: buildResponseHeaders(headObject, path, { includeContentLength: false }),
      });
    }

    const rangeHeader = request ? request.headers.get('Range') : null;
    const rangeSpec = rangeHeader ? parseRange(rangeHeader, headObject.size) : null;

    if (rangeHeader && !rangeSpec) {
      return new Response('Range not satisfiable', {
        status: 416,
        headers: {
          ...getCorsHeaders(),
          'Content-Range': `bytes */${headObject.size}`,
        },
      });
    }

    const getOptions = rangeSpec
      ? { range: { offset: rangeSpec.start, length: rangeSpec.end - rangeSpec.start + 1 } }
      : undefined;
    const object = await env.R2_BUCKET.get(path, getOptions);

    if (!object) {
      return new Response('File not found', {
        status: 404,
        headers: getCorsHeaders(),
      });
    }

    const headers = buildResponseHeaders(object, path, { includeContentLength: true });

    if (rangeSpec) {
      headers.set('Content-Range', `bytes ${rangeSpec.start}-${rangeSpec.end}/${headObject.size}`);
      headers.set('Content-Length', String(rangeSpec.end - rangeSpec.start + 1));
      return new Response(object.body, { status: 206, headers });
    }

    return new Response(object.body, { status: 200, headers });
  } catch (error) {
    console.error('serve_original_error', { path, error: error.message });
    return new Response('Internal server error', {
      status: 500,
      headers: getCorsHeaders(),
    });
  }
}

function serveR2Object(object, path, { vary } = {}) {
  const headers = buildResponseHeaders(object, path, { includeContentLength: true });
  if (vary) headers.set('Vary', 'Accept');
  return new Response(object.body, { status: 200, headers });
}

function buildResponseHeaders(object, path, { includeContentLength }) {
  const headers = new Headers(getCorsHeaders());
  headers.set('Content-Type', object.httpMetadata?.contentType || getContentType(path));
  headers.set('Cache-Control', 'public, max-age=31536000, immutable');
  headers.set('ETag', object.httpEtag);
  headers.set('Last-Modified', object.uploaded.toUTCString());
  headers.set('Accept-Ranges', 'bytes');
  if (includeContentLength && object.size != null) {
    headers.set('Content-Length', String(object.size));
  }
  return headers;
}

function isNotModified(request, object) {
  const ifNoneMatch = request.headers.get('If-None-Match');
  if (ifNoneMatch) {
    const tags = ifNoneMatch.split(',').map(t => t.trim());
    if (tags.includes(object.httpEtag) || tags.includes('*')) {
      return true;
    }
  }

  const ifModifiedSince = request.headers.get('If-Modified-Since');
  if (ifModifiedSince) {
    const since = Date.parse(ifModifiedSince);
    if (!Number.isNaN(since) && object.uploaded.getTime() <= since) {
      return true;
    }
  }

  return false;
}

// Parse RFC 7233 `Range: bytes=...`. Returns null when unsatisfiable or
// malformed. Supports a single byte range plus the suffix form `bytes=-N`.
function parseRange(rangeHeader, size) {
  if (!size) return null;

  const match = rangeHeader.match(/^bytes=(\d*)-(\d*)$/);
  if (!match) return null;

  const startRaw = match[1];
  const endRaw = match[2];

  let start;
  let end;

  if (startRaw === '' && endRaw === '') {
    return null;
  }

  if (startRaw === '') {
    const suffixLength = parseInt(endRaw, 10);
    if (suffixLength <= 0) return null;
    start = Math.max(0, size - suffixLength);
    end = size - 1;
  } else {
    start = parseInt(startRaw, 10);
    end = endRaw === '' ? size - 1 : parseInt(endRaw, 10);
  }

  if (Number.isNaN(start) || Number.isNaN(end)) return null;
  if (start > end || start >= size) return null;

  return { start, end: Math.min(end, size - 1) };
}

function handleCorsPreflight() {
  return new Response(null, {
    status: 204,
    headers: {
      ...getCorsHeaders(),
      'Access-Control-Allow-Methods': 'GET, HEAD, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization, Range, If-None-Match, If-Modified-Since',
      'Access-Control-Max-Age': '86400',
    },
  });
}

// Validates a public CDN path: `{tenant_uuid}/public/{file_uuid}/{filename}`.
// Rejects:
//   - non-UUID tenant or file segments (closes cost-leak via fabricated paths)
//   - any segment beginning with `.` (e.g. `.variants/` internal namespace)
//   - direct hits on the variant key namespace (transform spam vector)
//   - empty / over-long / control-char filenames (cache-pollution vector)
function isPublicPath(path) {
  const parts = path.split('/');
  if (parts.length < 4 || parts[1] !== 'public') return false;
  if (!UUID_RE.test(parts[0])) return false;
  if (!UUID_RE.test(parts[2])) return false;
  for (const part of parts) {
    if (part.length === 0) return false;
    if (part.startsWith('.')) return false;
  }
  const filename = parts.slice(3).join('/');
  if (filename.length === 0 || filename.length > MAX_FILENAME_LENGTH) return false;
  // eslint-disable-next-line no-control-regex
  if (/[\x00-\x1f\x7f]/.test(filename)) return false;
  return true;
}

function getCorsHeaders() {
  return {
    'Access-Control-Allow-Origin': '*',
  };
}

// Length-leaking but value-non-leaking string compare. Sufficient for the
// self-fetch token (fixed length per deploy via random_id), and avoids the
// early-exit timing channel of `!==`.
function constantTimeEqual(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string') return false;
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}

function getContentType(path) {
  const ext = path.split('.').pop()?.toLowerCase();
  const contentTypes = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'gif': 'image/gif',
    'svg': 'image/svg+xml',
    'webp': 'image/webp',
    'avif': 'image/avif',
    'pdf': 'application/pdf',
    'txt': 'text/plain',
    'json': 'application/json',
    'js': 'application/javascript',
    'css': 'text/css',
    'html': 'text/html',
    'mp4': 'video/mp4',
    'webm': 'video/webm',
    'mp3': 'audio/mpeg',
    'wav': 'audio/wav',
    'zip': 'application/zip',
    'doc': 'application/msword',
    'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls': 'application/vnd.ms-excel',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  };

  return contentTypes[ext] || 'application/octet-stream';
}
