// Centralised env access. Validates required vars at load time so worker
// failures fail loudly instead of producing confusing 404s deep in a flow.

import 'dotenv/config';

function required(name: string): string {
  const value = process.env[name];
  if (!value || value.trim() === '') {
    throw new Error(`Missing required env var: ${name}`);
  }
  return value.trim();
}

function optional(name: string, fallback: string): string {
  const value = process.env[name];
  return value && value.trim() !== '' ? value.trim() : fallback;
}

export const env = {
  traefikHost: required('TRAEFIK_HOST'),
  traefikPort: optional('TRAEFIK_PORT', '8021'),
  workers: Number(optional('WORKERS', '5')),
  iterations: Number(optional('ITERATIONS', '1')),
  stripeEmail: optional('STRIPE_TEST_EMAIL', ''),
  stripePassword: optional('STRIPE_TEST_PASSWORD', ''),
  registrationPassword: optional('REGISTRATION_PASSWORD', 'Loadtest-Pa55!'),
  mailpitTimeoutMs: Number(optional('MAILPIT_TIMEOUT_MS', '60000')),
  workspaceTimeoutMs: Number(optional('WORKSPACE_TIMEOUT_MS', '180000')),
};

export function apiBase(): string {
  return `http://api.${env.traefikHost}:${env.traefikPort}`;
}

export function appBase(): string {
  return `http://app.${env.traefikHost}:${env.traefikPort}`;
}

export function mailpitBase(): string {
  return `http://mailpit.${env.traefikHost}:${env.traefikPort}`;
}

export function tenantBase(slug: string): string {
  return `http://${slug}.${env.traefikHost}:${env.traefikPort}`;
}
