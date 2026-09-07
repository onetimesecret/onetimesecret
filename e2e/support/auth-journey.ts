// e2e/support/auth-journey.ts
//
// Shared drivers for the real "signup → check-email → emailed verification
// link → signin" journey. Extracted from
// e2e/auth/signup-redirect-preservation.spec.ts (issue #4305) so that every
// spec exercising this journey — the #4305 redirect spec, the #4306 plan
// intent spec — drives the exact same forms the exact same way. A drifted
// copy of these helpers is how one spec quietly starts testing a different
// signup surface than the other.
//
// Environment contract (the target server must actually SEND the email):
//   AUTHENTICATION_MODE=full        Rodauth is mounted
//   AUTH_AUTOVERIFY=false           accounts are NOT verified on creation
//   RACK_ENV != test                etc/auth.yaml force-disables
//                                   verify_account whenever RACK_ENV=test
//   EMAILER_MODE=smtp + SMTP_HOST/SMTP_PORT → Mailpit
//   a running job worker            mail is ENQUEUED by the web process and
//                                   delivered by EmailWorker, not inline
//   CREATE_ACCOUNT_RATE_LIMIT_ENABLED=false
//                                   these suites sign up several times per
//                                   run; the default cap is 10 per MASKED
//                                   client IP per hour with a 1h lockout

import { expect, type Browser, type Page } from '@playwright/test';

import { rebaseOnto, uniqueEmailAddress, waitForVerificationUrl } from './mailpit';

/**
 * A truly empty browser context. Spelled out rather than relying on the
 * project's lack of storageState, because the requirement under test is
 * "empty storage" — an implicit default is not an assertion.
 */
export const FRESH_CONTEXT = { storageState: { cookies: [], origins: [] } };

/**
 * Readiness flag set in src/main.ts after mount + router.isReady().
 *
 * Given a longer budget than the suite's 5s `expect.timeout` on purpose: this
 * is a page-load gate, not a behavioural assertion, and journey specs open a
 * FRESH browser context per journey — each one pays a cold, uncached asset
 * fetch. 30s matches the actionTimeout the chromium project already uses for
 * exactly this reason ("extra time for container responses").
 */
export async function waitForAppReady(page: Page): Promise<void> {
  await expect(page.locator('html[data-app-ready="true"]')).toBeAttached({
    timeout: 30_000,
  });
}

/**
 * Waits until the browser's PATHNAME satisfies `expected`.
 *
 * Not a glob and not a regex against the whole URL, deliberately. Both of
 * those match the entire URL string, and the URL a post-auth journey travels
 * FROM is `/signin?redirect=<destination>` — which happily satisfies a
 * glob/regex for the destination while the browser is still sitting on the
 * sign-in page. A wait that is already satisfied at the moment it is called
 * is not a wait; it silently converts "the redirect never happened" into a
 * confusing assertion failure one line later. Comparing the parsed pathname
 * cannot be fooled by the query.
 */
export async function waitForPathname(
  page: Page,
  expected: string | RegExp
): Promise<void> {
  await page.waitForURL((url) =>
    typeof expected === 'string' ? url.pathname === expected : expected.test(url.pathname)
  );
}

/**
 * Signs in on a page that is already sitting on /signin.
 *
 * Handles both sign-in surfaces the way e2e/global.setup.ts does: the plain
 * SignInForm, and the tabbed PasswordlessFirstSignIn rendered when magic
 * links or WebAuthn are enabled on the target.
 */
export async function signIn(page: Page, email: string, password: string): Promise<void> {
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
 * The request body is captured because it is where these journeys can fail
 * SILENTLY: the backend stores redirect/plan-intent values from the
 * create-account request params, so if the SPA omits them from the POST,
 * nothing is ever stored and every later step degrades to "no destination" —
 * which looks like a working app, just one that forgot where you were going.
 */
export async function submitSignup(
  page: Page,
  signupUrl: string,
  options: { emailPrefix: string; password: string }
): Promise<{ email: string; requestBody: Record<string, unknown> | null }> {
  const email = uniqueEmailAddress(options.emailPrefix);
  let requestBody: Record<string, unknown> | null = null;

  // An observer, NOT a route handler. page.route() would put Playwright in
  // the path of the request and let a spec REWRITE the body — which is
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
  await page.getByTestId('signup-password-input').fill(options.password);
  await page.getByTestId('signup-terms-checkbox').check();
  const [response] = await Promise.all([
    page.waitForResponse((r) => r.url().includes('/auth/create-account')),
    page.getByTestId('signup-submit').click(),
  ]);

  // Name the rate limiter explicitly. Without this the failure is a bare
  // waitForURL timeout, and the cause (the journey suites create several
  // accounts per run against a default cap of 10 signups/hour per MASKED
  // client IP, with a 1h lockout) is invisible in the trace.
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
 * The fresh context is the whole point of these journeys: verification links
 * get opened from mail clients, i.e. from a browser that has never seen the
 * signup tab. If a destination only survives because the ORIGINAL tab
 * remembered it (history state, sessionStorage, a live session cookie), the
 * feature does not work for real users.
 *
 * The caller owns closing the context — returning it keeps the failure
 * screenshots/traces attached to a live page instead of a torn-down one.
 */
export async function verifyInFreshContext(
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
