import { describe, it, expect, beforeEach, vi } from 'vitest';
import {
  listIncidents,
  getIncident,
  createIncident,
  appendUpdate,
  runAutoDetection,
  pruneOldIncidents,
} from '../incidents.js';

function mockKV() {
  const store = new Map();
  return {
    async get(key, type) {
      const v = store.get(key);
      if (v == null) return null;
      return type === 'json' ? JSON.parse(v) : v;
    },
    async put(key, value) {
      store.set(key, typeof value === 'string' ? value : JSON.stringify(value));
    },
    async delete(key) {
      store.delete(key);
    },
    async list({ prefix } = {}) {
      const keys = [...store.keys()]
        .filter(k => !prefix || k.startsWith(prefix))
        .sort()
        .map(name => ({ name }));
      return { keys, list_complete: true };
    },
  };
}

function mockEnv() {
  return { INCIDENTS_KV: mockKV() };
}

describe('incidents', () => {
  let env;

  beforeEach(() => {
    env = mockEnv();
  });

  it('createIncident stores and retrieves incident', async () => {
    const incident = await createIncident(env, {
      title: 'API outage',
      severity: 'major',
      affectedServices: ['API'],
      body: 'Service down',
    });

    expect(incident.id).toBeDefined();
    expect(incident.id).toMatch(/^[0-9A-Z]{26}$/);
    expect(incident.title).toBe('API outage');
    expect(incident.severity).toBe('major');
    expect(incident.source).toBe('manual');
    expect(incident.createdAt).toBeDefined();
    expect(incident.resolvedAt).toBeNull();
    expect(incident.updates).toHaveLength(1);
    expect(incident.updates[0].body).toBe('Service down');

    const retrieved = await getIncident(env, incident.id);
    expect(retrieved).toEqual(incident);

    const list = await listIncidents(env);
    expect(list).toHaveLength(1);
    expect(list[0]).toEqual(incident);
  });

  it('ULID lexicographic ordering reflects chronological order', async () => {
    const now = Date.now();
    vi.setSystemTime(now);

    const incident1 = await createIncident(env, {
      title: 'First',
      severity: 'minor',
      affectedServices: ['A'],
    });

    vi.setSystemTime(now + 10);
    const incident2 = await createIncident(env, {
      title: 'Second',
      severity: 'minor',
      affectedServices: ['B'],
    });

    const list = await listIncidents(env);
    expect(list).toHaveLength(2);
    expect(list[0].id).toBe(incident2.id);
    expect(list[1].id).toBe(incident1.id);
  });

  it('appendUpdate adds timestamped entry', async () => {
    const incident = await createIncident(env, {
      title: 'Test',
      severity: 'minor',
      affectedServices: ['A'],
      body: 'Initial',
    });

    const updated = await appendUpdate(env, incident.id, {
      body: 'Update 1',
    });

    expect(updated.updates).toHaveLength(2);
    expect(updated.updates[1].body).toBe('Update 1');
    expect(updated.updates[1].at).toBeDefined();
  });

  it('appendUpdate validates status transitions', async () => {
    const incident = await createIncident(env, {
      title: 'Test',
      severity: 'minor',
      affectedServices: ['A'],
      status: 'monitoring',
    });

    await appendUpdate(env, incident.id, { status: 'identified' });
    const current = await getIncident(env, incident.id);
    expect(current.status).toBe('identified');

    await expect(
      appendUpdate(env, incident.id, { status: 'investigating' })
    ).rejects.toThrow('status cannot regress');
  });

  it('appendUpdate with resolved sets resolvedAt and prevents mutations', async () => {
    const incident = await createIncident(env, {
      title: 'Test',
      severity: 'minor',
      affectedServices: ['A'],
      source: 'auto',
    });

    const resolved = await appendUpdate(env, incident.id, {
      status: 'resolved',
      body: 'Fixed',
    });

    expect(resolved.resolvedAt).toBeDefined();
    expect(resolved.status).toBe('resolved');

    await expect(
      appendUpdate(env, incident.id, { body: 'Another update' })
    ).rejects.toThrow('cannot update a resolved incident');
  });

  it('appendUpdate clears openIncidentId for auto incidents', async () => {
    const incident = await createIncident(env, {
      title: 'Test',
      severity: 'minor',
      affectedServices: ['Service A'],
      source: 'auto',
    });

    await env.INCIDENTS_KV.put(
      'health:counters',
      JSON.stringify({
        'Service A': { consecutiveFailures: 2, lastStatus: 'down', openIncidentId: incident.id },
      })
    );

    await appendUpdate(env, incident.id, { status: 'resolved' });

    const counters = await env.INCIDENTS_KV.get('health:counters', 'json');
    expect(counters['Service A'].openIncidentId).toBeNull();
  });

  it('runAutoDetection opens auto-incident on 2-strike', async () => {
    const healthResult = {
      services: [
        { name: 'Service A', status: 'down', latencyMs: 5000, httpStatus: 503 },
      ],
    };

    await runAutoDetection(env, healthResult);
    const counters1 = await env.INCIDENTS_KV.get('health:counters', 'json');
    expect(counters1['Service A'].consecutiveFailures).toBe(1);
    expect(counters1['Service A'].openIncidentId).toBeNull();

    await runAutoDetection(env, healthResult);
    const counters2 = await env.INCIDENTS_KV.get('health:counters', 'json');
    expect(counters2['Service A'].consecutiveFailures).toBe(2);
    expect(counters2['Service A'].openIncidentId).toBeDefined();

    const incident = await getIncident(env, counters2['Service A'].openIncidentId);
    expect(incident.severity).toBe('major');
    expect(incident.source).toBe('auto');
    expect(incident.affectedServices).toEqual(['Service A']);
    expect(incident.updates[0].body).toContain('HTTP 503');
  });

  it('runAutoDetection resolves auto-incident on recovery', async () => {
    const downResult = {
      services: [{ name: 'Service A', status: 'down', latencyMs: 5000 }],
    };

    await runAutoDetection(env, downResult);
    await runAutoDetection(env, downResult);

    const counters = await env.INCIDENTS_KV.get('health:counters', 'json');
    const incidentId = counters['Service A'].openIncidentId;

    const okResult = {
      services: [{ name: 'Service A', status: 'ok', latencyMs: 100 }],
    };

    await runAutoDetection(env, okResult);

    const incident = await getIncident(env, incidentId);
    expect(incident.status).toBe('resolved');
    expect(incident.resolvedAt).toBeDefined();

    const updated = await env.INCIDENTS_KV.get('health:counters', 'json');
    expect(updated['Service A'].openIncidentId).toBeNull();
    expect(updated['Service A'].consecutiveFailures).toBe(0);
  });

  it('runAutoDetection upgrades severity on degradation', async () => {
    const degradedResult = {
      services: [
        { name: 'Service A', status: 'degraded', latencyMs: 3000, error: 'timeout' },
      ],
    };

    await runAutoDetection(env, degradedResult);
    await runAutoDetection(env, degradedResult);

    const counters1 = await env.INCIDENTS_KV.get('health:counters', 'json');
    const incidentId = counters1['Service A'].openIncidentId;
    let incident = await getIncident(env, incidentId);
    expect(incident.severity).toBe('minor');

    const downResult = {
      services: [{ name: 'Service A', status: 'down', latencyMs: 5000, httpStatus: 500 }],
    };

    await runAutoDetection(env, downResult);

    incident = await getIncident(env, incidentId);
    expect(incident.severity).toBe('major');
    expect(incident.updates.length).toBeGreaterThan(1);
    expect(incident.updates[1].body).toContain('Severity upgraded');
  });

  it('runAutoDetection does not downgrade severity', async () => {
    const downResult = {
      services: [{ name: 'Service A', status: 'down', latencyMs: 5000 }],
    };

    await runAutoDetection(env, downResult);
    await runAutoDetection(env, downResult);

    const counters1 = await env.INCIDENTS_KV.get('health:counters', 'json');
    const incidentId = counters1['Service A'].openIncidentId;
    let incident = await getIncident(env, incidentId);
    expect(incident.severity).toBe('major');

    const degradedResult = {
      services: [{ name: 'Service A', status: 'degraded', latencyMs: 3000 }],
    };

    await runAutoDetection(env, degradedResult);

    incident = await getIncident(env, incidentId);
    expect(incident.severity).toBe('major');
  });

  it('runAutoDetection skips auto-open when manual incident covers service', async () => {
    const manual = await createIncident(env, {
      title: 'Scheduled maintenance',
      severity: 'minor',
      affectedServices: ['Service A'],
      source: 'manual',
    });

    const downResult = {
      services: [{ name: 'Service A', status: 'down', latencyMs: 5000 }],
    };

    await runAutoDetection(env, downResult);
    await runAutoDetection(env, downResult);

    const counters = await env.INCIDENTS_KV.get('health:counters', 'json');
    expect(counters['Service A'].consecutiveFailures).toBe(2);
    expect(counters['Service A'].openIncidentId).toBeNull();

    const incidents = await listIncidents(env);
    expect(incidents).toHaveLength(1);
    expect(incidents[0].id).toBe(manual.id);
  });

  it('pruneOldIncidents deletes resolved incidents older than cutoff', async () => {
    const now = Date.now();
    vi.setSystemTime(now);

    const incident1 = await createIncident(env, {
      title: 'Old',
      severity: 'minor',
      affectedServices: ['A'],
    });

    vi.setSystemTime(now + 1000);
    const incident2 = await createIncident(env, {
      title: 'Recent',
      severity: 'minor',
      affectedServices: ['B'],
    });

    await appendUpdate(env, incident1.id, { status: 'resolved' });
    await appendUpdate(env, incident2.id, { status: 'resolved' });

    vi.setSystemTime(now + 91 * 24 * 60 * 60 * 1000);

    await pruneOldIncidents(env, { sinceDays: 90 });

    const remaining = await listIncidents(env, { sinceDays: 91 });
    expect(remaining.length).toBeGreaterThan(0);
    expect(remaining.some(i => i.id === incident2.id)).toBe(true);
  });

  it('pruneOldIncidents preserves unresolved incidents', async () => {
    const now = Date.now();
    vi.setSystemTime(now);

    const unresolved = await createIncident(env, {
      title: 'Open issue',
      severity: 'minor',
      affectedServices: ['A'],
    });

    vi.setSystemTime(now + 91 * 24 * 60 * 60 * 1000);

    await pruneOldIncidents(env, { sinceDays: 90 });

    const incident = await getIncident(env, unresolved.id);
    expect(incident).toBeDefined();
  });

  it('appendUpdate requires status or body', async () => {
    const incident = await createIncident(env, {
      title: 'Test',
      severity: 'minor',
      affectedServices: ['A'],
    });

    await expect(
      appendUpdate(env, incident.id, {})
    ).rejects.toThrow('status or body required');
  });

  it('createIncident requires title, severity, affectedServices', async () => {
    await expect(
      createIncident(env, { severity: 'minor', affectedServices: ['A'] })
    ).rejects.toThrow();

    await expect(
      createIncident(env, { title: 'Test', affectedServices: ['A'] })
    ).rejects.toThrow();

    await expect(
      createIncident(env, { title: 'Test', severity: 'minor' })
    ).rejects.toThrow();
  });
});
