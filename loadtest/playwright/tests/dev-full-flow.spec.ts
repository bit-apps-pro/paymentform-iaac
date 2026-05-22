// Dev full-flow stress test.
//
// Each Playwright worker runs the whole signup -> verify -> provision ->
// login -> form create -> Stripe Connect OAuth -> render -> submit chain.
// We multiplex parallelism via Playwright's `workers` setting (env.workers)
// and via repeating the chain ITERATIONS times per worker.
//
// The test is *not* about asserting individual UI behaviour — that's what
// the project's normal e2e suite covers. It's about driving real concurrent
// load through the central + tenant + renderer + payment-gateway path and
// surfacing failures that only appear under contention (session pollution,
// rate-limit breaches, provisioning races, OAuth flakiness).
//
// Run:
//   cp .env.example .env && edit
//   npm install && npm run install:browsers
//   WORKERS=10 ITERATIONS=1 npm test

import { test, expect } from '@playwright/test';
import {
  register,
  submitVerificationCode,
  waitForWorkspaceReady,
  login,
  createForm,
  deleteForm,
  disposeSession,
} from '../lib/api';
import { waitForVerificationCode } from '../lib/mailpit';
import { connectStripeViaOAuth } from '../lib/stripe-oauth';
import { env, tenantBase } from '../lib/env';

const iterations = Math.max(1, env.iterations);

for (let i = 0; i < iterations; i++) {
  test(`full-flow iteration #${i}`, async ({ page }, testInfo) => {
    const workerIndex = testInfo.workerIndex;
    const stamp = Date.now();
    const email = `loadtest-w${workerIndex}-i${i}-${stamp}@example.test`;
    const name = `Loadtest W${workerIndex} I${i}`;
    const password = env.registrationPassword;

    let session: Awaited<ReturnType<typeof register>> | null = null;
    let createdFormId: string | number | null = null;
    let workspaceId: string | null = null;

    try {
      await test.step('register', async () => {
        session = await register(name, email, password);
        expect(session.token).toBeTruthy();
        expect(session.userUuid).toBeTruthy();
      });

      const code = await test.step('wait for verification email', async () => {
        return waitForVerificationCode(email);
      });

      await test.step('submit verification code', async () => {
        await submitVerificationCode(session!, code);
      });

      const status = await test.step('wait for workspace ready', async () => {
        return waitForWorkspaceReady(session!);
      });
      workspaceId = status.workspaceId;

      await test.step('login (web + tenant guards)', async () => {
        await login(session!);
      });

      const form = await test.step('create form', async () => {
        return createForm(session!, workspaceId!, `Loadtest Form w${workerIndex}-i${i}-${stamp}`);
      });
      createdFormId = form.id;

      await test.step('connect Stripe via OAuth', async () => {
        await connectStripeViaOAuth(page, session!.ctx, workspaceId!, session!.token);
      });

      await test.step('render form on tenant subdomain', async () => {
        const url = `${tenantBase(workspaceId!)}/f/${form.uuid}`;
        const response = await page.goto(url, { waitUntil: 'networkidle' });
        expect(response, `render did not respond at ${url}`).not.toBeNull();
        expect(response!.status(), `render returned ${response!.status()} at ${url}`).toBeLessThan(400);
      });
    } finally {
      // Cleanup is best-effort; a failed iteration shouldn't fail cleanup too.
      if (session && workspaceId && createdFormId) {
        await deleteForm(session, workspaceId, createdFormId).catch(() => undefined);
      }
      if (session) {
        await disposeSession(session).catch(() => undefined);
      }
    }
  });
}
