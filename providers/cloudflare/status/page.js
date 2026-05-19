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

export function renderHtml({ services, overall, checkedAt, incidents = [], history = {} }) {
  const today = new Date();
  const dayDates = [];
  for (let i = 89; i >= 0; i--) {
    const d = new Date(today);
    d.setUTCDate(d.getUTCDate() - i);
    dayDates.push(d.toISOString().slice(0, 10));
  }

  const chartRows = services
    .map((s) => {
      const dayCells = dayDates
        .map((dateStr) => {
          const dayData = history[dateStr];
          const entry = dayData && dayData.find((e) => e.name === s.name);
          const status = entry ? entry.status : "unknown";
          const color =
            status === "ok" ? "#22c55e" : status === "degraded" ? "#f59e0b" : status === "down" ? "#ef4444" : "#374151";
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

      const availableDays = dayDates.filter((d) => {
        const dayData = history[d];
        return dayData && dayData.find((e) => e.name === s.name);
      });
      const okDays = availableDays.filter((d) => {
        const entry = history[d].find((e) => e.name === s.name);
        return entry.status === "ok";
      }).length;
      const uptimePct = availableDays.length > 0 ? ((okDays / availableDays.length) * 100).toFixed(2) : "—";

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
    <div style="padding: 1.25rem; border-bottom: 1px solid var(--border-color);">
      <h2 style="font-size: 1.1rem; font-weight: 700; margin-bottom: 1rem;">Active incidents</h2>
      ${activeIncidents
        .map(
          (inc) => `
      <div style="margin-bottom: 1.5rem; padding-bottom: 1.5rem; border-bottom: 1px solid var(--border-color);">
        <div style="display: flex; gap: 1rem; align-items: flex-start; margin-bottom: 0.75rem;">
          <span class="badge" style="background: ${severityColor(inc.severity)}; color: #fff; text-transform: capitalize;">${escapeHtml(inc.severity)}</span>
          <h3 style="font-size: 1rem; font-weight: 600; flex: 1; margin: 0.2rem 0 0 0;">${escapeHtml(inc.title)}</h3>
        </div>
        <p style="font-size: 0.9rem; color: var(--text-secondary); margin: 0.5rem 0 1rem 0;">Affects: ${escapeHtml(inc.affectedServices.join(", "))}</p>
        <div style="background: var(--bg-alt); border-radius: 0.5rem; padding: 0.75rem; font-size: 0.85rem;">
          ${(inc.updates || [])
            .reverse()
            .map(
              (upd) => `
          <div style="margin-bottom: 0.5rem;">
            <strong>${new Date(upd.at).toLocaleString()}</strong> — <span style="text-transform: capitalize; color: var(--text-secondary);">${escapeHtml(upd.status)}</span>
            <p style="margin: 0.25rem 0 0 0; color: var(--text-secondary);">${escapeHtml(upd.body)}</p>
          </div>`
            )
            .join("")}
        </div>
      </div>`
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
  <div class="card" style="margin-top: 1.5rem;">
    <details style="cursor: pointer;">
      <summary style="padding: 1.25rem; font-weight: 600; font-size: 1rem; user-select: none; outline: none;">Recent history</summary>
      <div style="padding: 1.25rem; border-top: 1px solid var(--border-color);">
        <div id="resolved-list">
          ${resolvedRecent
            .map(
              (inc) => `
          <div style="margin-bottom: 1rem; padding-bottom: 1rem; border-bottom: 1px solid var(--border-color); font-size: 0.9rem;">
            <strong>${escapeHtml(inc.title)}</strong> — <span style="text-transform: capitalize; color: var(--text-secondary);">${escapeHtml(inc.severity)}</span>
            <p style="margin: 0.25rem 0 0 0; color: var(--text-secondary);">Resolved: ${new Date(inc.resolvedAt).toLocaleString()}</p>
          </div>`
            )
            .join("")}
        </div>
        ${allResolved.length > resolvedRecent.length ? `<button id="show-all" style="margin-top: 1rem; padding: 0.5rem 1rem; font-size: 0.9rem; border: 1px solid var(--border-color); background: var(--bg-alt); border-radius: 0.5rem; cursor: pointer;">View all (last 90 days)</button>` : ""}
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
        data.forEach(inc => {
          const div = document.createElement("div");
          div.style.marginBottom = "1rem";
          div.style.paddingBottom = "1rem";
          div.style.borderBottom = "1px solid var(--border-color)";
          div.style.fontSize = "0.9rem";
          const strong = document.createElement("strong");
          strong.textContent = inc.title;
          div.appendChild(strong);
          div.appendChild(document.createTextNode(" — "));
          const span = document.createElement("span");
          span.style.textTransform = "capitalize";
          span.style.color = "var(--text-secondary)";
          span.textContent = inc.severity;
          div.appendChild(span);
          const p = document.createElement("p");
          p.style.margin = "0.25rem 0 0 0";
          p.style.color = "var(--text-secondary)";
          p.textContent = "Resolved: " + new Date(inc.resolvedAt).toLocaleString();
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
    :root { --border-color: #e5e7eb; --text-secondary: #6b7280; --bg-alt: #f9fafb; }
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
    body { font-family: system-ui, sans-serif; background: #f9fafb; color: #111827; padding: 2rem 1rem; }
    header { max-width: 760px; margin: 0 auto 2rem; display: flex; align-items: center; gap: 1rem; }
    header h1 { font-size: 1.5rem; font-weight: 700; }
    .overall { display: inline-flex; align-items: center; gap: .5rem; padding: .4rem .9rem;
                border-radius: 9999px; font-weight: 600; font-size: .9rem;
                background: ${statusColor(overall)}22; color: ${statusColor(overall)}; border: 1px solid ${statusColor(overall)}44; }
    .card { max-width: 760px; margin: 1.5rem auto 0; background: #fff; border: 1px solid #e5e7eb;
             border-radius: .75rem; overflow: hidden; box-shadow: 0 1px 3px #0001; }
    table { width: 100%; border-collapse: collapse; }
    th, td { padding: .75rem 1rem; text-align: left; font-size: .9rem; }
    th { background: #f3f4f6; font-weight: 600; color: #374151; border-bottom: 1px solid #e5e7eb; }
    tr:not(:last-child) td { border-bottom: 1px solid #f3f4f6; }
    .badge { display: inline-block; padding: .2rem .6rem; border-radius: 9999px;
              color: #fff; font-size: .8rem; font-weight: 600; }
    .chart-row { display: flex; align-items: center; gap: 0.75rem; margin-bottom: 0.5rem; }
    .chart-label { width: 140px; font-size: .85rem; font-weight: 600; flex-shrink: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
    .chart-cells { display: flex; gap: 2px; flex: 1; flex-wrap: nowrap; }
    .day-cell { width: 8px; height: 28px; border-radius: 2px; display: inline-block; flex-shrink: 0; }
    .chart-uptime { width: 60px; text-align: right; font-size: .8rem; color: var(--text-secondary); flex-shrink: 0; }
    .chart-legend { display: flex; gap: 1rem; font-size: .8rem; color: var(--text-secondary); flex-wrap: wrap; }
    .legend-item { display: inline-flex; align-items: center; gap: 0.3rem; }
    .legend-item .day-cell { width: 12px; height: 12px; }
    details > summary::-webkit-details-marker { display: none; }
    details > summary { display: block; }
    footer { max-width: 760px; margin: 1.5rem auto 0; text-align: right; font-size: .8rem; color: #9ca3af; }
    @media (prefers-color-scheme: dark) {
      :root { --border-color: #374151; --text-secondary: #9ca3af; --bg-alt: #111827; }
      body { background: #111827; color: #f9fafb; }
      .card { background: #1f2937; border-color: #374151; }
      th { background: #374151; color: #d1d5db; border-color: #4b5563; }
      tr:not(:last-child) td { border-color: #374151; }
      .day-cell[title*="No data"] { background: #4b5563 !important; }
    }
  </style>
</head>
<body>
  <header>
    <h1>Paymentform Status</h1>
    <span class="overall">${statusLabel(overall)}</span>
  </header>
  <div class="card">
    <div style="padding: 1.25rem; border-bottom: 1px solid var(--border-color);">
      <h2 style="font-size: 1.1rem; font-weight: 700; margin-bottom: 0.5rem;">Service Status — Last 90 Days</h2>
      <div class="chart-legend">
        <span class="legend-item"><span class="day-cell" style="background:#22c55e"></span> Operational</span>
        <span class="legend-item"><span class="day-cell" style="background:#f59e0b"></span> Degraded</span>
        <span class="legend-item"><span class="day-cell" style="background:#ef4444"></span> Down</span>
        <span class="legend-item"><span class="day-cell" style="background:#374151"></span> No data</span>
      </div>
    </div>
    <div style="padding: 1rem 1.25rem;">
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
