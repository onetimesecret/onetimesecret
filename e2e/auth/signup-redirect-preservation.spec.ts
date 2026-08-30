// e2e/auth/signup-redirect-preservation.spec.ts
//
// E2E for issue #4305: the destination a user was heading to when they hit
// the signup wall must still be waiting for them after they verify their
// email and sign in.
//
// ─────────────────────────────────────────────────────────────────────────────
// THE JOURNEY, AND WHY IT NEEDS A BROWSER
// ─────────────────────────────────────────────────────────────────────────────
//
//   /signup?redirect=/account/settings/security
//     → submit → /check-email
//     → verification email (real SMTP → Mailpit)
//     → open the link IN A FRESH BROWSER CONTEXT
//     → /signin?redirect=/account/settings/security
//     → sign in → /account/settings/security
//
// Step 4 is the whole point. Unit and integration tests can assert that a
// hook stores a value and another hook returns it, but they cannot show that
// the destination survives a browser that has never seen the signup tab —
// which is the normal case, because verification links get opened from a mail
// client. If the destination only survives because the ORIGINAL tab
// remembered it (history state, sessionStorage, a live session cookie), the
// feature does not work for real users. A brand-new context with empty
// storage is the only honest way to state that requirement.
//
// ─────────────────────────────────────────────────────────────────────────────
// PROJECT / ENVIRONMENT
// ─────────────────────────────────────────────────────────────────────────────
//
// Runs in the `chromium` project (e2e/all + e2e/auth): no `setup` dependency
// and no storageState, which is exactly right here — every context this spec
// touches must start unauthenticated, including the first one.
//
// The target server must be able to actually SEND the verification email:
//   AUTHENTICATION_MODE=full        Rodauth is mounted
//   AUTH_AUTOVERIFY=false           accounts are NOT verified on creation
//   RACK_ENV != test                etc/auth.yaml:79 force-disables
//                                   verify_account whenever RACK_ENV=test
//   EMAILER_MODE=smtp + SMTP_HOST/SMTP_PORT → Mailpit
//   a running job worker            mail is ENQUEUED by the web process and
//                                   delivered by EmailWorker, not inline
//   CREATE_ACCOUNT_RATE_LIMIT_ENABLED=false
//                                   this file signs up 4 times per run and the
//                                   default cap is 10 per MASKED client IP per
//                                   hour, with a 1h lockout — so the second
//                                   run of the day trips it and every later
//                                   one stays tripped
//
//   pnpm test:playwright e2e/auth/signup-redirect-preservation.spec.ts \
//     --project=chromium
//   # with PLAYWRIGHT_BASE_URL=https://dev.onetime.dev
//   #      MAILPIT_URL=https://dev.onetime.dev:8025
//
// Mailpit reachability is asserted in beforeAll rather than skipped on: a
// silent skip here would turn "the feature is broken" into a green run.

import { expect, test, type Browser, type Page } from '@playwright/test';

import {
  MAILPIT_URL,
  isMailpitReachable,
  rebaseOnto,
  uniqueEmailAddress,
  waitForVerificationUrl,
} from '../support/mailpit';

/**
 * Password used for every account this spec creates. Satisfies the strict
 * password_requirements ruleset so the spec behaves identically on a target
 * that leaves AUTH_PASSWORD_REQUIREMENTS_ENABLED at its default (on).
 */
const PASSWORD = 'E2eRedirect!4305pw';

/**
 * A truly empty browser context. Spelled out rather than relying on the
 * project's lack of storageState, because the requirement under test is
 * "empty storage" — an implicit default is not an assertion.
 */
const FRESH_CONTEXT = { storageState: { cookies: [], origins: [] } };

/** The internal destination for the simple case: exists, and requires auth. */
const SIMPLE_TARGET = '/account/settings/security';

/**
 * The internal destination for the query+hash case.
 *
 * Deliberately a real, auth-gated route (Active Sessions) rather than the
 * issue's `/secret/abc?view=raw#content` sketch: /secret/:key is PUBLIC, so a
 * redirect to it proves nothing about surviving the auth wall, and an
 * arbitrary key lands on a "secret not found" page whose URL is not stable to
 * assert on. The query key and fragment are what matter, and they ride on any
 * path equally well.
 */
const RICH_TARGET = '/account/settings/security/sessions?filter=active#recent';

test.beforeAll(async () => {
  expect(
    await isMailpitReachable(),
    `Mailpit is not reachable at ${MAILPIT_URL}. The verification-link steps ` +
      'cannot run without it. Start it (podman compose -f ' +
      'docker/compose/docker-compose.mailpit.yml up -d) or point MAILPIT_URL ' +
      'at a running instance.'
  ).toBe(true);
});

/**
 * Readiness flag set in src/main.ts after mount + router.isReady().
 *
 * Given a longer budget than the suite's 5s `expect.timeout` on purpose: this
 * is a page-load gate, not a behavioural assertion, and this spec opens a
 * FRESH browser context per journey — each one pays a cold, uncached asset
 * fetch. 30s matches the actionTimeout the chromium project already uses for
 * exactly this reason ("extra time for container responses").
 */
async function waitForAppReady(page: Page): Promise<void> {
  await expect(page.locator('html[data-app-ready="true"]')).toBeAttached({
    timeout: 30_000,
  });
}

/**
 * Waits until the browser's PATHNAME is exactly `pathname`.
 *
 * Not a glob and not a regex, deliberately. Both of those match against the
 * whole URL string, and the URL we are travelling FROM is
 * `/signin?redirect=/account/settings/security` — which happily satisfies
 * `**​/account/settings/security` and `/\/account\/settings\/security/` while
 * the browser is still sitting on the sign-in page. A wait that is already
 * satisfied at the moment it is called is not a wait; it silently converts
 * "the redirect never happened" into a confusing assertion failure one line
 * later. Comparing the parsed pathname cannot be fooled by the query.
 */
async function waitForPathname(page: Page, pathname: string): Promise<void> {
  await page.waitForURL((url) => url.pathname === pathname);
}

/**
 * Signs in on a page that is already sitting on /signin.
 *
 * Handles both sign-in surfaces the way e2e/global.setup.ts does: the plain
 * SignInForm, and the tabbed PasswordlessFirstSignIn rendered when magic
 * links or WebAuthn are enabled on the target.
 */
async function signIn(page: Page, email: string, password: string): Promise<void> {
  const signinForm = page.getByTestId('signin-form');
  const passwordTab = page.getByRole('tab', { name: /password/i });
  await expect(signinForm.or(passwordTab).first()).toBeVisible();

  if (await passwordTab.isVisible()) {
    await passwordTab.click();
    await page.getByTestId('password-email-input').fill(email);
    await page.getByTestId('password-input').fill(password);
    await page.getByTestId('password-submit').click();
  } else {
    await page.getByTestId('signin-email-input').fill(email);
    await page.getByTestId('signin-password-input').fill(password);
    await page.getByTestId('signin-submit').click();
  }
}

/**
 * Runs signup through the real form and returns the address used, plus the
 * body the SPA actually POSTed to /auth/create-account.
 *
 * The request body is captured because it is where this journey can fail
 * SILENTLY: the backend stores the redirect from `request.params['redirect']`
 * at after_create_account, so if the SPA omits it from the POST, nothing is
 * ever stored and every later step degrades to "no destination" — which looks
 * like a working app, just one that forgot where you were going.
 */
async function submitSignup(
  page: Page,
  signupUrl: string
): Promise<{ email: string; requestBody: Record<string, unknown> | null }> {
  const email = uniqueEmailAddress('redirect-4305');
  let requestBody: Record<string, unknown> | null = null;

  // An observer, NOT a route handler. page.route() would put Playwright in
  // the path of the request and let this spec REWRITE the body — which is
  // exactly what it must not do: the point is to record what the product
  // sends, and a handler that "helpfully" completes the payload turns a real
  // gap into a green test. Reading off the event stream cannot lie.
  page.on('request', (request) => {
    if (request.method() === 'POST' && request.url().includes('/auth/create-account')) {
      requestBody = request.postDataJSON() ?? null;
    }
  });

  await page.goto(signupUrl);
  await waitForAppReady(page);

  await expect(page.getByTestId('signup-form')).toBeVisible();
  await page.getByTestId('signup-email-input').fill(email);
  await page.getByTestId('signup-password-input').fill(PASSWORD);
  await page.getByTestId('signup-terms-checkbox').check();
  const [response] = await Promise.all([
    page.waitForResponse((r) => r.url().includes('/auth/create-account')),
    page.getByTestId('signup-submit').click(),
  ]);

  // Name the rate limiter explicitly. Without this the failure is a bare
  // waitForURL timeout, and the cause (this suite creates 4 accounts per run
  // against a default cap of 10 signups/hour per MASKED client IP, with a 1h
  // lockout) is invisible in the trace.
  expect(
    response.status(),
    response.status() === 429
      ? 'POST /auth/create-account was rate-limited. The suite needs ' +
          'CREATE_ACCOUNT_RATE_LIMIT_ENABLED=false on the target, or a wait ' +
          'for the 1h lockout to expire.'
      : `POST /auth/create-account failed: ${await response.text()}`
  ).toBe(200);

  // Since 16c9012c42 signup lands on /check-email, NOT /signin: the sign-in
  // form is unusable until the account is verified.
  await page.waitForURL(/\/check-email/);
  await expect(page.getByTestId('check-email-view')).toBeVisible();

  return { email, requestBody };
}

/**
 * Opens the emailed verification link in a brand-new context and returns the
 * page, parked wherever the verify flow decided to send it.
 *
 * The caller owns closing the context — returning it keeps the failure
 * screenshots/traces attached to a live page instead of a torn-down one.
 */
async function verifyInFreshContext(
  browser: Browser,
  email: string,
  baseURL: string
): Promise<Page> {
  const emailedUrl = await waitForVerificationUrl(email);

  // The link is minted from the app's configured HOST, which need not be the
  // origin Playwright is driving. Re-base the origin only; the key lives in
  // the query and must not be touched.
  const verificationUrl = rebaseOnto(emailedUrl, baseURL);

  const context = await browser.newContext(FRESH_CONTEXT);
  const page = await context.newPage();

  await page.goto(verificationUrl);
  await waitForAppReady(page);

  return page;
}

test.describe('Signup redirect preservation (issue #4305)', () => {
  // Signup + async mail delivery + verify + signin is a long journey; the
  // 60s suite default is not enough headroom for the mail poll.
  test.slow();

  test('a plain internal target survives verification in a fresh browser', async ({
    browser,
    baseURL,
    page,
  }) => {
    const { email, requestBody } = await submitSignup(
      page,
      `/signup?redirect=${encodeURIComponent(SIMPLE_TARGET)}`
    );

    // The destination has to reach the SERVER at signup — that is what makes
    // it survive a browser that never saw this tab.
    expect(
      requestBody,
      'the SPA sent no body to /auth/create-account'
    ).not.toBeNull();
    expect(
      requestBody?.redirect,
      'POST /auth/create-account must carry `redirect` — after_create_account ' +
        'reads request.params[\'redirect\'] and stores it on the Customer. ' +
        'Without it nothing is persisted and the destination is lost.'
    ).toBe(SIMPLE_TARGET);

    const verifyPage = await verifyInFreshContext(browser, email, baseURL!);

    try {
      // The verify-account response carried the stored destination and the SPA
      // appended it to the sign-in URL.
      await verifyPage.waitForURL(/\/signin\?/);
      expect(new URL(verifyPage.url()).searchParams.get('redirect')).toBe(SIMPLE_TARGET);

      await signIn(verifyPage, email, PASSWORD);

      await waitForPathname(verifyPage, SIMPLE_TARGET);
      await waitForAppReady(verifyPage);
    } finally {
      await verifyPage.context().close();
    }
  });

  test('query string and fragment survive the whole journey intact', async ({
    browser,
    baseURL,
    page,
  }) => {
    const { email, requestBody } = await submitSignup(
      page,
      `/signup?redirect=${encodeURIComponent(RICH_TARGET)}`
    );

    expect(
      requestBody?.redirect,
      'POST /auth/create-account must carry the full `redirect`, query and fragment included'
    ).toBe(RICH_TARGET);

    const verifyPage = await verifyInFreshContext(browser, email, baseURL!);

    try {
      await verifyPage.waitForURL(/\/signin\?/);
      expect(new URL(verifyPage.url()).searchParams.get('redirect')).toBe(RICH_TARGET);

      await signIn(verifyPage, email, PASSWORD);

      await waitForPathname(verifyPage, '/account/settings/security/sessions');

      // Asserted component-by-component: a whole-URL regex would pass on a
      // near miss, and the near misses here are the interesting failures —
      // vue-router's `{ path }` form silently drops both of these.
      const landed = new URL(verifyPage.url());
      expect(landed.search).toBe('?filter=active');
      expect(landed.hash).toBe('#recent');
      await waitForAppReady(verifyPage);
    } finally {
      await verifyPage.context().close();
    }
  });

  /**
   * Negative cases. Both values are open-redirect attempts, rejected by the
   * SPA before the POST (so the create-account body carries no redirect at
   * all) AND re-validated server-side at capture and again at verify-time
   * read. This test pins the end-to-end OUTCOME — the journey ends where a
   * journey with no redirect at all would, the app's own root — not which
   * layer catches the value.
   *
   * `//evil.example` is the one a naive `startsWith('/')` check waves
   * through — it is a protocol-relative URL, not a path.
   */
  for (const hostile of ['https://attacker.example', '//evil.example']) {
    test(`an external redirect (${hostile}) never leaves the app`, async ({
      browser,
      baseURL,
      page,
    }) => {
      const { email } = await submitSignup(
        page,
        `/signup?redirect=${encodeURIComponent(hostile)}`
      );

      const verifyPage = await verifyInFreshContext(browser, email, baseURL!);

      try {
        await verifyPage.waitForURL(/\/signin/);

        // Nothing hostile may be echoed back into the sign-in URL.
        expect(new URL(verifyPage.url()).searchParams.get('redirect')).toBeNull();

        await signIn(verifyPage, email, PASSWORD);

        await expect(verifyPage).not.toHaveURL(/\/signin/, { timeout: 30_000 });
        await waitForAppReady(verifyPage);

        const landed = new URL(verifyPage.url());
        expect(landed.origin, 'navigated off-origin').toBe(new URL(baseURL!).origin);
        expect(landed.pathname).toMatch(/^\/(dashboard)?$/);
        expect(verifyPage.url()).not.toContain('attacker.example');
        expect(verifyPage.url()).not.toContain('evil.example');
      } finally {
        await verifyPage.context().close();
      }
    });
  }
});
