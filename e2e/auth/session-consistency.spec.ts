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
//   - verification outage -> `unavailable` view; retry recovers with no page
//     load, and the server session was intact throughout             (#4460)
//   - a session ended outside the tab ends in a page load and /signin,
//     with one message                                       (#4464, #4465)
//   - a different account signing in elsewhere reloads the tab as that
//     account, never applying it in place                           (#4464)
//
// NOT covered here, and why:
//   - MFA completion: this lane runs without AUTH_MFA_ENABLED and has no TOTP
//     enrolment; see e2e/full/mfa-bootstrap-reactivity.spec.ts for the OTP
//     generation to reuse once the lane provisions it.
//
// Usage:
//   PLAYWRIGHT_BASE_URL=https://dev.onetime.dev MAILPIT_URL=https://dev.onetime.dev:8025 \
//     pnpm test:playwright e2e/auth/session-consistency.spec.ts --project=chromium

import { expect, test, type Page } from '@playwright/test';

import {
  FRESH_CONTEXT,
  signIn,
  submitSignup,
  verifyInFreshContext,
  waitForAppReady,
} from '../support/auth-journey';
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

test.describe('authenticated bootstrap consistency (#4456, #4459, #4460, #4464)', () => {
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
  /** A dashboard tab on Playwright's clock, already past the check interval. */
  async function staleDashboardTab(session: Page): Promise<Page> {
    const tab = await session.context().newPage();
    await tab.clock.install();
    await tab.goto('/dashboard');
    await waitForAppReady(tab);
    await tab.clock.setSystemTime(Date.now() + PAST_THE_CHECK_INTERVAL_MS);
    return tab;
  }

  test('a verification outage withholds the page, never signs out, and retry recovers without a reload', async ({
    page,
    browser,
    baseURL,
  }) => {
    const session = await signedInPage(page, browser, baseURL!);
    const tab = await staleDashboardTab(session);

    let loads = 0;
    tab.on('load', () => (loads += 1));
    const bootstrapRequests = recordBootstrapRequests(tab);
    await tab.route(`**${BOOTSTRAP_PATH}`, (route) =>
      route.fulfill({ status: 503, contentType: 'application/json', body: '{}' })
    );

    // One failure per backoff step; at the limit the protected page is withheld.
    await becomeVisible(tab);
    const unavailable = tab.getByTestId('verification-unavailable');
    await expect(async () => {
      await tab.clock.runFor(61_000);
      await expect(unavailable).toBeVisible({ timeout: 1_000 });
    }).toPass({ timeout: 30_000 });
    expect(bootstrapRequests.length).toBeGreaterThanOrEqual(3);

    // Not a sign-out: still on the page, and the server session is intact.
    expect(new URL(tab.url()).pathname).toBe('/dashboard');
    const account = await tab.context().request.get('/api/account/');
    expect(account.status()).toBe(200);

    // The server is back. Retry applies what it reports, in place.
    await tab.unroute(`**${BOOTSTRAP_PATH}`);
    const answered = tab.waitForResponse((r) => new URL(r.url()).pathname === BOOTSTRAP_PATH);
    await tab.getByTestId('verification-retry').click();
    expect((await answered).status()).toBe(200);

    await expect(unavailable).toBeHidden();
    expect(new URL(tab.url()).pathname).toBe('/dashboard');
    expect(loads).toBe(0);
  });

  test('a session ended outside the tab ends in a page load and /signin, with one message', async ({
    page,
    browser,
    baseURL,
  }) => {
    const session = await signedInPage(page, browser, baseURL!);
    const tab = await staleDashboardTab(session);

    // Logout "in another tab": same cookie jar, no involvement of this page.
    const loggedOut = await tab.context().request.get('/logout');
    expect(loggedOut.ok()).toBe(true);

    const reloaded = tab.waitForEvent('load');
    await becomeVisible(tab);
    await reloaded;
    await waitForAppReady(tab);

    // The server, not the client, moved the user: /dashboard is protected HTML.
    expect(new URL(tab.url()).pathname).toBe('/signin');
    await expect(tab.getByText(/your session has ended/i)).toHaveCount(1);
    // The message kind was consumed; the loop-bound marker is what remains.
    expect(await tab.evaluate(() => sessionStorage.getItem('ots_session_transition'))).toBeNull();
  });

  test('another account signing in elsewhere reloads the tab as that account', async ({
    page,
    browser,
    baseURL,
  }) => {
    const session = await signedInPage(page, browser, baseURL!);
    const tab = await staleDashboardTab(session);

    // Account B is created and verified in contexts of its own...
    const signupB = await browser.newContext({ ...FRESH_CONTEXT, baseURL: baseURL! });
    const { email: emailB } = await submitSignup(await signupB.newPage(), '/signup', SIGNUP_OPTIONS);
    const verifiedB = await verifyInFreshContext(browser, emailB, baseURL!);
    await verifiedB.context().close();
    await signupB.close();

    // ...then signs in from ANOTHER TAB of the first context, replacing A's session.
    const other = await tab.context().newPage();
    await tab.context().request.get('/logout');
    await other.goto('/signin');
    await signIn(other, emailB, SIGNUP_OPTIONS.password);
    await waitForAppReady(other);

    const accountA = await tab.evaluate(() => document.body.innerText);
    expect(accountA).not.toContain(emailB);

    const reloaded = tab.waitForEvent('load');
    await becomeVisible(tab);
    await reloaded;
    await waitForAppReady(tab);

    // Hydration started the new stream: B's page, nothing of A applied in place.
    expect(new URL(tab.url()).pathname).toBe('/dashboard');
    const hydrated = await tab.evaluate(
      () => (window as unknown as { __BOOTSTRAP_ME__?: { email?: string } }).__BOOTSTRAP_ME__?.email
    );
    expect(hydrated).toBe(emailB);
  });
});
