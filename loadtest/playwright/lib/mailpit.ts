// Mailpit REST helpers. Mailpit's `/api/v1/search?query=to:<addr>` returns
// the latest matching messages; the message body contains the 6-digit
// verification code emitted by VerifyEmailWithCode.

import { request as playwrightRequest } from '@playwright/test';
import { env, mailpitBase } from './env';

type MailpitMessageSummary = {
  ID: string;
  Created: string;
  Subject: string;
  To: Array<{ Address: string }>;
};

type MailpitSearchResponse = {
  messages: MailpitMessageSummary[];
};

type MailpitMessage = {
  ID: string;
  Text: string;
  HTML: string;
};

const VERIFICATION_CODE_RE = /\b(\d{6})\b/;

/**
 * Poll mailpit until an email arrives for `address` (or timeout) and return
 * the extracted 6-digit verification code. Uses one short-lived APIRequestContext
 * to keep mailpit connection count proportional to active workers, not VUs.
 */
export async function waitForVerificationCode(address: string): Promise<string> {
  const ctx = await playwrightRequest.newContext({ baseURL: mailpitBase() });
  const deadline = Date.now() + env.mailpitTimeoutMs;
  const query = encodeURIComponent(`to:${address}`);

  try {
    while (Date.now() < deadline) {
      const res = await ctx.get(`/api/v1/search?query=${query}&limit=1`);
      if (res.ok()) {
        const body = (await res.json()) as MailpitSearchResponse;
        if (body.messages && body.messages.length > 0) {
          const id = body.messages[0].ID;
          const detail = await ctx.get(`/api/v1/message/${id}`);
          if (detail.ok()) {
            const message = (await detail.json()) as MailpitMessage;
            const haystack = `${message.Text}\n${message.HTML}`;
            const match = haystack.match(VERIFICATION_CODE_RE);
            if (match) return match[1];
          }
        }
      }
      await sleep(750);
    }
    throw new Error(`Timed out waiting for verification code to ${address}`);
  } finally {
    await ctx.dispose();
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
