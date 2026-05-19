const CROCKFORD = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

function generateULID() {
  // Date.now() is up to 48 bits. JS bitwise ops truncate to 32, so divide for the
  // upper portion and keep the high 53-bit precision of Number until the final mod-32 walk.
  let time = Date.now();
  let timePart = '';
  for (let i = 0; i < 10; i++) {
    const mod = time % 32;
    timePart = CROCKFORD[mod] + timePart;
    time = (time - mod) / 32;
  }

  const randomBytes = new Uint8Array(16);
  crypto.getRandomValues(randomBytes);
  let randomPart = '';
  for (let i = 0; i < 16; i++) {
    randomPart += CROCKFORD[randomBytes[i] & 0x1f];
  }

  return timePart + randomPart;
}

function now() {
  return new Date().toISOString();
}

export async function listIncidents(env, { sinceDays = 90 } = {}) {
  const cutoff = Date.now() - sinceDays * 24 * 60 * 60 * 1000;
  const list = await env.INCIDENTS_KV.list({ prefix: 'incident:' });
  const incidents = [];

  for (const { name } of list.keys) {
    const incident = await env.INCIDENTS_KV.get(name, 'json');
    if (incident && new Date(incident.createdAt).getTime() >= cutoff) {
      incidents.push(incident);
    }
  }

  return incidents.reverse();
}

export async function getIncident(env, id) {
  return env.INCIDENTS_KV.get(`incident:${id}`, 'json');
}

export async function createIncident(env, { title, severity, affectedServices, status = 'investigating', body = null, source = 'manual' }) {
  if (!title || !severity || !affectedServices) {
    throw new Error('title, severity, and affectedServices are required');
  }

  const id = generateULID();
  const createdAt = now();
  const updates = body ? [{ at: createdAt, status, body }] : [];

  const incident = {
    id,
    title,
    status,
    severity,
    affectedServices,
    source,
    createdAt,
    resolvedAt: null,
    updates,
  };

  await env.INCIDENTS_KV.put(`incident:${id}`, JSON.stringify(incident));
  return incident;
}

export async function appendUpdate(env, id, { status: newStatus = null, body = null } = {}) {
  if (newStatus === null && body === null) {
    throw new Error('status or body required');
  }

  const incident = await getIncident(env, id);
  if (!incident) return null;

  if (incident.resolvedAt) {
    throw new Error('cannot update a resolved incident');
  }

  const order = ['investigating', 'identified', 'monitoring', 'resolved'];
  if (newStatus && order.indexOf(newStatus) < order.indexOf(incident.status)) {
    throw new Error('status cannot regress');
  }

  const at = now();
  const update = { at };
  if (newStatus !== null) update.status = newStatus;
  if (body !== null) update.body = body;

  incident.updates.push(update);
  if (newStatus !== null) incident.status = newStatus;

  if (newStatus === 'resolved') {
    incident.resolvedAt = at;
    if (incident.source === 'auto') {
      const counters = (await env.INCIDENTS_KV.get('health:counters', 'json')) || {};
      for (const service of incident.affectedServices) {
        if (counters[service]) {
          counters[service].openIncidentId = null;
        }
      }
      await env.INCIDENTS_KV.put('health:counters', JSON.stringify(counters));
    }
  }

  await env.INCIDENTS_KV.put(`incident:${id}`, JSON.stringify(incident));
  return incident;
}

export async function runAutoDetection(env, healthResult) {
  const counters = (await env.INCIDENTS_KV.get('health:counters', 'json')) || {};

  const openIncidents = await listIncidents(env, { sinceDays: 90 });
  const manualIncidents = openIncidents.filter(i => i.source === 'manual' && !i.resolvedAt);

  for (const service of healthResult.services) {
    const counter = counters[service.name] || { consecutiveFailures: 0, lastStatus: 'ok', openIncidentId: null };

    if (service.status === 'down' || service.status === 'degraded') {
      counter.consecutiveFailures++;
      counter.lastStatus = service.status;

      if (counter.consecutiveFailures >= 2 && !counter.openIncidentId) {
        const hasManual = manualIncidents.some(i => i.affectedServices.includes(service.name));
        if (!hasManual) {
          const severity = service.status === 'down' ? 'major' : 'minor';
          const errorInfo = service.httpStatus ? `(HTTP ${service.httpStatus})` : service.error ? `(${service.error})` : '';
          const body = `Automated detection: ${service.name} ${service.status} for 2 consecutive checks ${errorInfo}.`;

          const incident = await createIncident(env, {
            title: `${service.name} — ${service.status}`,
            severity,
            affectedServices: [service.name],
            source: 'auto',
            body,
          });
          counter.openIncidentId = incident.id;
        }
      } else if (counter.consecutiveFailures >= 2 && counter.openIncidentId) {
        const incident = await getIncident(env, counter.openIncidentId);
        if (incident) {
          const newSeverity = service.status === 'down' ? 'major' : 'minor';
          if (newSeverity > incident.severity || (newSeverity === 'major' && incident.severity === 'minor')) {
            incident.severity = newSeverity;
            const errorInfo = service.httpStatus ? `(HTTP ${service.httpStatus})` : service.error ? `(${service.error})` : '';
            const body = `Severity upgraded: ${service.name} degraded to ${service.status} ${errorInfo}.`;
            await appendUpdate(env, incident.id, { body });
          }
        }
      }
    } else if (service.status === 'ok') {
      if (counter.openIncidentId) {
        await appendUpdate(env, counter.openIncidentId, {
          status: 'resolved',
          body: `Automated detection: ${service.name} recovered.`,
        });
      }
      counter.openIncidentId = null;
      counter.consecutiveFailures = 0;
    }

    counters[service.name] = counter;
  }

  await env.INCIDENTS_KV.put('health:counters', JSON.stringify(counters));
}

export async function pruneOldIncidents(env, { sinceDays = 90 } = {}) {
  const cutoff = Date.now() - sinceDays * 24 * 60 * 60 * 1000;
  const list = await env.INCIDENTS_KV.list({ prefix: 'incident:' });

  for (const { name } of list.keys) {
    const incident = await env.INCIDENTS_KV.get(name, 'json');
    if (incident && incident.resolvedAt && new Date(incident.resolvedAt).getTime() < cutoff) {
      await env.INCIDENTS_KV.delete(name);
    }
  }
}
