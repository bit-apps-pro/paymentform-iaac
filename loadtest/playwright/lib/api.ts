// Thin REST client over the central API. Reuses one APIRequestContext per
// worker so cookies (web + tenant session) persist across the chain. Sanctum
// bearer tokens are passed via the Authorization header where the cookie
// pipeline doesn't apply (verification-code GET, workspace status).

import { APIRequestContext, request as playwrightRequest } from '@playwright/test';
import { env, apiBase } from './env';

export type AuthSession = {
  ctx: APIRequestContext;
  token: string;
  userId: string;
  userUuid: string;
  email: string;
  password: string;
};

export type WorkspaceStatus = {
  workspaceId: string;
  url: string;
  state: string;
  provisioning: Record<string, unknown>;
};

export type CreatedForm = {
  id: number | string;
  uuid: string;
  name: string;
};

export async function register(name: string, email: string, password: string): Promise<AuthSession> {
  const ctx = await playwrightRequest.newContext({
    baseURL: apiBase(),
    extraHTTPHeaders: { Accept: 'application/json' },
  });

  const res = await ctx.post('/register', {
    data: { name, email, password },
  });
  if (!res.ok()) {
    throw new Error(`register failed (${res.status()}): ${await res.text()}`);
  }
  const body = (await res.json()) as {
    data: { token: string; user: { id: number | string; uuid: string } };
  };

  return {
    ctx,
    token: body.data.token,
    userId: String(body.data.user.id),
    userUuid: body.data.user.uuid,
    email,
    password,
  };
}

export async function submitVerificationCode(session: AuthSession, code: string): Promise<void> {
  // Route is GET /verify-email/code?code=XXXXXX — Laravel reads via input().
  const res = await session.ctx.get(`/verify-email/code?code=${encodeURIComponent(code)}`, {
    headers: bearer(session),
  });
  if (!res.ok()) {
    throw new Error(`verify-email/code failed (${res.status()}): ${await res.text()}`);
  }
}

/**
 * Poll /workspace/status until the tenant reaches the 'ready' state. The
 * provisioning chain is async, so we wait up to env.workspaceTimeoutMs.
 */
export async function waitForWorkspaceReady(session: AuthSession): Promise<WorkspaceStatus> {
  const deadline = Date.now() + env.workspaceTimeoutMs;
  let last: WorkspaceStatus | null = null;

  while (Date.now() < deadline) {
    const res = await session.ctx.get('/workspace/status', { headers: bearer(session) });
    if (res.ok()) {
      const body = (await res.json()) as {
        data: {
          workspace: null | {
            id: string;
            url: string;
            provisioning: { state: string } & Record<string, unknown>;
          };
        };
      };
      if (body.data.workspace) {
        last = {
          workspaceId: body.data.workspace.id,
          url: body.data.workspace.url,
          state: body.data.workspace.provisioning.state,
          provisioning: body.data.workspace.provisioning,
        };
        if (last.state === 'ready') return last;
      }
    }
    await sleep(1000);
  }

  throw new Error(
    `workspace not ready after ${env.workspaceTimeoutMs}ms (last state=${last?.state ?? 'null'})`,
  );
}

/**
 * Re-authenticate via /login so the SessionGuard for both `central` and `tenant`
 * is populated on the shared APIRequestContext. After registration only the
 * central guard is logged in; tenant guard is needed for /{tenant}/form/create.
 */
export async function login(session: AuthSession): Promise<void> {
  await session.ctx.get('/sanctum/csrf-cookie');
  const res = await session.ctx.post('/login', {
    data: { email: session.email, password: session.password, remember: false },
  });
  if (!res.ok()) {
    throw new Error(`login failed (${res.status()}): ${await res.text()}`);
  }
}

export async function createForm(
  session: AuthSession,
  workspaceId: string,
  name: string,
): Promise<CreatedForm> {
  const res = await session.ctx.post(`/${workspaceId}/form/create`, {
    headers: bearer(session),
    data: {
      formType: 8,
      name,
      templateType: 'donation-single-layout',
      successMessage: 'thanks',
      notificationEmailEnable: false,
      autoresponderEmailEnable: false,
      currencyCode: 'USD',
      status: 'enabled',
    },
  });
  if (!res.ok()) {
    throw new Error(`form/create failed (${res.status()}): ${await res.text()}`);
  }
  const body = (await res.json()) as { data: { id: number | string; uuid: string; name: string } };
  return body.data;
}

export async function deleteForm(session: AuthSession, workspaceId: string, formId: number | string): Promise<void> {
  await session.ctx.delete(`/${workspaceId}/form/delete/${formId}`, { headers: bearer(session) });
}

export async function disposeSession(session: AuthSession): Promise<void> {
  await session.ctx.dispose();
}

function bearer(session: AuthSession): Record<string, string> {
  return { Authorization: `Bearer ${session.token}` };
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
