/**
 * access.js — Layered access control for the /admin/* surface.
 *
 * Three independent gates, evaluated in order. Any fail returns 403 without
 * differentiating the reason in the response body (no info leak).
 *
 *   1. Country allowlist  (request.cf.country / CF-IPCountry header)
 *   2. IP allowlist       (CF-Connecting-IP) with IPv4 CIDR support
 *   3. Admin session      (admin_session cookie, HMAC-signed by ADMIN_TOKEN)
 *
 * Bearer-token JSON callers (curl / Postman) skip the cookie gate by hitting
 * the /api/* endpoints directly, which keep using requireBearer.
 *
 * CSRF protection for /admin POST/DELETE actions uses a double-submit cookie:
 * the worker sets `csrf` (non-HttpOnly) at login; the form ships it back in
 * a hidden field. A request whose form `csrf` mismatches the cookie is
 * rejected.
 */

const SESSION_COOKIE = "admin_session";
const CSRF_COOKIE = "csrf";
const SESSION_TTL_MS = 8 * 60 * 60 * 1000; // 8 hours

const TEXT_ENCODER = new TextEncoder();

// ─────────────────────────────────────────────────────────────────────────
//  Public API
// ─────────────────────────────────────────────────────────────────────────

/**
 * Check country + IP only. Returns null on pass, a 403 Response on fail.
 * Use this on /admin/login (no session yet) so unauthorised regions never
 * even see the login form.
 */
export function requireNetworkAccess(request, env) {
  const country = (request.cf && request.cf.country) || request.headers.get("CF-IPCountry") || "";
  if (!isCountryAllowed(country, env.ADMIN_ALLOWED_COUNTRIES)) {
    return deny();
  }

  const ip = request.headers.get("CF-Connecting-IP") || "";
  if (!isIpAllowed(ip, env.ADMIN_ALLOWED_IPS)) {
    return deny();
  }

  return null;
}

/**
 * Check network gates plus a valid admin_session cookie. Returns null on
 * pass, a Response on fail (403 for network, redirect to /admin/login for
 * missing/expired session).
 */
export async function requireAdminAccess(request, env) {
  const netFail = requireNetworkAccess(request, env);
  if (netFail) return netFail;

  const cookies = parseCookies(request.headers.get("Cookie") || "");
  const session = cookies[SESSION_COOKIE];
  if (!session) {
    return redirectToLogin(request);
  }

  const valid = await verifySessionToken(session, env.ADMIN_TOKEN || "");
  if (!valid) {
    return redirectToLogin(request);
  }

  return null;
}

/**
 * Verify a CSRF token from form data against the csrf cookie.
 * Returns null on pass, a 403 Response on fail.
 */
export function requireCsrf(request, formCsrf) {
  const cookies = parseCookies(request.headers.get("Cookie") || "");
  const cookieCsrf = cookies[CSRF_COOKIE] || "";
  if (!cookieCsrf || !formCsrf || !constantTimeEquals(cookieCsrf, formCsrf)) {
    return deny("Invalid CSRF token");
  }
  return null;
}

/**
 * Issue an admin_session cookie + csrf cookie. Caller builds the final
 * Response and merges these Set-Cookie headers in.
 *
 * @param {object}  env     worker env (must hold ADMIN_TOKEN)
 * @param {boolean} secure  set the cookie `Secure` attribute; pass false
 *                          only for http://localhost wrangler dev so
 *                          browsers will actually store the cookie
 * @returns {Promise<{ sessionCookie: string, csrfCookie: string, csrfValue: string }>}
 */
export async function issueAdminSession(env, secure = true) {
  const sessionToken = await signSessionToken(env.ADMIN_TOKEN || "");
  const csrfValue = randomToken(32);

  const sessionCookie = buildCookie(SESSION_COOKIE, sessionToken, {
    httpOnly: true,
    maxAgeSeconds: Math.floor(SESSION_TTL_MS / 1000),
    secure,
  });
  const csrfCookie = buildCookie(CSRF_COOKIE, csrfValue, {
    httpOnly: false, // form JS reads it
    maxAgeSeconds: Math.floor(SESSION_TTL_MS / 1000),
    secure,
  });

  return { sessionCookie, csrfCookie, csrfValue };
}

/**
 * Cookie strings that expire the session immediately. Use on logout.
 */
export function clearAdminSession(secure = true) {
  return [
    buildCookie(SESSION_COOKIE, "", { httpOnly: true, maxAgeSeconds: 0, secure }),
    buildCookie(CSRF_COOKIE, "", { httpOnly: false, maxAgeSeconds: 0, secure }),
  ];
}

export function readCsrfCookie(request) {
  const cookies = parseCookies(request.headers.get("Cookie") || "");
  return cookies[CSRF_COOKIE] || "";
}

// ─────────────────────────────────────────────────────────────────────────
//  Allowlist matching
// ─────────────────────────────────────────────────────────────────────────

function isCountryAllowed(country, allowlist) {
  const list = parseCsv(allowlist);
  if (list.length === 0) return true; // empty = unrestricted
  return list.includes(country.toUpperCase());
}

function isIpAllowed(ip, allowlist) {
  const list = parseCsv(allowlist);
  if (list.length === 0) return true;
  if (!ip) return false;

  for (const entry of list) {
    if (entry === ip) return true;
    if (entry.includes("/") && matchesCidr(ip, entry)) return true;
  }
  return false;
}

function matchesCidr(ip, cidr) {
  const [network, bitsStr] = cidr.split("/");
  const bits = Number(bitsStr);
  if (!Number.isFinite(bits) || bits < 0 || bits > 32) return false;

  const ipInt = ipv4ToInt(ip);
  const netInt = ipv4ToInt(network);
  if (ipInt === null || netInt === null) return false;

  if (bits === 0) return true;
  const mask = (0xffffffff << (32 - bits)) >>> 0;
  return (ipInt & mask) === (netInt & mask);
}

function ipv4ToInt(ip) {
  const parts = ip.split(".");
  if (parts.length !== 4) return null;
  let out = 0;
  for (const part of parts) {
    const n = Number(part);
    if (!Number.isInteger(n) || n < 0 || n > 255) return null;
    out = (out << 8) + n;
  }
  return out >>> 0;
}

function parseCsv(value) {
  if (!value) return [];
  return String(value)
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);
}

// ─────────────────────────────────────────────────────────────────────────
//  Session token: ts.<hmac> signed by ADMIN_TOKEN
// ─────────────────────────────────────────────────────────────────────────

async function signSessionToken(secret) {
  const ts = Date.now().toString();
  const sig = await hmac(secret, ts);
  return `${ts}.${sig}`;
}

async function verifySessionToken(token, secret) {
  if (!token || !secret) return false;
  const [tsStr, sig] = token.split(".");
  if (!tsStr || !sig) return false;

  const ts = Number(tsStr);
  if (!Number.isFinite(ts)) return false;
  if (Date.now() - ts > SESSION_TTL_MS) return false;

  const expected = await hmac(secret, tsStr);
  return constantTimeEquals(sig, expected);
}

async function hmac(secret, message) {
  const key = await crypto.subtle.importKey(
    "raw",
    TEXT_ENCODER.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign("HMAC", key, TEXT_ENCODER.encode(message));
  return base64UrlEncode(new Uint8Array(signature));
}

function constantTimeEquals(a, b) {
  const aBytes = TEXT_ENCODER.encode(a);
  const bBytes = TEXT_ENCODER.encode(b);
  let diff = aBytes.length === bBytes.length ? 0 : 1;
  const len = Math.max(aBytes.length, bBytes.length);
  for (let i = 0; i < len; i++) {
    diff |= (aBytes[i] || 0) ^ (bBytes[i] || 0);
  }
  return diff === 0;
}

function base64UrlEncode(bytes) {
  let str = "";
  for (let i = 0; i < bytes.length; i++) str += String.fromCharCode(bytes[i]);
  return btoa(str).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function randomToken(byteLen) {
  const bytes = new Uint8Array(byteLen);
  crypto.getRandomValues(bytes);
  return base64UrlEncode(bytes);
}

// ─────────────────────────────────────────────────────────────────────────
//  Cookie helpers
// ─────────────────────────────────────────────────────────────────────────

function parseCookies(header) {
  const out = {};
  if (!header) return out;
  for (const part of header.split(";")) {
    const eq = part.indexOf("=");
    if (eq < 0) continue;
    const k = part.slice(0, eq).trim();
    const v = part.slice(eq + 1).trim();
    if (k) out[k] = decodeURIComponent(v);
  }
  return out;
}

function buildCookie(name, value, { httpOnly, maxAgeSeconds, secure }) {
  const parts = [
    `${name}=${encodeURIComponent(value)}`,
    "Path=/admin",
    "SameSite=Strict",
  ];
  if (secure) parts.push("Secure");
  if (httpOnly) parts.push("HttpOnly");
  if (maxAgeSeconds === 0) {
    parts.push("Max-Age=0", "Expires=Thu, 01 Jan 1970 00:00:00 GMT");
  } else {
    parts.push(`Max-Age=${maxAgeSeconds}`);
  }
  return parts.join("; ");
}

// ─────────────────────────────────────────────────────────────────────────
//  Response helpers
// ─────────────────────────────────────────────────────────────────────────

function deny(reason = "Forbidden") {
  return new Response(reason, {
    status: 403,
    headers: { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "no-store" },
  });
}

function redirectToLogin(request) {
  const url = new URL(request.url);
  const next = encodeURIComponent(url.pathname + url.search);
  return new Response(null, {
    status: 302,
    headers: {
      Location: `/admin/login?next=${next}`,
      "Cache-Control": "no-store",
    },
  });
}
