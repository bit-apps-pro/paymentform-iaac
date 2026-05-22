// Drives the real Stripe Connect Standard OAuth flow in TEST mode against the
// dev backend. Steps:
//  1. POST /{tenant}/stripe/connect to get the OAuth redirect URL
//  2. Open the URL in the Playwright page
//  3. Sign in with the Stripe test account (env.stripeEmail/password)
//  4. Click "Skip this account form" (Stripe test-mode shortcut)
//  5. Wait for the FE redirect back to ${FRONTEND_URL}/payment-gateway, which
//     signals StripeConnectController has stored the PaymentGateway row.
//
// Selectors are intentionally loose. Stripe's Connect onboarding UI changes
// regularly; if a step fails, capture a screenshot via Playwright trace and
// adjust. Headed mode is recommended (set WORKERS=1 + --headed) the first
// time you run against a new Stripe test account.

import { Page, expect } from '@playwright/test';
import { APIRequestContext } from '@playwright/test';
import { env } from './env';

export async function connectStripeViaOAuth(
  page: Page,
  apiCtx: APIRequestContext,
  workspaceId: string,
  bearerToken: string,
): Promise<void> {
  if (!env.stripeEmail || !env.stripePassword) {
    throw new Error('STRIPE_TEST_EMAIL / STRIPE_TEST_PASSWORD not set — required for Stripe Connect OAuth.');
  }

  const start = await apiCtx.post(`/${workspaceId}/stripe/connect`, {
    headers: { Authorization: `Bearer ${bearerToken}`, Accept: 'application/json' },
  });
  if (!start.ok()) {
    throw new Error(`stripe/connect failed (${start.status()}): ${await start.text()}`);
  }

  const startBody = (await start.json()) as { data?: { url?: string } };
  const oauthUrl = startBody.data?.url;
  if (!oauthUrl) {
    throw new Error('stripe/connect did not return data.url');
  }

  await page.goto(oauthUrl);

  // Stripe email/password screen.
  const emailField = page.locator('input[type="email"], input[name="email"]').first();
  await emailField.fill(env.stripeEmail);
  const next1 = page.getByRole('button', { name: /next|continue/i }).first();
  if (await next1.isVisible().catch(() => false)) await next1.click();

  const passwordField = page.locator('input[type="password"], input[name="password"]').first();
  await passwordField.fill(env.stripePassword);
  await page.getByRole('button', { name: /sign in|continue|log in/i }).first().click();

  // Stripe Connect dev-mode shortcut: a "Skip this account form" link.
  const skip = page.getByRole('link', { name: /skip (this )?account form|skip for now/i });
  await skip.first().click({ timeout: 30000 });

  // Final landing: FRONTEND_URL/payment-gateway (see StripeConnectController:87).
  await page.waitForURL(/\/payment-gateway/i, { timeout: 30000 });
  expect(page.url()).toMatch(/\/payment-gateway/);
}
