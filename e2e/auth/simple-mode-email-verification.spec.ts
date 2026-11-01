// e2e/auth/simple-mode-email-verification.spec.ts
//
// E2E for issue #4831: in simple auth mode, the account verification link
// from the welcome email must verify the account when it is opened in a
// browser that has no session.
//
// ─────────────────────────────────────────────────────────────────────────────
// THE JOURNEY
// ─────────────────────────────────────────────────────────────────────────────
//
//   /signup → submit → /check-email
//     → welcome email (real SMTP → Mailpit) with a /secret/<key> link
//     → open the link IN A FRESH BROWSER CONTEXT → click to verify
//     → the reveal answers 200 and shows the secret
//     → sign in → /bootstrap/me reports the account verified
//
// Simple mode verifies an account by revealing a verification secret, on the
// same auth=noauth guest reveal route every recipient uses. #4831 was that
// route refusing every anonymous verification with a 422, because the caller
// arrives with no customer at all. The unit specs cover the logic; this spec
// covers the route, the strategy that resolves the caller, and the SPA.
//
// ─────────────────────────────────────────────────────────────────────────────
// PROJECT / ENVIRONMENT
// ─────────────────────────────────────────────────────────────────────────────
//
// Runs in the `chromium` project (e2e/all + e2e/auth), with no storageState.
// The target server must send the welcome email and must not autoverify:
//   AUTHENTICATION_MODE=simple      asserted below from /bootstrap/me
//   AUTH_AUTOVERIFY=false           the config default; asserted below. With it
//                                   on, signup verifies at once and sends nothing
//   EMAILER_MODE=smtp + SMTP_HOST/SMTP_PORT → Mailpit
//                                   simple-mode signup delivers inline
//                                   (Logic::Base#send_verification_email), so
//                                   no job worker is needed
//   CREATE_ACCOUNT_RATE_LIMIT_ENABLED=false
//                                   CI retries a failed test twice, and every
//                                   attempt signs up again
//
//   pnpm test:playwright e2e/auth/simple-mode-email-verification.spec.ts \
//     --project=chromium
//   # with PLAYWRIGHT_BASE_URL=<simple-mode server> MAILPIT_URL=<its Mailpit>
//
// Run by .github/workflows/e2e-full-auth.yml (the matrix's simple row).

import { expect, test, type APIRequestContext } from '@playwright/test';

import {
  FRESH_CONTEXT,
  signIn,
  submitSignup,
  waitForAppReady,
  waitForPathname,
} from '../support/auth-journey';
import {
  MAILPIT_URL,
  extractLinks,
  isMailpitReachable,
  rebaseOnto,
  waitForMessage,
} from '../support/mailpit';

const PASSWORD = 'Simple-Verify-E2E-2026!';

interface BootstrapMe {
  authentication?: { mode?: string; autoverify?: boolean };
  authenticated?: boolean;
  cust?: { verified?: boolean } | null;
}

async function bootstrapMe(request: APIRequestContext): Promise<BootstrapMe> {
  const response = await request.get('/bootstrap/me');
  expect(response.ok(), 'GET /bootstrap/me').toBe(true);
  return (await response.json()) as BootstrapMe;
}

test.describe('Simple mode: verify an account from the emailed link (#4831)', () => {
  test.beforeAll(async () => {
    expect(
      await isMailpitReachable(),
      `Mailpit is not reachable at ${MAILPIT_URL}. This spec reads the real ` +
        'welcome email; set MAILPIT_URL to the mailbox the target server sends to.'
    ).toBe(true);
  });

  test('verifies the account on the first reveal', async ({ page, browser, baseURL }) => {
    const { authentication } = await bootstrapMe(page.request);
    expect(authentication?.mode, 'the target must run AUTHENTICATION_MODE=simple').toBe('simple');
    expect(authentication?.autoverify, 'the target must run AUTH_AUTOVERIFY=false').toBe(false);

    const { email } = await submitSignup(page, '/signup', {
      emailPrefix: 'simple-verify',
      password: PASSWORD,
    });

    const message = await waitForMessage(email);
    const links = extractLinks(message, '/secret/');
    expect(links, `the welcome email to ${email} should carry one /secret/ link`).toHaveLength(1);

    // A mail client opens the link: no cookies, no session, no shared tab.
    const context = await browser.newContext(FRESH_CONTEXT);
    try {
      const visitor = await context.newPage();
      await visitor.goto(rebaseOnto(links[0], baseURL!));
      await waitForAppReady(visitor);
      await expect(visitor.getByTestId('secret-confirmation-form')).toBeVisible();

      const [response] = await Promise.all([
        visitor.waitForResponse((r) => /\/secret\/[^/]+\/reveal$/.test(r.url())),
        visitor.getByTestId('secret-reveal-submit').click(),
      ]);
      expect(response.status(), `reveal failed: ${await response.text()}`).toBe(200);
      await expect(visitor.getByTestId('secret-content')).toHaveValue(/fortune cookie/);

      // Simple mode signs a pending account in too (it only resends the
      // email), so landing in the app proves nothing. The account record does.
      await visitor.goto('/signin');
      await waitForAppReady(visitor);
      await signIn(visitor, email, PASSWORD);
      await waitForPathname(visitor, /^\/(?!signin)/);
      const me = await bootstrapMe(visitor.request);
      expect(me.authenticated).toBe(true);
      expect(me.cust?.verified, 'the reveal should have verified the account').toBe(true);
    } finally {
      await context.close();
    }
  });
});
