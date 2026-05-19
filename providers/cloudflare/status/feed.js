function escapeXml(str) {
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;');
}

export function renderAtom(incidents) {
  const limited = incidents.slice(0, 50);

  let updated;
  if (limited.length > 0) {
    const newest = limited[0];
    updated = newest.resolvedAt || newest.updates[newest.updates.length - 1].at;
  } else {
    updated = new Date().toISOString();
  }

  let xml = '<?xml version="1.0" encoding="UTF-8"?>\n';
  xml += '<feed xmlns="http://www.w3.org/2005/Atom">\n';
  xml += '  <id>tag:status.paymentform.io,2026:incidents</id>\n';
  xml += '  <title>Paymentform Status — Incidents</title>\n';
  xml += '  <link rel="self" href="https://status.paymentform.io/feed.xml" />\n';
  xml += '  <link rel="alternate" href="https://status.paymentform.io/" />\n';
  xml += `  <updated>${escapeXml(updated)}</updated>\n`;

  for (const incident of limited) {
    const titleSuffix = incident.resolvedAt ? ' (resolved)' : '';
    const title = `[${incident.severity}] ${incident.title}${titleSuffix}`;
    const entryUpdated = incident.resolvedAt || incident.updates[incident.updates.length - 1].at;
    const mostRecentUpdate = incident.updates[incident.updates.length - 1];

    const updates = incident.updates
      .map(u => `<li><strong>${escapeXml(u.at)}</strong>: ${escapeXml(u.body)}</li>`)
      .join('\n');

    xml += '  <entry>\n';
    xml += `    <id>tag:status.paymentform.io,2026:incident/${escapeXml(incident.id)}</id>\n`;
    xml += `    <title>${escapeXml(title)}</title>\n`;
    xml += `    <updated>${escapeXml(entryUpdated)}</updated>\n`;
    xml += `    <published>${escapeXml(incident.createdAt)}</published>\n`;
    xml += `    <summary type="text">${escapeXml(mostRecentUpdate.body)}</summary>\n`;
    xml += `    <content type="html"><![CDATA[<ul>\n${updates}\n</ul>]]></content>\n`;
    xml += `    <link rel="alternate" href="https://status.paymentform.io/#incident-${escapeXml(incident.id)}" />\n`;
    xml += '  </entry>\n';
  }

  xml += '</feed>\n';
  return xml;
}
