// e2e/global.setup.ts

/**
 * Auth setup project (e2e/docs/e2e-remediation-plan.md, Phase 2.1)
 *
 * Obtains an authenticated session once per run and saves it to
 * STORAGE_STATE (e2e/.auth/user.json, gitignored). The `full` and
 * `full-billing` projects declare `dependencies: ['setup']` and consume the
 * saved session via `storageState`, so their tests start already signed in.
 *
 * Strategy: register via the real /signup flow, then sign in via /signin —
 * exercising the same product code paths users hit, with no backend seam.
 * Requirements on the target server:
 *  - signup enabled (site.authentication.signup, default on)
 *  - a new account can sign in without an email round-trip. What provides
 *    that depends on the auth mode:
 *      simple mode: AUTH_AUTOVERIFY=true (site.authentication.autoverify),
 *        so the customer is created verified.
 *      full mode: AUTH_VERIFY_ACCOUNT_ENABLED=false, so Rodauth's
 *        verify_account feature is off and the account is created open.
 *        AUTH_AUTOVERIFY has no effect on full-mode signups.
 *    The CI workflow sets both on the container; see .github/workflows/e2e.yml.
 *
 * Registration is safe to repeat (a Playwright retry after the account was
 * created, or a re-run against the same server), but the two modes answer an
 * existing login differently:
 *   simple mode: the same success response as for a new account
 *     (email-enumeration prevention), so the SPA lands on /check-email.
 *   full mode: 400 with the generic "Unable to create account" error
 *     (apps/web/auth/config/overrides/duplicate_signup.rb), so the signup
 *     form shows its error alert.
 * The setup accepts either outcome and goes on to sign in. Sign-in is the
 * guard: it passes only if the account exists and the password matches. A
 * signup error is recorded as a `signup-error` annotation, so a sign-in
 * failure that follows it names the signup error that caused it.
 *
 * Fallback (documented in the plan, not currently needed): seed directly via
 *   docker exec <container> ... Onetime::Customer.create!(...)
 *
 * Readiness: waits on `html[data-app-ready="true"]` (set in src/main.ts
 * after mount + brand theme application + router.isReady()) — never
 * `networkidle` or `waitForTimeout`.
 */

import { expect, test as setup } from '@playwright/test';

import { STORAGE_STATE } from './playwright.config';

const TEST_USER_EMAIL = process.env.TEST_USER_EMAIL ?? '';
const TEST_USER_PASSWORD = process.env.TEST_USER_PASSWORD ?? '';

setup('register and authenticate test user', async ({ page }) => {
  if (!TEST_USER_EMAIL || !TEST_USER_PASSWORD) {
    throw new Error(
      'TEST_USER_EMAIL and TEST_USER_PASSWORD must be set to run the ' +
        'authenticated suites (full/, full-billing/). ' +
        'CI generates ephemeral credentials in .github/workflows/e2e.yml; ' +
        'locally, export both env vars before running.'
    );
  }

  // ---------------------------------------------------------------------
  // Register via the signup form. A new account is created sign-in-able
  // (see the requirements above); an existing one answers success in simple
  // mode and the generic signup error in full mode. Both continue to signin.
  // ---------------------------------------------------------------------
  await page.goto('/signup');
  await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

  await expect(page.getByTestId('signup-form')).toBeVisible();
  await page.getByTestId('signup-email-input').fill(TEST_USER_EMAIL);
  await page.getByTestId('signup-password-input').fill(TEST_USER_PASSWORD);
  await page.getByTestId('signup-terms-checkbox').check();
  await page.getByTestId('signup-submit').click();

  // On success the SPA navigates to /check-email — NOT /signin. It changed in
  // 16c9012c42 (2026-07-03): the sign-in form is unusable until an account is
  // verified, so signup now lands on a "check your email" confirmation page.
  // This step waited on /signin for weeks afterwards and timed out every run,
  // which took the whole `full` / `full-billing` dependency chain down with it.
  //
  // Waiting for one of the two known outcomes is what keeps that from
  // happening silently again: if signup starts landing somewhere else, THIS
  // assertion fails, instead of the failure surfacing as an unexplained
  // timeout on the sign-in form below. The budget matches the navigation
  // timeout the old waitForURL used: signup hashes the password server-side.
  const checkEmailView = page.getByTestId('check-email-view');
  const signupError = page.getByTestId('signup-error-message');
  await expect(checkEmailView.or(signupError)).toBeVisible({ timeout: 15_000 });

  // Settled: the error alert only renders on the signup page, and a failed
  // signup does not navigate, so exactly one of the two is on screen.
  if (await signupError.isVisible()) {
    setup.info().annotations.push({
      type: 'signup-error',
      description: (await signupError.innerText()).trim(),
    });
  } else {
    await expect(page).toHaveURL(/\/check-email/);
  }

  // No email round-trip to wait on: the target server creates accounts
  // sign-in-able (requirements above), so go straight to the sign-in form.
  await page.goto('/signin');
  await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

  // ---------------------------------------------------------------------
  // Sign in. Default deployments (no passwordless methods) render
  // SignInForm directly; passwordless-first deployments render a tabbed
  // form (PasswordlessFirstSignIn) where the password panel sits behind a
  // "Password" tab and uses different test ids.
  // ---------------------------------------------------------------------
  const signinForm = page.getByTestId('signin-form');
  const passwordTab = page.getByRole('tab', { name: /password/i });
  await expect(signinForm.or(passwordTab).first()).toBeVisible();

  if (await passwordTab.isVisible()) {
    // Passwordless-first variant (magic links / WebAuthn enabled)
    await passwordTab.click();
    await page.getByTestId('password-email-input').fill(TEST_USER_EMAIL);
    await page.getByTestId('password-input').fill(TEST_USER_PASSWORD);
    await page.getByTestId('password-submit').click();
  } else {
    // Password-only variant (CI container default)
    await page.getByTestId('signin-email-input').fill(TEST_USER_EMAIL);
    await page.getByTestId('signin-password-input').fill(TEST_USER_PASSWORD);
    await page.getByTestId('signin-submit').click();
  }

  // Successful login navigates away from /signin (router.push('/') then the
  // post-auth redirect). Failed logins stay on /signin with an inline error,
  // which this assertion surfaces via timeout + screenshot/trace.
  await expect(page).not.toHaveURL(/\/signin/, { timeout: 30000 });
  await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

  // Verify the session server-side before persisting it: /bootstrap/me
  // reflects the authenticated state for the cookies this page holds.
  const me = await page.request.get('/bootstrap/me');
  expect(me.ok()).toBe(true);
  expect((await me.json()).authenticated).toBe(true);

  await page.context().storageState({ path: STORAGE_STATE });
});
