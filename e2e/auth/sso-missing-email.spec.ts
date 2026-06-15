// e2e/auth/sso-missing-email.spec.ts
//
// E2E tests for GitHub issue #3478:
//   "Unable to login with SSO/EntraID when the user doesn't have an email address."
//
// When an Entra/OIDC IdP returns NO email claim, the backend OmniAuth callback
// (apps/web/auth/config/hooks/omniauth.rb) redirects the browser to
// `/signin?auth_error=invalid_email`. Login.vue maps that code to the localized
// message `web.login.errors.invalid_email` and renders it in a red alert with
// role="alert".
//
// The REPORTED symptom was a "frozen loading screen" - which is what users saw
// when the error was NOT rendered (e.g. a stale frontend bundle lacking the
// handler). So the user-observable CONTRACT these tests guard is:
//   landing on `/signin?auth_error=invalid_email` MUST render the error alert
//   and a usable signin page - never a blank/stuck screen.
//
// These tests do NOT need a real IdP: the primary regression guards drive the
// signin route directly with the query param the backend would have set. A
// full IdP round-trip variant is included but gated behind SSO_NOEMAIL_E2E so
// it is skipped in CI (see the setup notes inside that test).

import { test, expect } from '@playwright/test';

// Exact English copy from locales/content/en/session-auth.json under
// `web.login.errors.invalid_email`. Asserted as a substring (locale-tolerant
// callers can swap base URL, but the default en build must show this text).
const INVALID_EMAIL_TEXT =
  'The email address from your identity provider is invalid. Please contact your administrator.';

/**
 * SSO Missing-Email Error Rendering (Issue #3478)
 *
 * Primary, CI-friendly regression guards. No real IdP is required: the backend
 * contract is that a failed SSO callback redirects to
 * `/signin?auth_error=invalid_email`, so we navigate there directly and assert
 * the front end renders the localized alert (rather than hanging).
 */
test.describe('SSO missing-email error (issue #3478)', () => {
  test.beforeEach(async ({ page }) => {
    // Extended timeout for page load, matching sibling SSO specs.
    page.setDefaultTimeout(15000);
  });

  test('renders invalid_email alert and a usable signin page (regression guard against the hang)', async ({
    page,
  }) => {
    await page.goto('/signin?auth_error=invalid_email');
    await page.waitForLoadState('networkidle');

    // Core guard: the error must surface in an accessible alert.
    const alert = page.getByRole('alert');
    await expect(alert).toBeVisible();
    await expect(alert).toContainText(INVALID_EMAIL_TEXT);

    // Core guard: the signin page must remain usable, i.e. NOT a frozen/blank
    // loading screen. The heading is rendered by AuthView and is the most
    // stable proof the SPA mounted and the route resolved.
    await expect(page.getByRole('heading', { name: /log in to your account/i })).toBeVisible();

    // Defense-in-depth: the page body has real content (not an empty shell).
    await expect(page.locator('body')).toBeVisible();
  });

  test('clears the auth_error query param after mount (router.replace), keeping the alert visible', async ({
    page,
  }) => {
    // Login.vue's onMounted() calls router.replace to strip auth_error so a
    // refresh does not re-show the error. We assert both halves of that
    // contract: the param is gone from the URL, but the already-rendered alert
    // persists (the message was captured into reactive state on mount).
    await page.goto('/signin?auth_error=invalid_email');
    await page.waitForLoadState('networkidle');

    // The alert is shown...
    await expect(page.getByRole('alert')).toContainText(INVALID_EMAIL_TEXT);

    // ...and the query param has been removed from the URL by router.replace.
    await expect
      .poll(() => new URL(page.url()).searchParams.get('auth_error'), {
        message: 'auth_error query param should be cleared by router.replace on mount',
        timeout: 5000,
      })
      .toBeNull();

    // The alert remains visible even after the param is cleared.
    await expect(page.getByRole('alert')).toContainText(INVALID_EMAIL_TEXT);
  });

  test('plain /signin (no auth_error) shows NO error alert', async ({ page }) => {
    // Contrast case: without the query param there must be no error alert, so a
    // healthy signin page is never confused with the error state.
    await page.goto('/signin');
    await page.waitForLoadState('networkidle');

    await expect(page.getByRole('alert')).toHaveCount(0);

    // Sanity: the page still rendered (it just has no error).
    await expect(page.getByRole('heading', { name: /log in to your account/i })).toBeVisible();
  });

  // Parameterized sibling-code check: invalid_email is wired exactly like the
  // other handled auth_error codes in Login.vue's authErrorMessages map. Each
  // must render an alert (and must not hang). This proves invalid_email is not
  // a special-cased one-off but part of the same render path.
  const SIBLING_ERROR_CODES = ['invalid_email', 'sso_failed', 'domain_not_allowed'] as const;

  for (const code of SIBLING_ERROR_CODES) {
    test(`auth_error=${code} renders a non-empty alert on a usable page`, async ({ page }) => {
      await page.goto(`/signin?auth_error=${code}`);
      await page.waitForLoadState('networkidle');

      const alert = page.getByRole('alert');
      await expect(alert).toBeVisible();
      // Localized text varies per code; assert the alert is non-empty rather
      // than hard-coding every string (invalid_email's exact text is asserted
      // in the dedicated tests above).
      await expect(alert).not.toBeEmpty();

      // The page is usable, not stuck.
      await expect(page.getByRole('heading', { name: /log in to your account/i })).toBeVisible();
    });
  }
});

/**
 * Full-flow reproduction variant (issue #3478) - GATED / SKIPPED IN CI.
 *
 * The real SSO round-trip cannot run in CI (no IdP), so this is gated behind
 * the SSO_NOEMAIL_E2E env flag and skipped when it is unset. When enabled, it
 * drives the actual SSO button and asserts the post-IdP landing reproduces the
 * bug surface: `/signin?auth_error=invalid_email` with the alert shown (and no
 * hang).
 *
 * ----------------------------------------------------------------------------
 * SSO SETUP REQUIRED FOR THIS TEST TO REPRODUCE THE FAILURE
 * ----------------------------------------------------------------------------
 * The whole point of #3478 is an IdP that authenticates a user but returns NO
 * email claim, so OmniAuth's `info.email` resolves to nil and the backend
 * redirects to `?auth_error=invalid_email`. To stage that with Microsoft Entra:
 *
 *   1. Microsoft Entra ID, using the V2.0 endpoint (this is what the
 *      `omniauth-entra-id` strategy uses). The v1.0 endpoint behaves
 *      differently around `upn`/`email` claims and will NOT reproduce reliably.
 *
 *   2. A test user with NO `mail` attribute - i.e. no mailbox / no license
 *      assigned - so the `email` claim is genuinely absent from the token.
 *      (A user who happens to have a mailbox WILL get an email claim and the
 *      bug will not reproduce.)
 *
 *   3. App registration token configuration with NO `email` and NO `upn`
 *      optional claims added. The v2.0 endpoint omits `upn` by default and
 *      emits `preferred_username` instead - which OTS does NOT use as an email
 *      source - so leaving these optional claims off ensures OmniAuth's
 *      `info.email` resolves to nil.
 *
 *   4. OTS environment:
 *        - AUTH_SSO_ENABLED=true
 *        - ENTRA_TENANT_ID / ENTRA_CLIENT_ID / ENTRA_CLIENT_SECRET all set
 *        - ALLOWED_SIGNUP_DOMAIN **MUST be unset**. If a signup-domain policy
 *          is configured, the `before_omniauth_create_account` hook
 *          short-circuits to `auth_error=domain_not_allowed` BEFORE it reaches
 *          the malformed/missing-email branch, so you would test the wrong
 *          code path.
 *
 *   Expected result: after authenticating as the no-email user, the browser
 *   lands on `/signin?auth_error=invalid_email` and the localized alert renders
 *   (and the page must NOT hang on a loading screen - that hang is the
 *   user-reported symptom #3478 is about).
 *
 *   CI-FRIENDLY STAND-IN: a cloud Entra tenant is not required to reproduce the
 *   full round-trip. A local OIDC IdP (Zitadel or Keycloak, per
 *   docs/authentication/omniauth-testing.md) configured with a user that has no
 *   email attribute is an equivalent way to drive `info.email == nil` and make
 *   the end-to-end flow land on `?auth_error=invalid_email`.
 * ----------------------------------------------------------------------------
 */
test.describe('SSO missing-email full round-trip (issue #3478, gated)', () => {
  test('IdP with no email claim lands on /signin?auth_error=invalid_email with the alert', async ({
    page,
  }) => {
    test.skip(
      !process.env.SSO_NOEMAIL_E2E,
      'Set SSO_NOEMAIL_E2E=1 with a no-email IdP user configured (see setup notes above) to run the full SSO round-trip.'
    );

    await page.goto('/signin');
    await page.waitForLoadState('networkidle');

    // Skip-guard consistent with sso-csrf.spec.ts: only meaningful when the SSO
    // button (OmniAuth) is actually enabled in this environment.
    const ssoButton = page.locator('[data-testid="sso-button"]');
    const ssoButtonVisible = await ssoButton.isVisible().catch(() => false);
    if (!ssoButtonVisible) {
      test.skip(true, 'SSO button not present - OmniAuth may not be enabled');
      return;
    }

    // Drive the real SSO flow. This navigates to the IdP, which (per the setup
    // notes) authenticates a user with no email claim and bounces back through
    // the OmniAuth callback to the signin page with the error code.
    await Promise.all([
      page.waitForURL(/\/signin\?.*auth_error=invalid_email/, { timeout: 30000 }),
      ssoButton.click(),
    ]);

    await page.waitForLoadState('networkidle');

    // Same user-observable contract as the CI-friendly guard: the alert renders
    // and the page is usable rather than frozen.
    const alert = page.getByRole('alert');
    await expect(alert).toBeVisible();
    await expect(alert).toContainText(INVALID_EMAIL_TEXT);
    await expect(page.getByRole('heading', { name: /log in to your account/i })).toBeVisible();
  });
});
