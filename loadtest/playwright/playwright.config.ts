// Playwright config tuned for stress runs against the dev compose stack.
// - One project (chromium). Headed is a CLI toggle.
// - `workers` knob is taken from env so callers can swap parallelism without
//   editing this file.
// - Long timeouts: the chain includes mailpit polling + async tenant
//   provisioning + Stripe OAuth, none of which fit a default 30s budget.

import { defineConfig } from '@playwright/test';
import { env } from './lib/env';

export default defineConfig({
  testDir: './tests',
  timeout: 5 * 60 * 1000,
  expect: { timeout: 30 * 1000 },
  fullyParallel: true,
  workers: env.workers,
  reporter: [['list'], ['html', { open: 'never', outputFolder: 'playwright-report' }]],
  use: {
    actionTimeout: 30 * 1000,
    navigationTimeout: 60 * 1000,
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
    ignoreHTTPSErrors: true,
  },
  projects: [
    {
      name: 'chromium',
      use: { browserName: 'chromium' },
    },
  ],
});
