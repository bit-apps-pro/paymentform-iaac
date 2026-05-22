import { checkService, overallStatus } from "./health.js";
import { renderHtml } from "./page.js";
import { renderAtom } from "./feed.js";
import { listIncidents, createIncident, appendUpdate, runAutoDetection, pruneOldIncidents } from "./incidents.js";
import { requireBearer } from "./auth.js";
import {
  insertLog,
  insertLogBatch,
  queryLogs,
  purgeExpired,
  purgeBefore,
  deleteLogById,
  getLogById,
} from "./logs.js";
import {
  requireNetworkAccess,
  requireAdminAccess,
  requireCsrf,
  issueAdminSession,
  clearAdminSession,
  readCsrfCookie,
} from "./access.js";
import { renderLogin, renderLogs, renderLogDetail, renderIncidents } from "./admin.js";

const CACHE_TTL_SECONDS = 300;

async function loadHistory(env, days) {
  const keys = [];
  const now = new Date();
  for (let i = 0; i < days; i++) {
    const d = new Date(now);
    d.setUTCDate(d.getUTCDate() - i);
    keys.push("health:day:" + d.toISOString().slice(0, 10));
  }
  const results = await Promise.all(keys.map((k) => env.INCIDENTS_KV.get(k, "json").catch(() => null)));
  const history = {};
  for (let i = 0; i < days; i++) {
    if (results[i]) {
      history[keys[i].slice("health:day:".length)] = results[i];
    }
  }
  return history;
}

function getServices(env) {
  const raw = env.SERVICES_JSON;
  // wrangler --var sometimes auto-parses JSON-shaped values into objects/arrays
  // before they reach the worker. Handle both shapes so a Terraform deploy
  // doesn't silently zero out the service list.
  if (Array.isArray(raw)) return raw;
  if (typeof raw === "string" && raw.length > 0) {
    try {
      return JSON.parse(raw);
    } catch {
      return [];
    }
  }
  return [];
}

export default {
  async scheduled(_event, env) {
    try {
      const services = getServices(env);
      if (!services || services.length === 0) {
        console.log("No services configured, skipping health check");
        return;
      }

      const results = await Promise.all(services.map(checkService));
      const overall = overallStatus(results);
      const checkedAt = new Date().toUTCString();

      await env.INCIDENTS_KV.put("health:current", JSON.stringify({ services: results, overall, checkedAt }));

      // Persist daily health snapshot for 90-day chart
      const dayKey = "health:day:" + new Date().toISOString().slice(0, 10);
      const daySnapshot = results.map((s) => ({ name: s.name, status: s.status }));
      await env.INCIDENTS_KV.put(dayKey, JSON.stringify(daySnapshot));

      await runAutoDetection(env, { services: results });
      await pruneOldIncidents(env);

      if (env.LOGS_DB) {
        try {
          const purged = await purgeExpired(env.LOGS_DB);
          if (purged > 0) console.log("logs: purged " + purged + " expired rows");
        } catch (e) {
          console.error("logs purge failed:", e);
        }
      }
    } catch (err) {
      console.error("scheduled handler error:", err);
    }
  },

  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname;
    const method = request.method;

    if (method === "GET" && path === "/") {
      let cached = await env.INCIDENTS_KV.get("health:current", "json");
      let services, overall, checkedAt;

      if (!cached) {
        const svcs = getServices(env);
        services = await Promise.all(svcs.map(checkService));
        overall = overallStatus(services);
        checkedAt = new Date().toUTCString();
        await env.INCIDENTS_KV.put("health:current", JSON.stringify({ services, overall, checkedAt }));
      } else {
        ({ services, overall, checkedAt } = cached);
      }

      const incidents = await listIncidents(env);
      const history = await loadHistory(env, 90);
      const html = renderHtml({ services, overall, checkedAt, incidents, history });
      return new Response(html, {
        status: 200,
        headers: { "Content-Type": "text/html;charset=UTF-8", "Cache-Control": `public, max-age=${CACHE_TTL_SECONDS}` },
      });
    }

    if (method === "GET" && path === "/status") {
      const cached = await env.INCIDENTS_KV.get("health:current", "json");
      let services, overall, checkedAt;

      if (!cached) {
        const svcs = getServices(env);
        services = await Promise.all(svcs.map(checkService));
        overall = overallStatus(services);
        checkedAt = new Date().toUTCString();
        await env.INCIDENTS_KV.put("health:current", JSON.stringify({ services, overall, checkedAt }));
      } else {
        ({ services, overall, checkedAt } = cached);
      }

      const incidents = await listIncidents(env);
      const openIncidents = incidents.filter((i) => !i.resolvedAt);
      const httpStatus = overall === "down" ? 503 : 200;

      return new Response(JSON.stringify({ overall, checkedAt, services, openIncidents }, null, 2), {
        status: httpStatus,
        headers: { "Content-Type": "application/json", "Cache-Control": `public, max-age=${CACHE_TTL_SECONDS}` },
      });
    }

    if (method === "GET" && path === "/feed.xml") {
      const incidents = await listIncidents(env);
      const xml = renderAtom(incidents);
      return new Response(xml, {
        status: 200,
        headers: { "Content-Type": "application/atom+xml; charset=utf-8", "Cache-Control": `public, max-age=${CACHE_TTL_SECONDS}` },
      });
    }

    if (method === "GET" && path === "/api/debug") {
      const authResp = await requireBearer(request, env);
      if (authResp) return authResp;

      const raw = env.SERVICES_JSON;
      const rawType = Array.isArray(raw) ? "array" : typeof raw;
      const parsedServices = getServices(env);

      const today = new Date();
      const dayKeys = [];
      for (let i = 0; i < 7; i++) {
        const d = new Date(today);
        d.setUTCDate(d.getUTCDate() - i);
        dayKeys.push("health:day:" + d.toISOString().slice(0, 10));
      }
      const dayValues = await Promise.all(
        dayKeys.map((k) => env.INCIDENTS_KV.get(k, "json").catch((err) => ({ __error: err.message }))),
      );
      const dayPresence = dayKeys.map((k, i) => ({
        key: k,
        present: dayValues[i] !== null,
        size: Array.isArray(dayValues[i]) ? dayValues[i].length : null,
        error: dayValues[i] && dayValues[i].__error ? dayValues[i].__error : null,
      }));

      const current = await env.INCIDENTS_KV.get("health:current", "json").catch((err) => ({ __error: err.message }));
      const counters = await env.INCIDENTS_KV.get("health:counters", "json").catch((err) => ({ __error: err.message }));

      const incidentList = await env.INCIDENTS_KV.list({ prefix: "incident:", limit: 50 }).catch((err) => ({ __error: err.message }));

      return new Response(
        JSON.stringify(
          {
            now: new Date().toISOString(),
            servicesBinding: {
              rawType,
              rawSnippet: typeof raw === "string" ? raw.slice(0, 200) : null,
              parsedCount: Array.isArray(parsedServices) ? parsedServices.length : null,
              parsedNames: Array.isArray(parsedServices) ? parsedServices.map((s) => s && s.name) : null,
            },
            kv: {
              healthCurrent: current,
              countersPresent: counters !== null,
              dayPresence,
              incidentKeyCount: incidentList.keys ? incidentList.keys.length : null,
              incidentListError: incidentList.__error || null,
            },
          },
          null,
          2,
        ),
        { status: 200, headers: { "Content-Type": "application/json" } },
      );
    }

    if (method === "GET" && path === "/api/incidents") {
      const incidents = await listIncidents(env);
      return new Response(JSON.stringify(incidents, null, 2), {
        status: 200,
        headers: { "Content-Type": "application/json", "Cache-Control": `public, max-age=${CACHE_TTL_SECONDS}` },
      });
    }

    if (method === "POST" && path === "/api/incidents") {
      const authResp = await requireBearer(request, env);
      if (authResp) return authResp;

      let body;
      try {
        body = await request.json();
      } catch {
        return new Response(JSON.stringify({ error: "invalid_json" }), { status: 400, headers: { "Content-Type": "application/json" } });
      }

      try {
        const incident = await createIncident(env, body);
        return new Response(JSON.stringify(incident, null, 2), {
          status: 201,
          headers: { "Content-Type": "application/json" },
        });
      } catch (err) {
        return new Response(JSON.stringify({ error: err.message }), {
          status: 400,
          headers: { "Content-Type": "application/json" },
        });
      }
    }

    // Shortcut for support tooling: mark an incident resolved in one call.
    // Optional JSON body: { body?: string } adds a closing update note.
    if (method === "POST" && /^\/api\/incidents\/[^/]+\/resolve$/.test(path)) {
      const authResp = await requireBearer(request, env);
      if (authResp) return authResp;

      const id = path.split("/")[3];

      let body = {};
      try {
        if (request.headers.get("Content-Length") && Number(request.headers.get("Content-Length")) > 0) {
          body = await request.json();
        }
      } catch {
        return new Response(JSON.stringify({ error: "invalid_json" }), { status: 400, headers: { "Content-Type": "application/json" } });
      }

      try {
        const incident = await appendUpdate(env, id, {
          status: "resolved",
          body: body.body || "Resolved by support.",
        });
        if (!incident) {
          return new Response(JSON.stringify({ error: "not_found" }), { status: 404, headers: { "Content-Type": "application/json" } });
        }
        return new Response(JSON.stringify(incident, null, 2), {
          status: 200,
          headers: { "Content-Type": "application/json" },
        });
      } catch (err) {
        return new Response(JSON.stringify({ error: err.message }), {
          status: 409,
          headers: { "Content-Type": "application/json" },
        });
      }
    }

    if (method === "PATCH" && path.startsWith("/api/incidents/")) {
      const authResp = await requireBearer(request, env);
      if (authResp) return authResp;

      const id = path.slice("/api/incidents/".length);

      let body;
      try {
        body = await request.json();
      } catch {
        return new Response(JSON.stringify({ error: "invalid_json" }), { status: 400, headers: { "Content-Type": "application/json" } });
      }

      try {
        const incident = await appendUpdate(env, id, body);
        if (!incident) {
          return new Response(JSON.stringify({ error: "not_found" }), { status: 404, headers: { "Content-Type": "application/json" } });
        }
        return new Response(JSON.stringify(incident, null, 2), {
          status: 200,
          headers: { "Content-Type": "application/json" },
        });
      } catch (err) {
        return new Response(JSON.stringify({ error: err.message }), {
          status: 409,
          headers: { "Content-Type": "application/json" },
        });
      }
    }

    // -----------------------------------------------------------------------
    // Logs ingestion + query (D1-backed).
    // -----------------------------------------------------------------------

    if (method === "POST" && path === "/api/logs") {
      const authResp = await requireBearer(request, env, "LOG_INGEST_TOKEN");
      if (authResp) return authResp;

      if (!env.LOGS_DB) {
        return new Response(JSON.stringify({ error: "logs_db_unbound" }), { status: 503, headers: { "Content-Type": "application/json" } });
      }

      let body;
      try {
        body = await request.json();
      } catch {
        return new Response(JSON.stringify({ error: "invalid_json" }), { status: 400, headers: { "Content-Type": "application/json" } });
      }

      try {
        const result = await insertLog(env.LOGS_DB, body);
        return new Response(JSON.stringify(result), { status: 201, headers: { "Content-Type": "application/json" } });
      } catch (err) {
        return new Response(JSON.stringify({ error: err.message }), { status: 400, headers: { "Content-Type": "application/json" } });
      }
    }

    if (method === "POST" && path === "/api/logs/batch") {
      const authResp = await requireBearer(request, env, "LOG_INGEST_TOKEN");
      if (authResp) return authResp;

      if (!env.LOGS_DB) {
        return new Response(JSON.stringify({ error: "logs_db_unbound" }), { status: 503, headers: { "Content-Type": "application/json" } });
      }

      let body;
      try {
        body = await request.json();
      } catch {
        return new Response(JSON.stringify({ error: "invalid_json" }), { status: 400, headers: { "Content-Type": "application/json" } });
      }

      const records = Array.isArray(body) ? body : Array.isArray(body && body.records) ? body.records : null;
      if (!records) {
        return new Response(JSON.stringify({ error: "expected array of records or { records: [...] }" }), { status: 400, headers: { "Content-Type": "application/json" } });
      }

      try {
        const result = await insertLogBatch(env.LOGS_DB, records);
        return new Response(JSON.stringify(result), { status: 201, headers: { "Content-Type": "application/json" } });
      } catch (err) {
        return new Response(JSON.stringify({ error: err.message }), { status: 400, headers: { "Content-Type": "application/json" } });
      }
    }

    if (method === "GET" && path === "/api/logs") {
      const authResp = await requireBearer(request, env);
      if (authResp) return authResp;

      if (!env.LOGS_DB) {
        return new Response(JSON.stringify({ error: "logs_db_unbound" }), { status: 503, headers: { "Content-Type": "application/json" } });
      }

      const filters = Object.fromEntries(url.searchParams.entries());
      try {
        const rows = await queryLogs(env.LOGS_DB, filters);
        return new Response(JSON.stringify({ count: rows.length, rows }, null, 2), {
          status: 200,
          headers: { "Content-Type": "application/json" },
        });
      } catch (err) {
        return new Response(JSON.stringify({ error: err.message }), { status: 400, headers: { "Content-Type": "application/json" } });
      }
    }

    if (method === "GET" && /^\/api\/logs\/\d+$/.test(path)) {
      const authResp = await requireBearer(request, env);
      if (authResp) return authResp;

      if (!env.LOGS_DB) {
        return new Response(JSON.stringify({ error: "logs_db_unbound" }), { status: 503, headers: { "Content-Type": "application/json" } });
      }

      const id = path.slice("/api/logs/".length);
      try {
        const row = await getLogById(env.LOGS_DB, id);
        if (!row) {
          return new Response(JSON.stringify({ error: "not_found" }), { status: 404, headers: { "Content-Type": "application/json" } });
        }
        return new Response(JSON.stringify(row, null, 2), { status: 200, headers: { "Content-Type": "application/json" } });
      } catch (err) {
        return new Response(JSON.stringify({ error: err.message }), { status: 400, headers: { "Content-Type": "application/json" } });
      }
    }

    if (method === "DELETE" && /^\/api\/logs\/\d+$/.test(path)) {
      const authResp = await requireBearer(request, env);
      if (authResp) return authResp;

      if (!env.LOGS_DB) {
        return new Response(JSON.stringify({ error: "logs_db_unbound" }), { status: 503, headers: { "Content-Type": "application/json" } });
      }

      const id = path.slice("/api/logs/".length);
      try {
        const removed = await deleteLogById(env.LOGS_DB, id);
        return new Response(JSON.stringify({ removed }), {
          status: removed ? 200 : 404,
          headers: { "Content-Type": "application/json" },
        });
      } catch (err) {
        return new Response(JSON.stringify({ error: err.message }), { status: 400, headers: { "Content-Type": "application/json" } });
      }
    }

    if (method === "DELETE" && path === "/api/logs") {
      const authResp = await requireBearer(request, env);
      if (authResp) return authResp;

      if (!env.LOGS_DB) {
        return new Response(JSON.stringify({ error: "logs_db_unbound" }), { status: 503, headers: { "Content-Type": "application/json" } });
      }

      const before = url.searchParams.get("before");
      if (!before) {
        return new Response(JSON.stringify({ error: "before=<unix_ms> required" }), { status: 400, headers: { "Content-Type": "application/json" } });
      }

      try {
        const removed = await purgeBefore(env.LOGS_DB, before);
        return new Response(JSON.stringify({ removed }), { status: 200, headers: { "Content-Type": "application/json" } });
      } catch (err) {
        return new Response(JSON.stringify({ error: err.message }), { status: 400, headers: { "Content-Type": "application/json" } });
      }
    }

    // -----------------------------------------------------------------------
    // Admin browser UI. Country/IP gates apply to every /admin/* request;
    // /admin/login + /admin (the entry point) only require the network gate
    // so users from allowed networks can see the login form, every other
    // route additionally needs a valid `admin_session` cookie.
    // -----------------------------------------------------------------------

    if (path === "/admin" || path === "/admin/") {
      const netFail = requireNetworkAccess(request, env);
      if (netFail) return netFail;
      return redirect("/admin/logs");
    }

    if (method === "GET" && path === "/admin/login") {
      const netFail = requireNetworkAccess(request, env);
      if (netFail) return netFail;
      const next = url.searchParams.get("next") || "/admin/logs";
      return htmlResponse(renderLogin({ next }));
    }

    if (method === "POST" && path === "/admin/login") {
      const netFail = requireNetworkAccess(request, env);
      if (netFail) return netFail;

      const form = await readForm(request);
      const expected = env.ADMIN_TOKEN || "";
      const presented = String(form.get("token") || "");

      if (!expected || !timingSafeEquals(presented, expected)) {
        return htmlResponse(renderLogin({ error: "Invalid token", next: String(form.get("next") || "/admin/logs") }), 401);
      }

      const secure = url.protocol === "https:";
      const { sessionCookie, csrfCookie } = await issueAdminSession(env, secure);
      const next = String(form.get("next") || "/admin/logs");
      return new Response(null, {
        status: 303,
        headers: appendSetCookies(
          new Headers({ Location: sanitiseNext(next), "Cache-Control": "no-store" }),
          [sessionCookie, csrfCookie],
        ),
      });
    }

    if (method === "POST" && path === "/admin/logout") {
      const accessFail = await requireAdminAccess(request, env);
      if (accessFail) return accessFail;

      const form = await readForm(request);
      const csrfFail = requireCsrf(request, String(form.get("csrf") || ""));
      if (csrfFail) return csrfFail;

      return new Response(null, {
        status: 303,
        headers: appendSetCookies(
          new Headers({ Location: "/admin/login", "Cache-Control": "no-store" }),
          clearAdminSession(url.protocol === "https:"),
        ),
      });
    }

    if (method === "GET" && path === "/admin/logs") {
      const accessFail = await requireAdminAccess(request, env);
      if (accessFail) return accessFail;

      if (!env.LOGS_DB) {
        return htmlResponse(`<p>D1 not bound. <a href="/admin/login">Re-login</a></p>`, 503);
      }

      const filters = filtersFromSearchParams(url.searchParams);
      const queryFilters = toQueryFilters(filters);
      const rows = await queryLogs(env.LOGS_DB, queryFilters);
      const csrf = readCsrfCookie(request);

      return htmlResponse(renderLogs({ rows, filters, csrf, flash: url.searchParams.get("flash") || "" }));
    }

    if (method === "GET" && /^\/admin\/logs\/\d+$/.test(path)) {
      const accessFail = await requireAdminAccess(request, env);
      if (accessFail) return accessFail;

      if (!env.LOGS_DB) {
        return htmlResponse(`<p>D1 not bound.</p>`, 503);
      }

      const id = path.slice("/admin/logs/".length);
      let row;
      try {
        row = await getLogById(env.LOGS_DB, id);
      } catch (err) {
        return new Response(err.message, { status: 400 });
      }
      if (!row) {
        return htmlResponse(`<p>Log #${escapeHtmlString(id)} not found. <a href="/admin/logs">Back</a></p>`, 404);
      }

      const backHref = url.searchParams.get("back") || "/admin/logs";
      const csrf = readCsrfCookie(request);
      return htmlResponse(renderLogDetail({ row, csrf, backHref }));
    }

    if (method === "POST" && path === "/admin/logs/delete") {
      const accessFail = await requireAdminAccess(request, env);
      if (accessFail) return accessFail;

      const form = await readForm(request);
      const csrfFail = requireCsrf(request, String(form.get("csrf") || ""));
      if (csrfFail) return csrfFail;

      if (!env.LOGS_DB) {
        return new Response("logs_db_unbound", { status: 503 });
      }

      try {
        await deleteLogById(env.LOGS_DB, String(form.get("id") || ""));
      } catch (err) {
        return new Response(err.message, { status: 400 });
      }

      const next = sanitiseNext(String(form.get("next") || "/admin/logs"));
      return redirect(next + (next.includes("?") ? "&" : "?") + "flash=" + encodeURIComponent("Log row deleted"));
    }

    if (method === "POST" && path === "/admin/logs/purge") {
      const accessFail = await requireAdminAccess(request, env);
      if (accessFail) return accessFail;

      const form = await readForm(request);
      const csrfFail = requireCsrf(request, String(form.get("csrf") || ""));
      if (csrfFail) return csrfFail;

      if (!env.LOGS_DB) return new Response("logs_db_unbound", { status: 503 });

      const beforeIso = String(form.get("before_iso") || "");
      const beforeTs = Date.parse(beforeIso);
      if (!Number.isFinite(beforeTs)) {
        return new Response("before_iso required (YYYY-MM-DDTHH:mm)", { status: 400 });
      }

      try {
        const removed = await purgeBefore(env.LOGS_DB, beforeTs);
        return redirect("/admin/logs?flash=" + encodeURIComponent(`Purged ${removed} rows before ${beforeIso}`));
      } catch (err) {
        return new Response(err.message, { status: 400 });
      }
    }

    if (method === "GET" && path === "/admin/incidents") {
      const accessFail = await requireAdminAccess(request, env);
      if (accessFail) return accessFail;

      const incidents = await listIncidents(env);
      const csrf = readCsrfCookie(request);
      return htmlResponse(renderIncidents({ incidents, csrf, flash: url.searchParams.get("flash") || "" }));
    }

    if (method === "POST" && path === "/admin/incidents/create") {
      const accessFail = await requireAdminAccess(request, env);
      if (accessFail) return accessFail;

      const form = await readForm(request);
      const csrfFail = requireCsrf(request, String(form.get("csrf") || ""));
      if (csrfFail) return csrfFail;

      const affectedServices = String(form.get("affectedServices") || "")
        .split(",")
        .map((s) => s.trim())
        .filter(Boolean);

      try {
        await createIncident(env, {
          title: String(form.get("title") || "").trim(),
          severity: String(form.get("severity") || "minor"),
          affectedServices,
          body: String(form.get("body") || "").trim() || null,
          source: "manual",
        });
        return redirect("/admin/incidents?flash=" + encodeURIComponent("Incident created"));
      } catch (err) {
        return new Response(err.message, { status: 400 });
      }
    }

    {
      const m = /^\/admin\/incidents\/([^/]+)\/(update|resolve)$/.exec(path);
      if (method === "POST" && m) {
        const accessFail = await requireAdminAccess(request, env);
        if (accessFail) return accessFail;

        const form = await readForm(request);
        const csrfFail = requireCsrf(request, String(form.get("csrf") || ""));
        if (csrfFail) return csrfFail;

        const [, id, action] = m;
        const payload =
          action === "resolve"
            ? { status: "resolved", body: String(form.get("body") || "Resolved by support.") }
            : {
                status: String(form.get("status") || "") || null,
                body: String(form.get("body") || "").trim() || null,
              };

        try {
          const updated = await appendUpdate(env, id, payload);
          if (!updated) return new Response("not_found", { status: 404 });
          return redirect("/admin/incidents?flash=" + encodeURIComponent(action === "resolve" ? "Resolved" : "Updated"));
        } catch (err) {
          return new Response(err.message, { status: 409 });
        }
      }
    }

    return new Response("Not Found", { status: 404 });
  },
};

// ─────────────────────────────────────────────────────────────────────────
// Local helpers (HTTP/HTML plumbing).
// Auth, cookies, CSRF and HMAC live in access.js.
// ─────────────────────────────────────────────────────────────────────────

function htmlResponse(html, status = 200) {
  return new Response(html, {
    status,
    headers: {
      "Content-Type": "text/html;charset=UTF-8",
      "Cache-Control": "no-store",
      "X-Frame-Options": "DENY",
      "Content-Security-Policy":
        "default-src 'self'; style-src 'self' 'unsafe-inline'; script-src 'self'; img-src 'self' data:; form-action 'self'",
      "Referrer-Policy": "no-referrer",
    },
  });
}

function redirect(location, status = 303) {
  return new Response(null, {
    status,
    headers: { Location: location, "Cache-Control": "no-store" },
  });
}

async function readForm(request) {
  const contentType = request.headers.get("Content-Type") || "";
  if (contentType.includes("application/x-www-form-urlencoded") || contentType.includes("multipart/form-data")) {
    return request.formData();
  }
  return new FormData();
}

function appendSetCookies(headers, cookies) {
  for (const cookie of cookies) headers.append("Set-Cookie", cookie);
  return headers;
}

/**
 * Only allow same-origin redirects under /admin/. Defends against
 * open-redirect via the `next` field on the login form.
 */
function sanitiseNext(value) {
  if (typeof value !== "string") return "/admin/logs";
  if (!value.startsWith("/admin/")) return "/admin/logs";
  if (value.startsWith("//") || value.includes("\\")) return "/admin/logs";
  return value;
}

function filtersFromSearchParams(params) {
  const filters = {};
  for (const key of ["level", "source", "tenant_id", "trace_id", "q", "since_iso", "until_iso", "limit"]) {
    const v = params.get(key);
    if (v !== null && v !== "") filters[key] = v;
  }
  return filters;
}

function toQueryFilters(filters) {
  const out = { ...filters };
  if (filters.since_iso) {
    const ts = Date.parse(filters.since_iso);
    if (Number.isFinite(ts)) out.since = ts;
    delete out.since_iso;
  }
  if (filters.until_iso) {
    const ts = Date.parse(filters.until_iso);
    if (Number.isFinite(ts)) out.until = ts;
    delete out.until_iso;
  }
  return out;
}

function escapeHtmlString(s) {
  return String(s ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function timingSafeEquals(a, b) {
  const enc = new TextEncoder();
  const ab = enc.encode(a);
  const bb = enc.encode(b);
  let diff = ab.length === bb.length ? 0 : 1;
  const len = Math.max(ab.length, bb.length);
  for (let i = 0; i < len; i++) diff |= (ab[i] || 0) ^ (bb[i] || 0);
  return diff === 0;
}
