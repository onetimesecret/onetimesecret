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
//   - a session REVOKED from another device ends the same way    (#4459 AC5)
//   - a different account signing in elsewhere reloads the tab as that
//     account, never applying it in place                           (#4464)
//   - MFA completion: password -> mfa_pending -> TOTP -> authenticated, in
//     place, with no account data before the second factor     (#4459 AC5)
//
// The MFA scenario needs AUTH_MFA_ENABLED=true (the e2e-full-auth lane sets
// it) and skips itself where the server does not offer TOTP. It enrols its
// own second factor over the API; e2e/support/totp.ts generates the codes.
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
  waitForPathname,
} from '../support/auth-journey';
import { MAILPIT_URL, isMailpitReachable } from '../support/mailpit';
import { TOTP_STEP_SECONDS, totp } from '../support/totp';

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

/** Counts this page's /api/ requests. Attach BEFORE the navigation. */
function trackApiRequests(page: Page): { started: number; pending: number } {
  const counts = { started: 0, pending: 0 };
  const isApi = (url: string) => new URL(url).pathname.startsWith('/api/');
  page.on('request', (request) => {
    if (!isApi(request.url())) return;
    counts.started += 1;
    counts.pending += 1;
  });
  const settled = (request: { url(): string }) => {
    if (isApi(request.url())) counts.pending -= 1;
  };
  page.on('requestfinished', settled);
  page.on('requestfailed', settled);
  return counts;
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

/**
 * A key of the payload the server rendered into this document. NOT
 * window.__BOOTSTRAP_ME__: that is consumed at startup and reads `true` after.
 */
async function hydratedValue(page: Page, key: string): Promise<string | undefined> {
  return page.evaluate((name) => {
    const data = document.querySelector('script[data-window="__BOOTSTRAP_ME__"]')?.textContent;
    const value = data ? (JSON.parse(data) as Record<string, unknown>)[name] : undefined;
    return typeof value === 'string' ? value : undefined;
  }, key);
}

/** JSON + CSRF headers for an API call made with this page's cookie jar. */
async function apiHeaders(page: Page): Promise<Record<string, string>> {
  const me = await page.context().request.get(BOOTSTRAP_PATH);
  const { shrimp } = (await me.json()) as { shrimp: string };
  return { Accept: 'application/json', 'Content-Type': 'application/json', 'X-CSRF-Token': shrimp };
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
    return (await signedInAccount(page, browser, baseURL)).session;
  }

  /** signedInPage(), for the scenarios that sign the same account in again. */
  async function signedInAccount(
    page: Page,
    browser: Parameters<typeof verifyInFreshContext>[0],
    baseURL: string
  ): Promise<{ session: Page; email: string }> {
    const { email } = await submitSignup(page, '/signup', SIGNUP_OPTIONS);
    const verified = await verifyInFreshContext(browser, email, baseURL);
    await signIn(verified, email, SIGNUP_OPTIONS.password);
    // signIn() returns once the form is SUBMITTED. Leaving /signin is what
    // says the session exists; a tab opened before that is anonymous.
    await expect(verified).not.toHaveURL(/\/signin/, { timeout: 30_000 });
    await waitForAppReady(verified);
    return { session: verified, email };
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
    const inFlight = trackApiRequests(tab);
    await tab.clock.install();
    await tab.goto('/dashboard');
    await waitForAppReady(tab);
    // Let the dashboard's own fetches finish. One still in flight when the
    // session ends elsewhere is answered 401, and that rejection (not the
    // visibility trigger these scenarios are about) would start the refresh.
    await expect.poll(() => inFlight.started > 0 && inFlight.pending === 0).toBe(true);
    await nextTask(tab);
    expect(inFlight.pending).toBe(0);
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
    await expect(other).not.toHaveURL(/\/signin/, { timeout: 30_000 });
    await waitForAppReady(other);

    const accountA = await tab.evaluate(() => document.body.innerText);
    expect(accountA).not.toContain(emailB);

    const reloaded = tab.waitForEvent('load');
    await becomeVisible(tab);
    await reloaded;
    await waitForAppReady(tab);

    // Hydration started the new stream: B's page, nothing of A applied in place.
    expect(new URL(tab.url()).pathname).toBe('/dashboard');
    expect(await hydratedValue(tab, 'email')).toBe(emailB);
    // One transition, one message — and it names a replacement, not an ending.
    await expect(tab.getByText(/your sign-in changed in another tab/i)).toHaveCount(1);
  });

  test('a session revoked from another device ends in a page load and /signin', async ({
    page,
    browser,
    baseURL,
  }) => {
    const { session, email } = await signedInAccount(page, browser, baseURL!);
    const tab = await staleDashboardTab(session);

    // The same account on a second device, with a cookie jar of its own.
    const device = await browser.newContext({ ...FRESH_CONTEXT, baseURL: baseURL! });
    const devicePage = await device.newPage();
    await devicePage.goto('/signin');
    await signIn(devicePage, email, SIGNUP_OPTIONS.password);
    await expect(devicePage).not.toHaveURL(/\/signin/, { timeout: 30_000 });

    // It revokes every session but its own: the row behind `tab` is gone, the
    // cookie `tab` holds is untouched. Only the server knows it is over.
    const headers = await apiHeaders(devicePage);
    const listed = await device.request.get('/auth/active-sessions', { headers });
    expect(listed.status()).toBe(200);
    const { sessions } = (await listed.json()) as {
      sessions: { id: string; is_current: boolean }[];
    };
    const others = sessions.filter((entry) => !entry.is_current);
    expect(others.length).toBeGreaterThan(0);
    for (const other of others) {
      const removed = await device.request.delete(`/auth/active-sessions/${other.id}`, { headers });
      expect(removed.status()).toBe(200);
    }

    const reloaded = tab.waitForEvent('load');
    await becomeVisible(tab);
    await reloaded;
    await waitForAppReady(tab);

    expect(new URL(tab.url()).pathname).toBe('/signin');
    await expect(tab.getByText(/your session has ended/i)).toHaveCount(1);

    // The revoking device is unaffected.
    expect((await device.request.get('/api/account/', { headers })).status()).toBe(200);
    await device.close();
  });

  test('MFA completion moves mfa_pending to authenticated in place', async ({
    page,
    browser,
    baseURL,
  }) => {
    // Enrolment + Rodauth's one-use-per-interval throttle: see below.
    test.slow();

    const { session, email } = await signedInAccount(page, browser, baseURL!);

    // --- Enrol a TOTP second factor over the API -----------------------------
    const headers = await apiHeaders(session);
    const request = session.context().request;
    const offered = await request.post('/auth/otp-setup', { headers, data: {} });
    test.skip(offered.status() === 404, 'This server does not offer TOTP (AUTH_MFA_ENABLED).');
    // 422 is the documented first leg: it carries the secret to confirm.
    expect(offered.status()).toBe(422);
    const setup = (await offered.json()) as { otp_setup: string; otp_raw_secret: string };
    // Keys are HMAC'd (otp_keys_use_hmac?): the secret an authenticator holds,
    // and the server verifies against, is `otp_setup`. `otp_raw_secret` only
    // travels back so the server can re-derive it.
    const secret = setup.otp_setup;

    const enrolled = await request.post('/auth/otp-setup', {
      headers,
      data: {
        otp_code: totp(secret),
        otp_setup: setup.otp_setup,
        otp_raw_secret: setup.otp_raw_secret,
        password: SIGNUP_OPTIONS.password,
      },
    });
    expect(enrolled.status(), await enrolled.text()).toBe(200);
    const enrolledAt = Date.now();

    // --- Password: the server reports mfa_pending, and no account data -------
    await request.get('/logout');
    const tab = await session.context().newPage();
    await tab.goto('/signin');
    await signIn(tab, email, SIGNUP_OPTIONS.password);
    await waitForPathname(tab, '/mfa-verify');
    await expect(tab.getByTestId('mfa-otp-panel')).toBeVisible();

    const pending = await (await request.get(BOOTSTRAP_PATH)).json();
    expect(pending.auth_status).toBe('mfa_pending');
    expect(pending.authenticated).toBe(false);
    expect(pending.cust).toBeNull();
    expect(pending.email).toBeNull();
    expect(pending.snapshot_epoch).toMatch(/^[0-9a-f]{32}$/);

    // Rodauth accepts a key once per interval and counts enrolment as a use.
    const usableAt = enrolledAt + (TOTP_STEP_SECONDS + 1) * 1000;
    await tab.waitForTimeout(Math.max(0, usableAt - Date.now()));

    // --- Second factor: one auth-mutation refresh, applied in place ----------
    let loads = 0;
    tab.on('load', () => (loads += 1));
    const bootstrapRequests = recordBootstrapRequests(tab);

    await tab.getByTestId('otp-digit-1').click();
    await tab.keyboard.type(totp(secret));

    await expect(tab).not.toHaveURL(/\/mfa-verify/, { timeout: 30_000 });
    await waitForAppReady(tab);

    // An authorised transition (the tab asked for it): applied without a page
    // load and without a "session replaced" notice.
    expect(loads).toBe(0);
    expect(bootstrapRequests).toHaveLength(1);
    await expect(tab.getByTestId('stale-session-notice')).toHaveCount(0);
    await expect(tab.getByTestId('verification-unavailable')).toHaveCount(0);

    const completed = await (await request.get(BOOTSTRAP_PATH)).json();
    expect(completed.auth_status).toBe('authenticated');
    expect(completed.email).toBe(email);
    // Observed: Rodauth rotates the session id at the password step, not at
    // the second factor, so this is the SAME stream moving forward. Were that
    // to change, a new epoch is equally acceptable to the coordinator; an
    // older version on the same epoch never is.
    if (completed.snapshot_epoch === pending.snapshot_epoch) {
      expect(BigInt(completed.snapshot_version)).toBeGreaterThan(BigInt(pending.snapshot_version));
    }

    // And the client agrees with the server: a protected route renders.
    await tab.goto('/dashboard');
    await waitForAppReady(tab);
    expect(new URL(tab.url()).pathname).toBe('/dashboard');
  });
});
