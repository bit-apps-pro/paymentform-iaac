// Production create + render hammer.
//
// Each VU is pinned to a (token, tenant_id) pair from fixtures.json and runs:
//
//   1. POST /{tenant_id}/form/create  — create a uniquely-tagged form
//   2. GET  <tenant_render_url>/f/{uuid}  — render it via the renderer service
//   3. DELETE /{tenant_id}/form/delete/{id}  — clean up
//
// No submission, no payment. Goal: stress the form-create write path + render
// fetch path under concurrent load and assert that no cross-tenant leak
// occurs (a VU only ever sees a form tagged with its own VU id).
//
// fixtures.json shape (see fixtures.example.json):
//   [
//     {
//       "user_id": "...",
//       "tenant_id": "...",
//       "token": "...",                       // Sanctum bearer
//       "api_base_url": "https://api.paymentform.io",
//       "tenant_render_base_url": "https://<slug>.paymentform.io"
//     },
//     ...
//   ]
//
// Run-time env (mirrors session-pollution.js for ergonomics):
//   FIXTURES_FILE                path to fixtures JSON
//   API_BASE_URL                 override fixture's api_base_url
//   TENANT_RENDER_TEMPLATE       override fixture's tenant_render_base_url;
//                                %s is replaced with tenant_id per fixture
//   VUS, DURATION                k6 standard knobs (defaults 100 / 5m)
//
// Exit non-zero on any threshold breach (cross-tenant leak, error rate, p95).

import http from 'k6/http';
import { sleep } from 'k6';
import { SharedArray } from 'k6/data';
import { Counter, Rate, Trend } from 'k6/metrics';

const FIXTURES_FILE = __ENV.FIXTURES_FILE || './fixtures.json';
const API_BASE_URL = __ENV.API_BASE_URL || '';
const TENANT_RENDER_TEMPLATE = __ENV.TENANT_RENDER_TEMPLATE || '';
const VUS = Number(__ENV.VUS || 100);
const DURATION = __ENV.DURATION || '5m';

function resolveApiBase(fixture) {
  return (API_BASE_URL || fixture.api_base_url || '').replace(/\/$/, '');
}

function resolveRenderBase(fixture) {
  if (TENANT_RENDER_TEMPLATE) {
    return TENANT_RENDER_TEMPLATE.replace('%s', String(fixture.tenant_id)).replace(/\/$/, '');
  }
  return (fixture.tenant_render_base_url || '').replace(/\/$/, '');
}

const fixtures = new SharedArray('fixtures', () => JSON.parse(open(FIXTURES_FILE)));

const formCreateSuccess = new Rate('form_create_success');
const formRenderSuccess = new Rate('form_render_success');
const crossTenantLeak = new Counter('cross_tenant_leaks');
const formCreateLatency = new Trend('form_create_latency', true);
const formRenderLatency = new Trend('form_render_latency', true);

export const options = {
  scenarios: {
    create_render: {
      executor: 'constant-vus',
      vus: VUS,
      duration: DURATION,
    },
  },
  thresholds: {
    form_create_success: ['rate>0.995'],
    form_render_success: ['rate>0.995'],
    cross_tenant_leaks: ['count==0'],
    http_req_failed: ['rate<0.005'],
    'http_req_duration{name:create}': ['p(95)<2000'],
    'http_req_duration{name:render}': ['p(95)<2000'],
  },
};

function tagName(vu, fixture) {
  return `prodloadtest-vu${vu}-t${fixture.tenant_id}-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
}

function parseJson(res) {
  try { return res.json(); } catch { return null; }
}

export default function () {
  const me = fixtures[__VU % fixtures.length];
  if (!me) { console.error('No fixtures loaded'); return; }

  const apiBase = resolveApiBase(me);
  const renderBase = resolveRenderBase(me);
  const name = tagName(__VU, me);

  const headers = {
    Authorization: `Bearer ${me.token}`,
    'Content-Type': 'application/json',
    Accept: 'application/json',
  };

  // 1. Create form.
  const createPayload = JSON.stringify({
    formType: 8,
    name,
    templateType: 'donation-single-layout',
    successMessage: 'thanks',
    notificationEmailEnable: false,
    autoresponderEmailEnable: false,
    currencyCode: 'USD',
    status: 'enabled',
  });

  const createRes = http.post(`${apiBase}/${me.tenant_id}/form/create`, createPayload, {
    headers,
    tags: { name: 'create' },
  });
  const createOk = createRes.status >= 200 && createRes.status < 300;
  formCreateSuccess.add(createOk);
  formCreateLatency.add(createRes.timings.duration);

  if (!createOk) {
    console.error(`[create-fail] vu=${__VU} tenant=${me.tenant_id} status=${createRes.status} body=${createRes.body?.slice?.(0, 200)}`);
    sleep(0.5);
    return;
  }

  const createBody = parseJson(createRes);
  const form = createBody?.data ?? createBody;
  const formId = form?.id ?? form?.uuid;
  const formUuid = form?.uuid ?? form?.id;
  const ownerTenant = form?.tenant_id ?? form?.tenantId;

  if (ownerTenant && String(ownerTenant) !== String(me.tenant_id)) {
    crossTenantLeak.add(1);
    console.error(`[cross-tenant-leak:create] vu=${__VU} expected=${me.tenant_id} got=${ownerTenant}`);
  }

  if (!formUuid) {
    sleep(0.3);
    return;
  }

  // 2. Render. Renderer service serves the form-render page on the tenant subdomain.
  const renderRes = http.get(`${renderBase}/f/${formUuid}`, { tags: { name: 'render' } });
  const renderOk = renderRes.status >= 200 && renderRes.status < 400;
  formRenderSuccess.add(renderOk);
  formRenderLatency.add(renderRes.timings.duration);

  // The renderer's response embeds the form name (or its tag) — if our VU
  // sees a `prodloadtest-vuX-...` tag for a different VU here, the renderer
  // mixed up requests across tenants.
  if (renderOk && typeof renderRes.body === 'string') {
    const foreignTag = renderRes.body.match(/prodloadtest-vu(\d+)-/);
    if (foreignTag && Number(foreignTag[1]) !== __VU) {
      crossTenantLeak.add(1);
      console.error(`[cross-tenant-leak:render] vu=${__VU} sees tag from vu=${foreignTag[1]} on tenant=${me.tenant_id}`);
    }
  }

  // 3. Cleanup. Best-effort; deletes don't block the test on failure.
  http.del(`${apiBase}/${me.tenant_id}/form/delete/${formId}`, null, {
    headers,
    tags: { name: 'delete' },
  });

  sleep(0.1 + Math.random() * 0.3);
}

export function handleSummary(data) {
  const m = data.metrics;
  const rate = k => ((m[k]?.values?.rate ?? 0) * 100).toFixed(2);
  const count = k => m[k]?.values?.count ?? 0;
  const p95 = k => (m[k]?.values?.['p(95)'] ?? 0).toFixed(0);
  const failedPct = ((m.http_req_failed?.values?.rate ?? 0) * 100).toFixed(2);

  const leaks = count('cross_tenant_leaks');
  const verdict = leaks === 0
    ? 'PASS — no cross-tenant leaks'
    : `FAIL — ${leaks} cross-tenant leak events`;

  const text = `
=== Production Form Create + Render Stress ===
  VUs: ${VUS}    Duration: ${DURATION}

  form_create_success:   ${rate('form_create_success')}%
  form_render_success:   ${rate('form_render_success')}%
  cross_tenant_leaks:    ${leaks}

  form_create_latency p95: ${p95('form_create_latency')}ms
  form_render_latency p95: ${p95('form_render_latency')}ms
  http_req_failed:       ${failedPct}%

  ${verdict}
`;
  return {
    stdout: text,
    'create-render-summary.json': JSON.stringify(data, null, 2),
  };
}
