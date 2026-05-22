// Session-pollution stress test.
//
// Drives many concurrent VUs, each pinned to a distinct (user, tenant)
// identity. On every response we assert the resolved identity matches the
// caller — any drift is a pollution event. Also scans tenant-scoped list
// endpoints for forms tagged by *other* users (cross-tenant leak).
//
// Run-time env:
//   FIXTURES_FILE             path to fixtures JSON (default ./fixtures.json)
//   API_BASE_URL              override fixture's api_base_url (e.g. https://api.dev.paymentform.io)
//   TENANT_BASE_URL_TEMPLATE  override fixture's tenant_base_url; %s is replaced
//                             with each fixture's tenant_id
//                             (e.g. https://%s.api.dev.paymentform.io)
//   VUS                       concurrent virtual users (default 50)
//   DURATION                  run length, k6 duration string (default 5m)
//   WITH_WRITES               "1" / "true" enables the create+verify+delete loop
//
// Exit 0 iff pollution_events == 0 and http_req_failed < 5%.

import http from 'k6/http';
import { check, sleep } from 'k6';
import { SharedArray } from 'k6/data';
import { Counter } from 'k6/metrics';

const FIXTURES_FILE = __ENV.FIXTURES_FILE || './fixtures.json';
const API_BASE_URL = __ENV.API_BASE_URL || '';
const TENANT_BASE_URL_TEMPLATE = __ENV.TENANT_BASE_URL_TEMPLATE || '';
const VUS = Number(__ENV.VUS || 50);
const DURATION = __ENV.DURATION || '5m';
const WITH_WRITES = __ENV.WITH_WRITES === '1' || __ENV.WITH_WRITES === 'true';

function resolveApiBase(fixture) {
  return (API_BASE_URL || fixture.api_base_url || '').replace(/\/$/, '');
}

function resolveTenantBase(fixture) {
  if (TENANT_BASE_URL_TEMPLATE) {
    return TENANT_BASE_URL_TEMPLATE.replace('%s', String(fixture.tenant_id)).replace(/\/$/, '');
  }
  return (fixture.tenant_base_url || '').replace(/\/$/, '');
}

const fixtures = new SharedArray('users', () => JSON.parse(open(FIXTURES_FILE)));

const pollution         = new Counter('pollution_events');
const identityMismatch  = new Counter('identity_mismatches');
const crossTenantLeak   = new Counter('cross_tenant_leaks');
const authFailure       = new Counter('auth_failures');

export const options = {
  scenarios: {
    user_behavior: {
      executor: 'constant-vus',
      vus: VUS,
      duration: DURATION,
    },
  },
  thresholds: {
    pollution_events:    ['count==0'],
    identity_mismatches: ['count==0'],
    cross_tenant_leaks:  ['count==0'],
    http_req_failed:     ['rate<0.05'],
  },
};

function tagName(me) {
  // Embed both VU id and user_id so we can spot tags written by anyone else.
  return `pollutiontest-vu${__VU}-u${me.user_id}-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
}

function isForeignTag(title, me) {
  if (typeof title !== 'string' || !title.startsWith('pollutiontest-')) return false;
  return !title.includes(`-u${me.user_id}-`);
}

function parseJson(res) {
  try { return res.json(); } catch { return null; }
}

function recordIdentityResult(label, expected, got, vu) {
  if (got === undefined || got === null) return;
  if (String(got) !== String(expected)) {
    identityMismatch.add(1);
    pollution.add(1);
    console.error(`[identity-leak] ${label} vu=${vu} expected=${expected} got=${got}`);
  }
}

export default function () {
  const me = fixtures[__VU % fixtures.length];
  if (!me) { console.error('No fixtures loaded'); return; }

  const apiBase    = resolveApiBase(me);
  const tenantBase = resolveTenantBase(me);

  const headers = {
    Authorization: `Bearer ${me.token}`,
    'Content-Type': 'application/json',
    Accept: 'application/json',
  };

  // 1. Central /me — auth guard sanity (route defined in routes/auth.php, mounted at root)
  let res = http.get(`${apiBase}/me`, { headers, tags: { name: 'central:me' } });
  if (res.status === 401) { authFailure.add(1); return; }
  if (res.status === 200) {
    const body = parseJson(res);
    const id = body?.id ?? body?.data?.id ?? body?.user?.id;
    recordIdentityResult('central:me', me.user_id, id, __VU);
  }

  // 2. Tenant-scoped /me — exercises tenant resolution + auth in same call
  res = http.get(`${tenantBase}/me`, { headers, tags: { name: 'tenant:me' } });
  if (res.status === 200) {
    const body = parseJson(res);
    const id = body?.id ?? body?.data?.id ?? body?.user?.id;
    recordIdentityResult('tenant:me', me.user_id, id, __VU);
    const resolvedTenant = body?.active_tenant ?? body?.tenant_id ?? body?.data?.active_tenant ?? body?.data?.tenant_id;
    if (resolvedTenant !== undefined && resolvedTenant !== null) {
      recordIdentityResult('tenant:me/tenant_id', me.tenant_id, resolvedTenant, __VU);
    }
  }

  // 3. Tenant forms list — catches cross-tenant data leak
  res = http.get(`${tenantBase}/forms`, { headers, tags: { name: 'tenant:forms_list' } });
  if (res.status === 200) {
    const body = parseJson(res);
    const list = Array.isArray(body?.data) ? body.data
              : Array.isArray(body?.forms) ? body.forms
              : Array.isArray(body) ? body : [];
    for (const form of list) {
      const title = form?.name ?? form?.title;
      if (isForeignTag(title, me)) {
        crossTenantLeak.add(1);
        pollution.add(1);
        console.error(`[cross-tenant-leak] vu=${__VU} user=${me.user_id} tenant=${me.tenant_id} sees foreign form id=${form?.id ?? form?.uuid} name="${title}"`);
      }
    }
  }

  // 4. Optional: tagged write + verify + cleanup
  if (WITH_WRITES) {
    const name = tagName(me);
    const payload = JSON.stringify({
      formType: 8,                                // FormModuleType::GENERAL_FORM
      name,
      templateType: 'donation-single-layout',     // TemplateType::DONATION_SINGLE_LAYOUT
      successMessage: 'thanks',
      notificationEmailEnable: false,
      autoresponderEmailEnable: false,
      currencyCode: 'USD',
      status: 'disabled',
    });

    res = http.post(`${tenantBase}/forms/create`, payload, { headers, tags: { name: 'tenant:forms_create' } });
    if (res.status >= 200 && res.status < 300) {
      const body = parseJson(res);
      const id = body?.id ?? body?.data?.id ?? body?.uuid ?? body?.data?.uuid;
      if (id) {
        const showRes = http.get(`${tenantBase}/forms/${id}`, { headers, tags: { name: 'tenant:form_show' } });
        check(showRes, { 'own form retrievable': r => r.status === 200 });
        http.del(`${tenantBase}/forms/delete/${id}`, null, { headers, tags: { name: 'tenant:form_delete' } });
      }
    }
  }

  sleep(0.1 + Math.random() * 0.4);
}

export function handleSummary(data) {
  const m = data.metrics;
  const c = k => m[k]?.values?.count ?? 0;
  const failedPct = ((m.http_req_failed?.values?.rate ?? 0) * 100).toFixed(2);
  const p95 = (m.http_req_duration?.values?.['p(95)'] ?? 0).toFixed(0);
  const total = c('pollution_events');
  const verdict = total === 0 ? 'PASS — no pollution detected' : `FAIL — ${total} pollution events`;
  const text = `
=== Session Pollution Stress Test ===
  VUs: ${VUS}    Duration: ${DURATION}    Writes: ${WITH_WRITES ? 'on' : 'off'}

  pollution_events:    ${c('pollution_events')}
  identity_mismatches: ${c('identity_mismatches')}
  cross_tenant_leaks:  ${c('cross_tenant_leaks')}
  auth_failures:       ${c('auth_failures')}

  http_reqs:           ${c('http_reqs')}
  http_req_failed:     ${failedPct}%
  http_req_duration p95: ${p95}ms

  ${verdict}
`;
  return {
    stdout: text,
    'summary.json': JSON.stringify(data, null, 2),
  };
}
