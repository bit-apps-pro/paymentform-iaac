// Signup-burst stress test.
//
// Fires N concurrent signups against the backend and measures, per VU:
//   * signup_latency_ms       — POST /register round-trip
//   * provision_latency_ms    — time from token issued until
//                               workspace.status returns provisioning.state=ready
//   * e2e_latency_ms          — signup_start → tenant ready (the user-visible wait)
//
// The point is to surface queue-pickup serialization (e.g. when a single
// global lock or under-provisioned worker pool turns a burst into a stairstep
// of 50s, 100s, 150s waits). Each VU runs exactly one signup iteration so
// the metrics reflect the burst's tail latency rather than steady-state.
//
// Run-time env:
//   API_BASE_URL              backend root (default http://localhost:8080)
//   VUS                       concurrent signups (default 10)
//   EMAIL_DOMAIN              throwaway domain for signup emails (default
//                             example.com — DNS-resolvable, won't bounce)
//   POLL_TIMEOUT_MS           cap on how long we wait for provisioning to
//                             complete per VU (default 180000 = 3 min)
//   POLL_INTERVAL_MS          status-poll cadence (default 500 ms)
//   PASSWORD                  password used for every signup (default a
//                             fixed strong throwaway value)
//
// Exit 0 iff signup_failures == 0 and provision_timeouts == 0.

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Counter, Trend } from 'k6/metrics';

const API_BASE_URL = (__ENV.API_BASE_URL || 'http://localhost:8080').replace(/\/$/, '');
const VUS = Number(__ENV.VUS || 10);
const EMAIL_DOMAIN = __ENV.EMAIL_DOMAIN || 'example.com';
const POLL_TIMEOUT_MS = Number(__ENV.POLL_TIMEOUT_MS || 180000);
const POLL_INTERVAL_MS = Number(__ENV.POLL_INTERVAL_MS || 500);
const PASSWORD = __ENV.PASSWORD || 'Loadtest!P@ssw0rd123';

const signupLatency = new Trend('signup_latency_ms', true);
const provisionLatency = new Trend('provision_latency_ms', true);
const e2eLatency = new Trend('e2e_latency_ms', true);
const signupFailures = new Counter('signup_failures');
const provisionTimeouts = new Counter('provision_timeouts');
const pollRequests = new Counter('poll_requests');

export const options = {
  scenarios: {
    burst: {
      executor: 'per-vu-iterations',
      vus: VUS,
      iterations: 1,
      maxDuration: '10m',
      gracefulStop: '30s',
    },
  },
  thresholds: {
    signup_failures: ['count==0'],
    provision_timeouts: ['count==0'],
    'provision_latency_ms': ['p(95)<60000', 'p(99)<120000'],
    'e2e_latency_ms': ['p(95)<70000'],
    http_req_failed: ['rate<0.05'],
  },
};

function uniqueId() {
  return `${__VU}-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
}

function readXsrfCookie() {
  const cookies = http.cookieJar().cookiesForURL(API_BASE_URL);
  const raw = cookies['XSRF-TOKEN']?.[0];
  return raw ? decodeURIComponent(raw) : '';
}

function extractToken(res) {
  const body = (() => { try { return res.json(); } catch { return null; } })();
  if (!body) return null;
  return body?.data?.token
    ?? body?.token
    ?? body?.data?.data?.token
    ?? null;
}

function readProvisioningState(res) {
  const body = (() => { try { return res.json(); } catch { return null; } })();
  if (!body) return null;
  return body?.data?.activeTenant?.provisioning?.state
    ?? body?.data?.tenant?.provisioning?.state
    ?? body?.activeTenant?.provisioning?.state
    ?? null;
}

export default function () {
  const id = uniqueId();
  const email = `loadtest+${id}@${EMAIL_DOMAIN}`;
  const tStart = Date.now();

  // Sanctum SPA flow: GET /sanctum/csrf-cookie to seed XSRF-TOKEN cookie,
  // then echo it as X-XSRF-TOKEN on the POST. The cookie jar is per-VU,
  // so concurrent VUs do not share state here.
  http.get(`${API_BASE_URL}/sanctum/csrf-cookie`, { tags: { step: 'csrf' } });
  const xsrf = readXsrfCookie();

  const regHeaders = {
    'Content-Type': 'application/json',
    Accept: 'application/json',
    Referer: `${API_BASE_URL}/`,
  };
  if (xsrf) regHeaders['X-XSRF-TOKEN'] = xsrf;

  const regBody = JSON.stringify({
    name: `Loadtest VU${__VU}`,
    email,
    password: PASSWORD,
    password_confirmation: PASSWORD,
  });

  const regRes = http.post(`${API_BASE_URL}/register`, regBody, {
    headers: regHeaders,
    tags: { step: 'register' },
  });
  const signupMs = Date.now() - tStart;
  signupLatency.add(signupMs);

  const signupOk = check(regRes, {
    'signup 2xx': r => r.status >= 200 && r.status < 300,
  });
  if (!signupOk) {
    signupFailures.add(1);
    console.error(`[VU${__VU}] signup failed status=${regRes.status} body=${regRes.body?.slice?.(0, 200)}`);
    return;
  }

  const token = extractToken(regRes);
  if (!token) {
    signupFailures.add(1);
    console.error(`[VU${__VU}] signup ok but token missing in response`);
    return;
  }

  const pollHeaders = {
    Authorization: `Bearer ${token}`,
    Accept: 'application/json',
  };

  const tPollStart = Date.now();
  let provisioned = false;
  let lastState = null;
  while (Date.now() - tPollStart < POLL_TIMEOUT_MS) {
    const statusRes = http.get(`${API_BASE_URL}/workspace/status`, {
      headers: pollHeaders,
      tags: { step: 'poll' },
    });
    pollRequests.add(1);
    if (statusRes.status === 200) {
      lastState = readProvisioningState(statusRes);
      if (lastState === 'ready') {
        provisioned = true;
        break;
      }
    }
    sleep(POLL_INTERVAL_MS / 1000);
  }

  const provisionMs = Date.now() - tPollStart;
  const totalMs = Date.now() - tStart;

  if (!provisioned) {
    provisionTimeouts.add(1);
    console.error(`[VU${__VU}] provisioning timed out after ${provisionMs}ms (last_state=${lastState})`);
    return;
  }

  provisionLatency.add(provisionMs);
  e2eLatency.add(totalMs);
}

export function handleSummary(data) {
  const m = data.metrics;
  const c = k => m[k]?.values?.count ?? 0;
  const trend = k => {
    const v = m[k]?.values;
    if (!v) return 'n/a';
    return `min=${v.min?.toFixed(0)}ms p50=${v['p(50)']?.toFixed(0)}ms p95=${v['p(95)']?.toFixed(0)}ms max=${v.max?.toFixed(0)}ms avg=${v.avg?.toFixed(0)}ms`;
  };
  const failures = c('signup_failures') + c('provision_timeouts');
  const verdict = failures === 0 ? 'PASS — all VUs reached ready' : `FAIL — ${failures} VU(s) failed`;

  const text = `
=== Signup Burst Test ===
  VUs: ${VUS}    API_BASE_URL: ${API_BASE_URL}
  email domain: ${EMAIL_DOMAIN}    poll interval: ${POLL_INTERVAL_MS}ms

  signup_latency_ms      ${trend('signup_latency_ms')}
  provision_latency_ms   ${trend('provision_latency_ms')}
  e2e_latency_ms         ${trend('e2e_latency_ms')}

  signup_failures:       ${c('signup_failures')}
  provision_timeouts:    ${c('provision_timeouts')}
  poll_requests:         ${c('poll_requests')}

  http_reqs:             ${c('http_reqs')}
  http_req_failed:       ${((m.http_req_failed?.values?.rate ?? 0) * 100).toFixed(2)}%

  ${verdict}
`;
  return {
    stdout: text,
    'signup-burst-summary.json': JSON.stringify(data, null, 2),
  };
}
