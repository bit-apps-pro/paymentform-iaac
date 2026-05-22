/**
 * admin.js — HTML renderers for the /admin/* surface.
 *
 * All renderers return a complete HTML document string. Shared styles are
 * inlined once (small page count, no asset pipeline). Visual conventions
 * mirror page.js (CSS variables, card layout, dark mode).
 *
 * Each renderer takes already-validated data and emits HTML. They do not
 * touch KV / D1 directly — the worker is the I/O boundary.
 */

const LEVEL_COLORS = {
  debug: "#6b7280",
  info: "#3b82f6",
  notice: "#3b82f6",
  warning: "#f59e0b",
  error: "#ef4444",
  critical: "#dc2626",
  alert: "#dc2626",
  emergency: "#991b1b",
};

function escapeHtml(s) {
  return String(s ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function htmlShell({ title, body, extraHead = "" }) {
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width,initial-scale=1" />
  <title>${escapeHtml(title)}</title>
  <style>${baseStyles()}</style>
  ${extraHead}
</head>
<body>
  ${body}
</body>
</html>`;
}

function baseStyles() {
  return `
  :root {
    --bg-page: #f9fafb;
    --bg-card: #fff;
    --bg-alt: #f3f4f6;
    --bg-input: #fff;
    --text-primary: #111827;
    --text-secondary: #6b7280;
    --text-muted: #9ca3af;
    --border-color: #e5e7eb;
    --accent: #2563eb;
    --danger: #ef4444;
  }
  @media (prefers-color-scheme: dark) {
    :root {
      --bg-page: #111827;
      --bg-card: #1f2937;
      --bg-alt: #111827;
      --bg-input: #0f172a;
      --text-primary: #f9fafb;
      --text-secondary: #9ca3af;
      --text-muted: #6b7280;
      --border-color: #374151;
      --accent: #3b82f6;
    }
  }
  *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
  body {
    font-family: system-ui, sans-serif;
    background: var(--bg-page);
    color: var(--text-primary);
    padding: 2rem 1rem;
    line-height: 1.4;
  }
  a { color: var(--accent); text-decoration: none; }
  a:hover { text-decoration: underline; }

  .container { max-width: 1280px; margin: 0 auto; }
  .container--narrow { max-width: 480px; }

  header.admin-header {
    display: flex;
    align-items: center;
    gap: 1rem;
    margin-bottom: 1.5rem;
    flex-wrap: wrap;
  }
  header.admin-header h1 { font-size: 1.4rem; font-weight: 700; flex: 1; }
  header.admin-header nav { display: flex; gap: 1rem; }
  header.admin-header nav a {
    padding: 0.4rem 0.8rem;
    border-radius: 0.5rem;
    color: var(--text-secondary);
  }
  header.admin-header nav a.active { background: var(--accent); color: #fff; }
  header.admin-header .logout-btn {
    background: transparent;
    color: var(--text-secondary);
    border: 1px solid var(--border-color);
    padding: 0.4rem 0.8rem;
    border-radius: 0.5rem;
    cursor: pointer;
    font-size: 0.85rem;
  }

  .card {
    background: var(--bg-card);
    border: 1px solid var(--border-color);
    border-radius: 0.75rem;
    overflow: hidden;
    box-shadow: 0 1px 3px rgba(0, 0, 0, 0.05);
    margin-bottom: 1.5rem;
  }
  .card-header {
    padding: 1rem 1.25rem;
    border-bottom: 1px solid var(--border-color);
    display: flex;
    align-items: center;
    gap: 1rem;
    flex-wrap: wrap;
  }
  .card-title { font-size: 1rem; font-weight: 700; flex: 1; }
  .card-body { padding: 1.25rem; }

  form.filter-form {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(160px, 1fr));
    gap: 0.75rem;
    align-items: end;
    margin-bottom: 1rem;
  }
  label {
    display: block;
    font-size: 0.75rem;
    font-weight: 600;
    color: var(--text-secondary);
    margin-bottom: 0.25rem;
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }
  input, select, textarea {
    width: 100%;
    padding: 0.5rem 0.75rem;
    border: 1px solid var(--border-color);
    border-radius: 0.4rem;
    background: var(--bg-input);
    color: var(--text-primary);
    font-size: 0.9rem;
    font-family: inherit;
  }
  textarea { min-height: 80px; resize: vertical; }
  input:focus, select:focus, textarea:focus {
    outline: 2px solid var(--accent);
    outline-offset: -1px;
  }

  button, .btn {
    padding: 0.5rem 1rem;
    border: 1px solid var(--border-color);
    background: var(--bg-alt);
    color: var(--text-primary);
    border-radius: 0.4rem;
    cursor: pointer;
    font-size: 0.85rem;
    font-family: inherit;
  }
  button.primary, .btn.primary {
    background: var(--accent);
    border-color: var(--accent);
    color: #fff;
  }
  button.danger, .btn.danger {
    background: transparent;
    border-color: var(--danger);
    color: var(--danger);
  }
  button.danger:hover, .btn.danger:hover { background: var(--danger); color: #fff; }
  button:disabled { opacity: 0.5; cursor: not-allowed; }

  table.logs-table {
    width: 100%;
    border-collapse: collapse;
    font-size: 0.85rem;
  }
  table.logs-table th, table.logs-table td {
    padding: 0.6rem 0.75rem;
    text-align: left;
    border-bottom: 1px solid var(--border-color);
    vertical-align: top;
  }
  table.logs-table th {
    background: var(--bg-alt);
    font-weight: 600;
    color: var(--text-secondary);
    font-size: 0.75rem;
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }
  table.logs-table tr:last-child td { border-bottom: none; }
  table.logs-table .col-ts { width: 160px; white-space: nowrap; }
  table.logs-table .col-level { width: 90px; }
  table.logs-table .col-source { width: 110px; white-space: nowrap; }
  table.logs-table .col-tenant { width: 140px; white-space: nowrap; font-family: ui-monospace, monospace; font-size: 0.75rem; }
  table.logs-table .col-actions { width: 140px; text-align: right; white-space: nowrap; }
  table.logs-table .msg-link { color: var(--text-primary); text-decoration: none; word-break: break-word; }
  table.logs-table .msg-link:hover { color: var(--accent); text-decoration: underline; }
  table.logs-table .msg-truncated { color: var(--text-muted); }
  table.logs-table .row-trace { font-family: ui-monospace, monospace; font-size: 0.7rem; color: var(--text-muted); margin-top: 0.3rem; }

  .detail-grid {
    display: grid;
    grid-template-columns: 140px 1fr;
    gap: 0.5rem 1rem;
    font-size: 0.9rem;
  }
  .detail-grid dt {
    font-weight: 600;
    color: var(--text-secondary);
    text-transform: uppercase;
    font-size: 0.75rem;
    letter-spacing: 0.05em;
    padding-top: 0.2rem;
  }
  .detail-grid dd { word-break: break-word; }
  .detail-message {
    background: var(--bg-alt);
    border-radius: 0.4rem;
    padding: 0.75rem;
    font-family: ui-monospace, monospace;
    font-size: 0.85rem;
    white-space: pre-wrap;
    word-break: break-word;
  }
  .detail-context {
    background: var(--bg-alt);
    border-radius: 0.4rem;
    padding: 0.75rem;
    font-family: ui-monospace, monospace;
    font-size: 0.8rem;
    white-space: pre-wrap;
    word-break: break-word;
    max-height: 500px;
    overflow: auto;
  }
  table.logs-table .msg { word-break: break-word; }
  table.logs-table .ctx {
    margin-top: 0.4rem;
    padding: 0.5rem;
    background: var(--bg-alt);
    border-radius: 0.3rem;
    font-family: ui-monospace, monospace;
    font-size: 0.75rem;
    color: var(--text-secondary);
    white-space: pre-wrap;
    word-break: break-word;
    max-height: 200px;
    overflow: auto;
  }

  .level-badge {
    display: inline-block;
    padding: 0.15rem 0.5rem;
    border-radius: 0.3rem;
    color: #fff;
    font-size: 0.7rem;
    font-weight: 600;
    text-transform: uppercase;
  }

  .pagination {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-top: 1rem;
    color: var(--text-secondary);
    font-size: 0.85rem;
  }
  .pagination a, .pagination span { padding: 0.4rem 0.8rem; }

  .incident-item {
    border: 1px solid var(--border-color);
    border-radius: 0.5rem;
    padding: 1rem;
    margin-bottom: 1rem;
  }
  .incident-item:last-child { margin-bottom: 0; }
  .incident-head { display: flex; gap: 0.75rem; align-items: center; flex-wrap: wrap; }
  .incident-head h3 { font-size: 1rem; font-weight: 600; flex: 1; }
  .severity-badge {
    display: inline-block;
    padding: 0.15rem 0.5rem;
    border-radius: 0.3rem;
    color: #fff;
    font-size: 0.7rem;
    font-weight: 600;
    text-transform: uppercase;
  }
  .incident-meta { color: var(--text-secondary); font-size: 0.8rem; margin-top: 0.4rem; }
  .incident-updates {
    margin-top: 0.75rem;
    padding: 0.6rem;
    background: var(--bg-alt);
    border-radius: 0.4rem;
    font-size: 0.85rem;
  }
  .incident-update { margin-bottom: 0.5rem; }
  .incident-update:last-child { margin-bottom: 0; }
  .incident-actions {
    display: flex;
    gap: 0.5rem;
    margin-top: 0.75rem;
    flex-wrap: wrap;
  }
  .inline-form {
    display: flex;
    gap: 0.5rem;
    margin-top: 0.5rem;
    align-items: center;
    flex-wrap: wrap;
  }
  .inline-form input { flex: 1; min-width: 200px; }

  .flash {
    padding: 0.75rem 1rem;
    border-radius: 0.4rem;
    margin-bottom: 1rem;
    font-size: 0.9rem;
  }
  .flash--ok { background: rgba(34, 197, 94, 0.15); color: #22c55e; }
  .flash--err { background: rgba(239, 68, 68, 0.15); color: var(--danger); }
  `;
}

function severityColor(sev) {
  return sev === "minor" ? "#f59e0b" : sev === "major" ? "#ef4444" : "#7f1d1d";
}

function navHtml(current) {
  return `<nav>
    <a href="/admin/logs" class="${current === "logs" ? "active" : ""}">Logs</a>
    <a href="/admin/incidents" class="${current === "incidents" ? "active" : ""}">Incidents</a>
    <a href="/" target="_blank">Status</a>
  </nav>`;
}

function logoutFormHtml(csrf) {
  return `<form method="POST" action="/admin/logout" style="display:inline;">
    <input type="hidden" name="csrf" value="${escapeHtml(csrf)}" />
    <button type="submit" class="logout-btn">Logout</button>
  </form>`;
}

function pageHeader({ title, current, csrf }) {
  return `<header class="admin-header">
    <h1>${escapeHtml(title)}</h1>
    ${navHtml(current)}
    ${logoutFormHtml(csrf)}
  </header>`;
}

function flash(flashType, message) {
  if (!message) return "";
  const cls = flashType === "err" ? "flash--err" : "flash--ok";
  return `<div class="flash ${cls}">${escapeHtml(message)}</div>`;
}

// ─────────────────────────────────────────────────────────────────────────
//  Login
// ─────────────────────────────────────────────────────────────────────────

export function renderLogin({ next = "/admin/logs", error = "" } = {}) {
  const body = `
  <div class="container container--narrow">
    <header class="admin-header"><h1>Admin sign-in</h1></header>
    <div class="card">
      <div class="card-body">
        ${flash("err", error)}
        <form method="POST" action="/admin/login">
          <input type="hidden" name="next" value="${escapeHtml(next)}" />
          <div style="margin-bottom: 1rem;">
            <label for="token">Admin token</label>
            <input type="password" id="token" name="token" autocomplete="current-password" autofocus required />
          </div>
          <button type="submit" class="primary" style="width: 100%;">Sign in</button>
        </form>
      </div>
    </div>
  </div>`;
  return htmlShell({ title: "Admin sign-in — Paymentform Status", body });
}

// ─────────────────────────────────────────────────────────────────────────
//  Logs
// ─────────────────────────────────────────────────────────────────────────

export function renderLogs({ rows, filters, csrf, flash: flashMsg = "" }) {
  const filterValue = (key, dflt = "") => escapeHtml(filters[key] ?? dflt);
  const tableRows = rows.map((row) => renderLogRow(row, csrf, filters)).join("");

  const olderHref = buildPaginationHref(filters, rows, "older");
  const newerHref = buildPaginationHref(filters, rows, "newer");

  const body = `
  <div class="container">
    ${pageHeader({ title: "Logs", current: "logs", csrf })}
    ${flash("ok", flashMsg)}

    <div class="card">
      <div class="card-header"><span class="card-title">Filters</span></div>
      <div class="card-body">
        <form class="filter-form" method="GET" action="/admin/logs">
          <div>
            <label for="f-level">Level</label>
            <select id="f-level" name="level">
              <option value="">All</option>
              ${["debug", "info", "notice", "warning", "error", "critical", "alert", "emergency"]
                .map(
                  (lv) =>
                    `<option value="${lv}" ${filters.level === lv ? "selected" : ""}>${lv}</option>`,
                )
                .join("")}
            </select>
          </div>
          <div>
            <label for="f-source">Source</label>
            <input id="f-source" name="source" value="${filterValue("source")}" placeholder="backend, renderer..." />
          </div>
          <div>
            <label for="f-tenant">Tenant ID</label>
            <input id="f-tenant" name="tenant_id" value="${filterValue("tenant_id")}" />
          </div>
          <div>
            <label for="f-trace">Trace ID</label>
            <input id="f-trace" name="trace_id" value="${filterValue("trace_id")}" />
          </div>
          <div style="grid-column: 1 / -1;">
            <label for="f-q">Search (message contains)</label>
            <input id="f-q" name="q" value="${filterValue("q")}" />
          </div>
          <div>
            <label for="f-since">Since (UTC)</label>
            <input id="f-since" name="since_iso" value="${filterValue("since_iso")}" placeholder="2026-05-20T00:00" type="datetime-local" />
          </div>
          <div>
            <label for="f-until">Until (UTC)</label>
            <input id="f-until" name="until_iso" value="${filterValue("until_iso")}" placeholder="2026-05-22T00:00" type="datetime-local" />
          </div>
          <div>
            <label for="f-limit">Limit</label>
            <input id="f-limit" name="limit" value="${filterValue("limit", "100")}" type="number" min="1" max="500" />
          </div>
          <div>
            <button type="submit" class="primary">Apply</button>
            <a href="/admin/logs" class="btn" style="margin-left:0.5rem;">Reset</a>
          </div>
        </form>
      </div>
    </div>

    <div class="card">
      <div class="card-header">
        <span class="card-title">${rows.length} row${rows.length === 1 ? "" : "s"}</span>
        <form method="POST" action="/admin/logs/purge" class="inline-form" onsubmit="return confirm('Delete logs older than this date?');">
          <input type="hidden" name="csrf" value="${escapeHtml(csrf)}" />
          <input type="datetime-local" name="before_iso" required />
          <button type="submit" class="danger">Purge before</button>
        </form>
      </div>
      <div class="card-body" style="overflow-x:auto;">
        ${rows.length === 0
          ? '<p style="color: var(--text-secondary);">No rows match.</p>'
          : `<table class="logs-table">
            <thead>
              <tr>
                <th class="col-ts">Time (UTC)</th>
                <th class="col-level">Level</th>
                <th class="col-source">Source</th>
                <th>Message</th>
                <th class="col-tenant">Tenant</th>
                <th class="col-actions"></th>
              </tr>
            </thead>
            <tbody>${tableRows}</tbody>
          </table>`}
      </div>
      <div class="card-body" style="border-top: 1px solid var(--border-color); padding-top: 0.75rem;">
        <div class="pagination">
          <a href="${escapeHtml(newerHref)}">&larr; Newer</a>
          <span>showing ${rows.length}</span>
          <a href="${escapeHtml(olderHref)}">Older &rarr;</a>
        </div>
      </div>
    </div>
  </div>`;

  return htmlShell({ title: "Logs — Paymentform Status Admin", body });
}

function renderLogRow(row, csrf, filters) {
  const levelColor = LEVEL_COLORS[row.level] || "#6b7280";
  const tsIso = new Date(row.ts).toISOString().replace("T", " ").slice(0, 19);
  const tenantSnippet = row.tenant_id ? escapeHtml(row.tenant_id) : '<span style="color:var(--text-muted)">—</span>';
  const shortMessage = truncate(row.message, 140);
  const detailUrl = `/admin/logs/${row.id}`;

  return `<tr>
    <td class="col-ts">${escapeHtml(tsIso)}</td>
    <td class="col-level"><span class="level-badge" style="background:${levelColor}">${escapeHtml(row.level)}</span></td>
    <td class="col-source">${escapeHtml(row.source)}</td>
    <td class="msg">
      <a href="${detailUrl}" class="msg-link">${escapeHtml(shortMessage)}</a>
      ${row.message.length > 140 ? `<span class="msg-truncated"> &hellip;</span>` : ""}
      ${row.trace_id ? `<div class="row-trace">trace ${escapeHtml(row.trace_id)}</div>` : ""}
    </td>
    <td class="col-tenant">${tenantSnippet}</td>
    <td class="col-actions">
      <a href="${detailUrl}" class="btn" style="margin-right:0.25rem;">View</a>
      <form method="POST" action="/admin/logs/delete" style="display:inline;" onsubmit="return confirm('Delete row ${row.id}?');">
        <input type="hidden" name="csrf" value="${escapeHtml(csrf)}" />
        <input type="hidden" name="id" value="${row.id}" />
        <input type="hidden" name="next" value="${escapeHtml(reconstructFilterUrl(filters))}" />
        <button type="submit" class="danger">Delete</button>
      </form>
    </td>
  </tr>`;
}

function truncate(str, max) {
  const s = String(str ?? "");
  return s.length <= max ? s : s.slice(0, max).trimEnd();
}

function formatContextForDisplay(value) {
  if (value === null || value === undefined) return "";
  if (typeof value === "string") {
    try { return JSON.stringify(JSON.parse(value), null, 2); } catch { return value; }
  }
  return JSON.stringify(value, null, 2);
}

function reconstructFilterUrl(filters) {
  const params = new URLSearchParams();
  for (const [k, v] of Object.entries(filters)) {
    if (v !== undefined && v !== null && v !== "") params.set(k, String(v));
  }
  const qs = params.toString();
  return "/admin/logs" + (qs ? "?" + qs : "");
}

function buildPaginationHref(filters, rows, direction) {
  const params = new URLSearchParams();
  for (const [k, v] of Object.entries(filters)) {
    if (v !== undefined && v !== null && v !== "" && k !== "since_iso" && k !== "until_iso") {
      params.set(k, String(v));
    }
  }

  if (rows.length === 0) {
    if (filters.since_iso) params.set("since_iso", filters.since_iso);
    if (filters.until_iso) params.set("until_iso", filters.until_iso);
    return "/admin/logs?" + params.toString();
  }

  if (direction === "older") {
    const oldestTs = rows[rows.length - 1].ts;
    params.set("until_iso", new Date(oldestTs - 1).toISOString().slice(0, 16));
  } else {
    const newestTs = rows[0].ts;
    params.set("since_iso", new Date(newestTs + 1).toISOString().slice(0, 16));
  }
  return "/admin/logs?" + params.toString();
}

// ─────────────────────────────────────────────────────────────────────────
//  Incidents
// ─────────────────────────────────────────────────────────────────────────

export function renderIncidents({ incidents, csrf, flash: flashMsg = "" }) {
  const open = incidents.filter((i) => !i.resolvedAt);
  const resolved = incidents.filter((i) => i.resolvedAt).slice(0, 20);

  const body = `
  <div class="container">
    ${pageHeader({ title: "Incidents", current: "incidents", csrf })}
    ${flash("ok", flashMsg)}

    <div class="card">
      <div class="card-header"><span class="card-title">Create incident</span></div>
      <div class="card-body">
        <form method="POST" action="/admin/incidents/create">
          <input type="hidden" name="csrf" value="${escapeHtml(csrf)}" />
          <div style="display:grid;grid-template-columns:2fr 1fr;gap:0.75rem;margin-bottom:0.75rem;">
            <div>
              <label for="i-title">Title</label>
              <input id="i-title" name="title" required />
            </div>
            <div>
              <label for="i-severity">Severity</label>
              <select id="i-severity" name="severity">
                <option value="minor">Minor</option>
                <option value="major">Major</option>
                <option value="critical">Critical</option>
              </select>
            </div>
          </div>
          <div style="margin-bottom:0.75rem;">
            <label for="i-services">Affected services (comma-separated)</label>
            <input id="i-services" name="affectedServices" placeholder="API (Backend), Renderer" required />
          </div>
          <div style="margin-bottom:0.75rem;">
            <label for="i-body">Initial update</label>
            <textarea id="i-body" name="body" placeholder="What's happening?" required></textarea>
          </div>
          <button type="submit" class="primary">Create incident</button>
        </form>
      </div>
    </div>

    <div class="card">
      <div class="card-header"><span class="card-title">Open (${open.length})</span></div>
      <div class="card-body">
        ${open.length === 0 ? '<p style="color:var(--text-secondary);">None open.</p>' : open.map((inc) => renderIncidentItem(inc, csrf, false)).join("")}
      </div>
    </div>

    <div class="card">
      <div class="card-header"><span class="card-title">Recently resolved</span></div>
      <div class="card-body">
        ${resolved.length === 0 ? '<p style="color:var(--text-secondary);">Nothing resolved recently.</p>' : resolved.map((inc) => renderIncidentItem(inc, csrf, true)).join("")}
      </div>
    </div>
  </div>`;

  return htmlShell({ title: "Incidents — Paymentform Status Admin", body });
}

function renderIncidentItem(inc, csrf, isResolved) {
  const sevColor = severityColor(inc.severity);
  const updatesHtml = (inc.updates || [])
    .slice()
    .reverse()
    .map(
      (upd) => `<div class="incident-update">
        <strong>${escapeHtml(new Date(upd.at).toUTCString())}</strong>
        ${upd.status ? ` — <span style="text-transform:capitalize;color:var(--text-secondary);">${escapeHtml(upd.status)}</span>` : ""}
        <div style="color:var(--text-secondary);margin-top:0.2rem;">${escapeHtml(upd.body || "")}</div>
      </div>`,
    )
    .join("");

  return `<div class="incident-item">
    <div class="incident-head">
      <span class="severity-badge" style="background:${sevColor}">${escapeHtml(inc.severity)}</span>
      <h3>${escapeHtml(inc.title)}</h3>
      <code style="font-size:0.75rem;color:var(--text-muted);">${escapeHtml(inc.id)}</code>
    </div>
    <div class="incident-meta">
      Affects ${escapeHtml((inc.affectedServices || []).join(", "))}
      &middot; created ${escapeHtml(new Date(inc.createdAt).toUTCString())}
      ${inc.resolvedAt ? "&middot; resolved " + escapeHtml(new Date(inc.resolvedAt).toUTCString()) : ""}
      &middot; source ${escapeHtml(inc.source || "manual")}
    </div>
    <div class="incident-updates">${updatesHtml || '<span style="color:var(--text-muted);">No updates.</span>'}</div>
    ${isResolved ? "" : renderIncidentActions(inc, csrf)}
  </div>`;
}

function renderIncidentActions(inc, csrf) {
  return `<div class="incident-actions">
    <form method="POST" action="/admin/incidents/${escapeHtml(inc.id)}/update" class="inline-form" style="flex:1;min-width:240px;">
      <input type="hidden" name="csrf" value="${escapeHtml(csrf)}" />
      <select name="status">
        <option value="">(no status change)</option>
        <option value="investigating">investigating</option>
        <option value="identified">identified</option>
        <option value="monitoring">monitoring</option>
      </select>
      <input name="body" placeholder="Update note" required />
      <button type="submit">Append</button>
    </form>
    <form method="POST" action="/admin/incidents/${escapeHtml(inc.id)}/resolve" onsubmit="return confirm('Resolve incident ${escapeHtml(inc.id)}?');">
      <input type="hidden" name="csrf" value="${escapeHtml(csrf)}" />
      <input type="hidden" name="body" value="Resolved by support." />
      <button type="submit" class="danger">Resolve</button>
    </form>
  </div>`;
}

// ─────────────────────────────────────────────────────────────────────────
//  Log detail
// ─────────────────────────────────────────────────────────────────────────

export function renderLogDetail({ row, csrf, backHref = "/admin/logs" }) {
  const levelColor = LEVEL_COLORS[row.level] || "#6b7280";
  const tsIso = new Date(row.ts).toISOString();
  const expiresIso = new Date(row.expires_at).toISOString();
  const contextStr = formatContextForDisplay(row.context ?? row.context_json);

  const fieldRows = [
    ["ID", String(row.id)],
    ["Time (UTC)", tsIso],
    ["Level", `<span class="level-badge" style="background:${levelColor}">${escapeHtml(row.level)}</span>`, true],
    ["Source", escapeHtml(row.source), true],
    ["Tenant", row.tenant_id ? escapeHtml(row.tenant_id) : '<span style="color:var(--text-muted)">—</span>', true],
    ["Trace ID", row.trace_id ? `<code>${escapeHtml(row.trace_id)}</code>` : '<span style="color:var(--text-muted)">—</span>', true],
    ["Retention", `${row.retention_days} day${row.retention_days === 1 ? "" : "s"} (expires ${expiresIso})`],
  ]
    .map(([label, value, isHtml]) => `<dt>${escapeHtml(label)}</dt><dd>${isHtml ? value : escapeHtml(value)}</dd>`)
    .join("");

  const body = `
  <div class="container">
    ${pageHeader({ title: `Log #${row.id}`, current: "logs", csrf })}

    <div style="margin-bottom: 1rem;">
      <a href="${escapeHtml(backHref)}" class="btn">&larr; Back to logs</a>
    </div>

    <div class="card">
      <div class="card-header"><span class="card-title">Metadata</span></div>
      <div class="card-body">
        <dl class="detail-grid">${fieldRows}</dl>
      </div>
    </div>

    <div class="card">
      <div class="card-header"><span class="card-title">Message</span></div>
      <div class="card-body">
        <div class="detail-message">${escapeHtml(row.message)}</div>
      </div>
    </div>

    ${
      contextStr
        ? `<div class="card">
        <div class="card-header"><span class="card-title">Context</span></div>
        <div class="card-body">
          <pre class="detail-context">${escapeHtml(contextStr)}</pre>
        </div>
      </div>`
        : ""
    }

    <div class="card">
      <div class="card-header"><span class="card-title">Actions</span></div>
      <div class="card-body" style="display:flex;gap:0.5rem;">
        <form method="POST" action="/admin/logs/delete" onsubmit="return confirm('Delete log #${row.id}?');">
          <input type="hidden" name="csrf" value="${escapeHtml(csrf)}" />
          <input type="hidden" name="id" value="${row.id}" />
          <input type="hidden" name="next" value="${escapeHtml(backHref)}" />
          <button type="submit" class="danger">Delete this log</button>
        </form>
      </div>
    </div>
  </div>`;

  return htmlShell({ title: `Log #${row.id} — Paymentform Status Admin`, body });
}
