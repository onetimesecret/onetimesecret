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
 *  - autoverify enabled (AUTH_AUTOVERIFY=true) so the new account is
 *    immediately sign-in-able without an email round-trip. The CI workflow
 *    sets this on the container; see .github/workflows/e2e.yml.
 * Registration is idempotent: the backend intentionally returns the same
 * success response for new and already-existing accounts (email-enumeration
 * prevention), so re-running against the same server is safe.
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
  // Register via the signup form. With autoverify enabled the account is
  // created verified; if the account already exists the backend still
  // responds with success (enumeration prevention) and we proceed to signin.
  // ---------------------------------------------------------------------
  await page.goto('/signup');
  await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

  await expect(page.getByTestId('signup-form')).toBeVisible();
  await page.getByTestId('signup-email-input').fill(TEST_USER_EMAIL);
  await page.getByTestId('signup-password-input').fill(TEST_USER_PASSWORD);
  await page.getByTestId('signup-terms-checkbox').check();
  await page.getByTestId('signup-submit').click();

  // On success the SPA navigates to /signin (useAuth.signup()).
  await page.waitForURL(/\/signin/);

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
