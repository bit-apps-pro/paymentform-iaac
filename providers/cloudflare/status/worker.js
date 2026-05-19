import { checkService, overallStatus } from "./health.js";
import { renderHtml } from "./page.js";
import { renderAtom } from "./feed.js";
import { listIncidents, createIncident, appendUpdate, runAutoDetection, pruneOldIncidents } from "./incidents.js";
import { requireBearer } from "./auth.js";

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
  try {
    return JSON.parse(env.SERVICES_JSON);
  } catch {
    return [];
  }
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

    return new Response("Not Found", { status: 404 });
  },
};
