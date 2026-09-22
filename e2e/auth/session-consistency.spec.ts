// e2e/auth/session-consistency.spec.ts
//
// #4456 / #4459: the authenticated half of the bootstrap-consistency browser
// tests. Needs a full-auth stack with Mailpit, exactly like
// signup-redirect-preservation.spec.ts (see its header for the recipe).
//
// Covered here:
//   - a valid hydrated AUTHENTICATED page makes zero startup requests (#4456)
//   - returning to a stale visible tab makes exactly one request      (#4459)
//   - returning to a fresh tab makes none                             (#4459)
//
// NOT covered here yet, and why:
//   - "refresh after idle/revocation ends in /signin": the coordinator applies
//     the anonymous snapshot and clears account data, but moving the user is
//     ADR-046's "session ended -> forced page load", which lands with
//     #4464/#4465. The scenario belongs next to that code.
//   - account switching: same dependency (session replaced -> forced load).
//   - MFA completion: this lane runs without AUTH_MFA_ENABLED and has no TOTP
//     enrolment; see e2e/full/mfa-bootstrap-reactivity.spec.ts for the OTP
//     generation to reuse once the lane provisions it.
//
// Usage:
//   PLAYWRIGHT_BASE_URL=https://dev.onetime.dev MAILPIT_URL=https://dev.onetime.dev:8025 \
//     pnpm test:playwright e2e/auth/session-consistency.spec.ts --project=chromium

import { expect, test, type Page } from '@playwright/test';

import { signIn, submitSignup, verifyInFreshContext, waitForAppReady } from '../support/auth-journey';
import { MAILPIT_URL, isMailpitReachable } from '../support/mailpit';

const BOOTSTRAP_PATH = '/bootstrap/me';
const SIGNUP_OPTIONS = { emailPrefix: 'consistency-4459', password: 'E2eConsistency!4459pw' };

/** The passive verification interval is 15 min; anything past it is stale. */
const PAST_THE_CHECK_INTERVAL_MS = 16 * 60 * 1000;

/** Attach BEFORE the navigation under test, or the startup request is missed. */
function recordBootstrapRequests(page: Page): string[] {
  const seen: string[] = [];
  page.on('request', (request) => {
    if (new URL(request.url()).pathname === BOOTSTRAP_PATH) seen.push(request.url());
  });
  return seen;
}

/**
 * Lets the page run what is already queued. The visibility handler calls the
 * coordinator synchronously and the request goes out within microtasks, so
 * after a round trip to the page a request it was going to make has been
 * issued. NOT setTimeout: this tab runs on Playwright's installed clock,
 * where a timer never fires unless the test advances it.
 */
async function nextTask(page: Page): Promise<void> {
  await page.evaluate(() => Promise.resolve());
  await page.evaluate(() => Promise.resolve());
}

/** Tells the page it has just become visible again. */
async function becomeVisible(page: Page): Promise<void> {
  await page.evaluate(() => {
    Object.defineProperty(document, 'visibilityState', { value: 'visible', configurable: true });
    document.dispatchEvent(new Event('visibilitychange'));
  });
}

test.describe('authenticated bootstrap consistency (#4456, #4459)', () => {
  test.beforeEach(async () => {
    test.skip(
      !(await isMailpitReachable()),
      `Mailpit is not reachable at ${MAILPIT_URL}; these scenarios need a verified account.`
    );
  });

  /** Signs up, verifies and signs in. Returns a page holding a real session. */
  async function signedInPage(
    page: Page,
    browser: Parameters<typeof verifyInFreshContext>[0],
    baseURL: string
  ): Promise<Page> {
    const { email } = await submitSignup(page, '/signup', SIGNUP_OPTIONS);
    const verified = await verifyInFreshContext(browser, email, baseURL);
    await signIn(verified, email, SIGNUP_OPTIONS.password);
    await waitForAppReady(verified);
    return verified;
  }

  test('a hydrated authenticated page makes zero startup requests', async ({
    page,
    browser,
    baseURL,
  }) => {
    const session = await signedInPage(page, browser, baseURL!);

    // A fresh load of a protected page in the SAME context: the cookie is
    // sent, the server hydrates an authenticated snapshot, nothing is fetched.
    const fresh = await session.context().newPage();
    const bootstrapRequests = recordBootstrapRequests(fresh);

    await fresh.goto('/dashboard');
    await waitForAppReady(fresh);

    expect(new URL(fresh.url()).pathname).toBe('/dashboard');
    expect(bootstrapRequests).toEqual([]);
  });

  test('returning to a stale visible tab makes exactly one request', async ({
    page,
    browser,
    baseURL,
  }) => {
    const session = await signedInPage(page, browser, baseURL!);
    const tab = await session.context().newPage();

    // Install the clock before load so the app's timers use it. setSystemTime
    // moves Date.now() WITHOUT firing timers, so the 15-minute interval cannot
    // be what makes the request: only the visibility trigger can.
    await tab.clock.install();
    await tab.goto('/dashboard');
    await waitForAppReady(tab);

    const bootstrapRequests = recordBootstrapRequests(tab);
    await tab.clock.setSystemTime(Date.now() + PAST_THE_CHECK_INTERVAL_MS);

    // Twice in quick succession: equivalent requests are deduplicated.
    const answered = tab.waitForResponse((r) => new URL(r.url()).pathname === BOOTSTRAP_PATH);
    await becomeVisible(tab);
    await becomeVisible(tab);
    expect((await answered).status()).toBe(200);

    expect(bootstrapRequests).toHaveLength(1);
    // Still signed in, still on the page: recovery needed no reload.
    expect(new URL(tab.url()).pathname).toBe('/dashboard');

    // Now fresh again: another return to the tab asks nothing.
    await becomeVisible(tab);
    await nextTask(tab);
    expect(bootstrapRequests).toHaveLength(1);
  });
});
