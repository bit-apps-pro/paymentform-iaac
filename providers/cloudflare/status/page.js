/**
 * page.js — HTML status page renderer
 */

function escapeHtml(str) {
  return String(str || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

export function statusColor(s) {
  return s === "ok" ? "#22c55e" : s === "degraded" ? "#f59e0b" : "#ef4444";
}

export function statusLabel(s) {
  return s === "ok" ? "Operational" : s === "degraded" ? "Degraded" : "Down";
}

function severityColor(sev) {
  return sev === "minor" ? "#f59e0b" : sev === "major" ? "#ef4444" : "#7f1d1d";
}

/**
 * Build the chart's day window.
 *
 * Auto-windows from the earliest day with stored data to today, so the
 * chart never opens with 85 grey "No data" cells when daily-snapshot
 * collection has just started. Falls back to a 14-day window when no
 * history exists at all (fresh install / cron not yet run). Capped at 90.
 */
function buildDayWindow(history, today) {
  const allDataDates = Object.keys(history).sort();
  const todayStr = today.toISOString().slice(0, 10);
  const baseDate = allDataDates.length > 0 ? allDataDates[0] : todayStr;

  const start = new Date(baseDate + "T00:00:00Z");
  const end = new Date(today);
  end.setUTCHours(0, 0, 0, 0);

  let days = Math.floor((end.getTime() - start.getTime()) / (24 * 60 * 60 * 1000)) + 1;
  if (days < 14) days = 14;
  if (days > 90) days = 90;

  const dayDates = [];
  for (let i = days - 1; i >= 0; i--) {
    const d = new Date(today);
    d.setUTCDate(d.getUTCDate() - i);
    dayDates.push(d.toISOString().slice(0, 10));
  }
  return dayDates;
}

export function renderHtml({ services, overall, checkedAt, incidents = [], history = {} }) {
  const today = new Date();
  const dayDates = buildDayWindow(history, today);

  const chartRows = services
    .map((s) => {
      const dayCells = dayDates
        .map((dateStr) => {
          const dayData = history[dateStr];
          const entry = dayData && dayData.find((e) => e.name === s.name);
          const status = entry ? entry.status : "unknown";
          const color =
            status === "ok"
              ? "#22c55e"
              : status === "degraded"
                ? "#f59e0b"
                : status === "down"
                  ? "#ef4444"
                  : "var(--cell-empty)";
          const label = status === "unknown" ? "No data" : statusLabel(status);
          const dayTs = new Date(dateStr + "T00:00:00Z").getTime();
          const matchingIncidents = incidents.filter((inc) => {
            if (!inc.affectedServices || !inc.affectedServices.includes(s.name)) return false;
            const startTs = new Date(inc.createdAt).setUTCHours(0, 0, 0, 0);
            const endTs = inc.resolvedAt ? new Date(inc.resolvedAt).setUTCHours(0, 0, 0, 0) : Date.now();
            return dayTs >= startTs && dayTs <= endTs;
          });
          let tip = `${dateStr}: ${label}`;
          for (const inc of matchingIncidents) {
            tip += ` | ${inc.title} (${inc.severity}, ${inc.resolvedAt ? "resolved" : "ongoing"})`;
          }
          return `<span class="day-cell" style="background:${color}" title="${escapeHtml(tip)}" aria-label="${escapeHtml(tip)}"></span>`;
        })
        .join("");

      // Uptime counts: ok=1, degraded=0.5 (partial), down=0. Days with no
      // snapshot are excluded so a freshly-monitored service doesn't show
      // an artificial 0% / 100%.
      const monitoredDays = dayDates
        .map((d) => history[d] && history[d].find((e) => e.name === s.name))
        .filter(Boolean);
      const weighted = monitoredDays.reduce((sum, entry) => {
        if (entry.status === "ok") return sum + 1;
        if (entry.status === "degraded") return sum + 0.5;
        return sum;
      }, 0);
      const uptimePct = monitoredDays.length > 0 ? ((weighted / monitoredDays.length) * 100).toFixed(2) : "—";

      return `<div class="chart-row">
        <div class="chart-label">${escapeHtml(s.name)}</div>
        <div class="chart-cells">${dayCells}</div>
        <div class="chart-uptime">${uptimePct === "—" ? "—" : uptimePct + "%"}</div>
      </div>`;
    })
    .join("");

  const activeIncidents = incidents.filter((i) => !i.resolvedAt);
  const activeIncidentsHtml =
    activeIncidents.length === 0
      ? ""
      : `
  <div class="card">
    <div class="card-header">
      <h2 class="card-title">Active incidents</h2>
    </div>
    <div class="card-body">
      ${activeIncidents
        .map(
          (inc, idx) => `
      <div class="incident${idx === activeIncidents.length - 1 ? " incident--last" : ""}">
        <div class="incident-head">
          <span class="badge" style="background:${severityColor(inc.severity)}">${escapeHtml(inc.severity)}</span>
          <h3 class="incident-title">${escapeHtml(inc.title)}</h3>
        </div>
        <p class="incident-affects">Affects: ${escapeHtml(inc.affectedServices.join(", "))}</p>
        <div class="incident-updates">
          ${(inc.updates || [])
            .slice()
            .reverse()
            .map(
              (upd) => `
          <div class="update">
            <strong>${escapeHtml(new Date(upd.at).toUTCString())}</strong> — <span class="update-status">${escapeHtml(upd.status)}</span>
            <p class="update-body">${escapeHtml(upd.body)}</p>
          </div>`,
            )
            .join("")}
        </div>
      </div>`,
        )
        .join("")}
    </div>
  </div>`;

  const resolvedRecent = incidents
    .filter((i) => i.resolvedAt && Date.now() - new Date(i.resolvedAt).getTime() < 30 * 24 * 60 * 60 * 1000)
    .sort((a, b) => new Date(b.resolvedAt).getTime() - new Date(a.resolvedAt).getTime());

  const allResolved = incidents
    .filter((i) => i.resolvedAt)
    .sort((a, b) => new Date(b.resolvedAt).getTime() - new Date(a.resolvedAt).getTime());

  const incidentsJson = JSON.stringify(allResolved).replace(/</g, "\\u003c").replace(/>/g, "\\u003e");

  const recentHistoryHtml = `
  <div class="card">
    <details class="history-details">
      <summary class="card-header">
        <span class="card-title">Recent history</span>
      </summary>
      <div class="card-body">
        <div id="resolved-list">
          ${resolvedRecent
            .map(
              (inc, idx) => `
          <div class="incident-resolved${idx === resolvedRecent.length - 1 ? " incident-resolved--last" : ""}">
            <strong>${escapeHtml(inc.title)}</strong> — <span class="incident-resolved-severity">${escapeHtml(inc.severity)}</span>
            <p class="incident-resolved-meta">Resolved: ${escapeHtml(new Date(inc.resolvedAt).toUTCString())}</p>
          </div>`,
            )
            .join("")}
        </div>
        ${allResolved.length > resolvedRecent.length ? `<button id="show-all" class="show-all-btn">View all (last 90 days)</button>` : ""}
      </div>
    </details>
  </div>

  <script type="application/json" id="incidents-data">${incidentsJson}</script>
  <script>
    const showAllBtn = document.getElementById("show-all");
    const resolvedList = document.getElementById("resolved-list");
    if (showAllBtn) {
      showAllBtn.addEventListener("click", () => {
        const data = JSON.parse(document.getElementById("incidents-data").textContent);
        resolvedList.innerHTML = "";
        data.forEach((inc, idx) => {
          const div = document.createElement("div");
          div.className = "incident-resolved" + (idx === data.length - 1 ? " incident-resolved--last" : "");
          const strong = document.createElement("strong");
          strong.textContent = inc.title;
          div.appendChild(strong);
          div.appendChild(document.createTextNode(" — "));
          const span = document.createElement("span");
          span.className = "incident-resolved-severity";
          span.textContent = inc.severity;
          div.appendChild(span);
          const p = document.createElement("p");
          p.className = "incident-resolved-meta";
          p.textContent = "Resolved: " + new Date(inc.resolvedAt).toUTCString();
          div.appendChild(p);
          resolvedList.appendChild(div);
        });
        showAllBtn.remove();
      });
    }
  </script>`;

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width,initial-scale=1"/>
  <title>Paymentform Status</title>
  <style>
    :root {
      --bg-page: #f9fafb;
      --bg-card: #fff;
      --bg-alt: #f9fafb;
      --text-primary: #111827;
      --text-secondary: #6b7280;
      --text-muted: #9ca3af;
      --border-color: #e5e7eb;
      --cell-empty: #d1d5db;
    }
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: system-ui, sans-serif;
      background: var(--bg-page);
      color: var(--text-primary);
      padding: 2rem 1rem;
    }
    header {
      max-width: 760px;
      margin: 0 auto 1.5rem;
      display: flex;
      align-items: center;
      gap: 1rem;
    }
    header h1 { font-size: 1.5rem; font-weight: 700; }
    .overall {
      display: inline-flex;
      align-items: center;
      gap: .5rem;
      padding: .4rem .9rem;
      border-radius: 9999px;
      font-weight: 600;
      font-size: .9rem;
      background: ${statusColor(overall)}22;
      color: ${statusColor(overall)};
      border: 1px solid ${statusColor(overall)}44;
    }

    .card {
      max-width: 760px;
      margin: 1.5rem auto 0;
      background: var(--bg-card);
      border: 1px solid var(--border-color);
      border-radius: .75rem;
      overflow: hidden;
      box-shadow: 0 1px 3px rgba(0, 0, 0, 0.05);
    }
    .card-header {
      padding: 1.25rem;
      border-bottom: 1px solid var(--border-color);
    }
    .card-title {
      font-size: 1.1rem;
      font-weight: 700;
      display: block;
    }
    .card-subtitle {
      margin-top: 0.5rem;
    }
    .card-body { padding: 1.25rem; }

    .badge {
      display: inline-block;
      padding: .2rem .6rem;
      border-radius: 9999px;
      color: #fff;
      font-size: .8rem;
      font-weight: 600;
      text-transform: capitalize;
    }

    .chart-row {
      display: flex;
      align-items: center;
      gap: 0.75rem;
      margin-bottom: 0.5rem;
    }
    .chart-row:last-child { margin-bottom: 0; }
    .chart-label {
      width: 140px;
      font-size: .85rem;
      font-weight: 600;
      flex-shrink: 0;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
    .chart-cells { display: flex; gap: 2px; flex: 1; flex-wrap: nowrap; }
    .day-cell {
      width: 8px;
      height: 28px;
      border-radius: 2px;
      display: inline-block;
      flex-shrink: 0;
    }
    .chart-uptime {
      width: 60px;
      text-align: right;
      font-size: .8rem;
      color: var(--text-secondary);
      flex-shrink: 0;
    }
    .chart-legend {
      display: flex;
      gap: 1rem;
      font-size: .8rem;
      color: var(--text-secondary);
      flex-wrap: wrap;
    }
    .legend-item { display: inline-flex; align-items: center; gap: 0.3rem; }
    .legend-item .day-cell { width: 12px; height: 12px; }

    .incident { padding-bottom: 1.5rem; margin-bottom: 1.5rem; border-bottom: 1px solid var(--border-color); }
    .incident--last { padding-bottom: 0; margin-bottom: 0; border-bottom: none; }
    .incident-head {
      display: flex;
      gap: 1rem;
      align-items: flex-start;
      margin-bottom: 0.75rem;
    }
    .incident-title { font-size: 1rem; font-weight: 600; flex: 1; margin-top: 0.2rem; }
    .incident-affects {
      font-size: 0.9rem;
      color: var(--text-secondary);
      margin: 0.5rem 0 1rem 0;
    }
    .incident-updates {
      background: var(--bg-alt);
      border-radius: 0.5rem;
      padding: 0.75rem;
      font-size: 0.85rem;
    }
    .update { margin-bottom: 0.5rem; }
    .update:last-child { margin-bottom: 0; }
    .update-status { text-transform: capitalize; color: var(--text-secondary); }
    .update-body { margin-top: 0.25rem; color: var(--text-secondary); }

    .incident-resolved {
      padding-bottom: 1rem;
      margin-bottom: 1rem;
      border-bottom: 1px solid var(--border-color);
      font-size: 0.9rem;
    }
    .incident-resolved--last { padding-bottom: 0; margin-bottom: 0; border-bottom: none; }
    .incident-resolved-severity { text-transform: capitalize; color: var(--text-secondary); }
    .incident-resolved-meta { margin-top: 0.25rem; color: var(--text-secondary); }

    .history-details { cursor: pointer; }
    .history-details > summary {
      display: block;
      cursor: pointer;
      user-select: none;
      outline: none;
    }
    .history-details[open] > summary { border-bottom: 1px solid var(--border-color); }
    details > summary::-webkit-details-marker { display: none; }

    .show-all-btn {
      margin-top: 1rem;
      padding: 0.5rem 1rem;
      font-size: 0.9rem;
      border: 1px solid var(--border-color);
      background: var(--bg-alt);
      color: inherit;
      border-radius: 0.5rem;
      cursor: pointer;
    }

    footer {
      max-width: 760px;
      margin: 1.5rem auto 0;
      text-align: right;
      font-size: .8rem;
      color: var(--text-muted);
    }

    @media (prefers-color-scheme: dark) {
      :root {
        --bg-page: #111827;
        --bg-card: #1f2937;
        --bg-alt: #111827;
        --text-primary: #f9fafb;
        --text-secondary: #9ca3af;
        --text-muted: #6b7280;
        --border-color: #374151;
        --cell-empty: #4b5563;
      }
    }
  </style>
</head>
<body>
  <header>
    <h1>Paymentform Status</h1>
    <span class="overall">${statusLabel(overall)}</span>
  </header>
  <div class="card">
    <div class="card-header">
      <h2 class="card-title">Service Status — Last ${dayDates.length} Days</h2>
      <div class="chart-legend card-subtitle">
        <span class="legend-item"><span class="day-cell" style="background:#22c55e"></span> Operational</span>
        <span class="legend-item"><span class="day-cell" style="background:#f59e0b"></span> Degraded</span>
        <span class="legend-item"><span class="day-cell" style="background:#ef4444"></span> Down</span>
        <span class="legend-item"><span class="day-cell" style="background:var(--cell-empty)"></span> No data</span>
      </div>
    </div>
    <div class="card-body">
      ${chartRows}
    </div>
  </div>
  ${activeIncidentsHtml}
  ${recentHistoryHtml}
  <footer>Last checked: ${escapeHtml(checkedAt)} &nbsp;·&nbsp; Auto-refreshes every 5 min</footer>
  <script>setTimeout(() => location.reload(), 300000);</script>
</body>
</html>`;
}
