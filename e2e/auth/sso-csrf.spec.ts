// e2e/auth/sso-csrf.spec.ts
//
// E2E tests for SSO button form submission flow.
// Verifies that the SsoButton component correctly submits forms to the OmniAuth
// endpoint. Note: SSO routes skip Rack::Protection CSRF validation - CSRF
// protection is handled by OAuth's state parameter during the IdP redirect flow.
// The shrimp token is still included for form consistency but is not validated.

import { test, expect } from '@playwright/test';

import { ssoSigninEnabled } from '../support/env';

/**
 * SSO Form Submission E2E Tests
 *
 * These tests validate that:
 * 1. The SSO button appears when OmniAuth is enabled
 * 2. Form submissions include the 'shrimp' field (for form consistency)
 * 3. The form targets the correct OmniAuth endpoint
 *
 * Background:
 * SSO routes (/auth/sso/*) skip Rack::Protection CSRF validation because OAuth's
 * state parameter provides CSRF protection during the IdP redirect flow. The shrimp
 * field is still included for consistency with other forms but is not validated
 * server-side for SSO requests.
 *
 * Environment gate (plan Phase 2.4): whether the signin page renders the
 * SSO button depends on the target server's OmniAuth configuration — a
 * deployment decision, not something to probe at runtime. The SSO describes
 * are gated once on E2E_SSO_UI (e2e/support/env.ts); when the gate is on,
 * the button MUST be present or the tests fail.
 */
test.describe('Signin page', () => {
  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
  });

  test('signin page loads successfully', async ({ page }) => {
    await page.goto('/signin');
    await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

    // Verify we're on the signin page
    await expect(page).toHaveURL(/signin/);
    await expect(page.locator('body')).toBeVisible();
  });

  test('CSRF token is available to the signin page', async ({ page }) => {
    await page.goto('/signin');
    await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

    // Get the shrimp value from bootstrap state before it's consumed
    // Note: Bootstrap state may already be consumed by the app
    const shrimpFromBootstrap = await page.evaluate(() => {
      const state = (window as Window & { __BOOTSTRAP_ME__?: { shrimp?: string } | true }).__BOOTSTRAP_ME__;

      // If state is still an object, extract shrimp
      if (state && typeof state === 'object' && 'shrimp' in state) {
        return state.shrimp;
      }

      // State was consumed by the app
      return null;
    });

    // Alternative source: the X-CSRF-Token header on API responses
    const response = await page.request.get('/api/v2/status');
    const csrfHeader = response.headers()['x-csrf-token'];

    // At least one CSRF mechanism must expose a plausible token. The old
    // version of this test only checked whichever source happened to be
    // present and passed vacuously when both were missing.
    const token = shrimpFromBootstrap || csrfHeader;
    expect(token, 'no CSRF token via bootstrap state or X-CSRF-Token header').toBeTruthy();
    expect(String(token).length).toBeGreaterThan(10);
  });
});

test.describe('SSO Form Submission', () => {
  test.skip(
    !ssoSigninEnabled,
    'SSO signin requires OmniAuth on the target server — set E2E_SSO_UI=true (see e2e/support/env.ts)'
  );

  test.beforeEach(async ({ page }) => {
    // Extended timeout for page load
    page.setDefaultTimeout(15000);
  });

  test('SSO button is visible when OmniAuth is enabled', async ({ page }) => {
    await page.goto('/signin');
    await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

    // SSO button must be visible on an SSO-enabled deployment
    const ssoButton = page.locator('[data-testid="sso-button"]');
    await expect(ssoButton).toBeVisible();

    // Button should have correct text
    await expect(ssoButton).toContainText(/SSO/i);
  });

  test('SSO form submission includes shrimp field', async ({ page }) => {
    await page.goto('/signin');
    await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

    const ssoButton = page.locator('[data-testid="sso-button"]');
    await expect(ssoButton).toBeVisible();

    // Intercept form submissions to verify CSRF token
    let formSubmission: { action: string; method: string; shrimp: string | null } | null = null;

    await page.addInitScript(() => {
      // Override form.submit to capture form data
      HTMLFormElement.prototype.submit = function () {
        const form = this;
        const shrimpInput = form.querySelector('input[name="shrimp"]') as HTMLInputElement | null;

        // Store form data for verification
        (window as Window & { __capturedFormSubmission?: unknown }).__capturedFormSubmission = {
          action: form.action,
          method: form.method,
          shrimp: shrimpInput?.value || null,
        };

        // Don't actually submit (would navigate away)
        // Return undefined to prevent navigation
      };
    });

    // Reload page to apply the script
    await page.reload();
    await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

    // Click the SSO button
    await ssoButton.click();

    // Wait deterministically for the patched form.submit() to record the
    // submission on window (the click handler builds the form async)
    await page.waitForFunction(() => '__capturedFormSubmission' in window);

    // Retrieve captured form data
    formSubmission = await page.evaluate(() => {
      return (window as Window & { __capturedFormSubmission?: { action: string; method: string; shrimp: string | null } }).__capturedFormSubmission || null;
    });

    // Verify form was created and submitted
    expect(formSubmission).not.toBeNull();
    expect(formSubmission?.action).toContain('/auth/sso/oidc');
    expect(formSubmission?.method?.toUpperCase()).toBe('POST');

    // Verify shrimp field is present (for form consistency, not validated for SSO)
    expect(formSubmission?.shrimp).not.toBeNull();
    expect(formSubmission?.shrimp).not.toBe('');
    expect(typeof formSubmission?.shrimp).toBe('string');
    expect(formSubmission?.shrimp?.length).toBeGreaterThan(0);
  });

  test('SSO button shows loading state when clicked', async ({ page }) => {
    await page.goto('/signin');
    await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

    const ssoButton = page.locator('[data-testid="sso-button"]');
    await expect(ssoButton).toBeVisible();

    // Prevent actual form submission
    await page.addInitScript(() => {
      HTMLFormElement.prototype.submit = function () {
        // No-op to prevent navigation
      };
    });

    await page.reload();
    await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

    // Button should not be disabled initially
    await expect(ssoButton).not.toBeDisabled();

    // Click and verify loading state
    await ssoButton.click();

    // Button should become disabled during loading
    await expect(ssoButton).toBeDisabled();

    // Loading text should appear
    await expect(ssoButton).toContainText(/signing in/i);
  });

  test('SSO divider appears when OmniAuth is enabled', async ({ page }) => {
    await page.goto('/signin');
    await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

    const ssoButton = page.locator('[data-testid="sso-button"]');
    await expect(ssoButton).toBeVisible();

    // Divider with "or continue with" text should be visible
    const dividerText = page.locator('text=/or continue with/i');
    await expect(dividerText).toBeVisible();
  });
});

test.describe('SSO Form - Structure Validation', () => {
  test.skip(
    !ssoSigninEnabled,
    'SSO signin requires OmniAuth on the target server — set E2E_SSO_UI=true (see e2e/support/env.ts)'
  );

  test('form action points to correct OmniAuth endpoint', async ({ page }) => {
    await page.goto('/signin');
    await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

    const ssoButton = page.locator('[data-testid="sso-button"]');
    await expect(ssoButton).toBeVisible();

    // Capture the form that gets created
    let formAction: string | null = null;

    await page.addInitScript(() => {
      HTMLFormElement.prototype.submit = function () {
        (window as Window & { __formAction?: string }).__formAction = this.action;
      };
    });

    await page.reload();
    await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

    await ssoButton.click();
    // Wait deterministically for the patched form.submit() to record the
    // form action on window
    await page.waitForFunction(() => '__formAction' in window);

    formAction = await page.evaluate(() => {
      return (window as Window & { __formAction?: string }).__formAction || null;
    });

    // Verify the endpoint matches the expected OmniAuth route
    // Route is: POST /auth/sso/:provider where provider is 'oidc' by default
    expect(formAction).not.toBeNull();
    expect(formAction).toMatch(/\/auth\/sso\/oidc$/);
  });

  test('shrimp field uses correct name attribute', async ({ page }) => {
    // This test verifies the frontend uses 'shrimp' (not 'authenticity_token')
    // for consistency with other forms in the app

    await page.goto('/signin');
    await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

    const ssoButton = page.locator('[data-testid="sso-button"]');
    await expect(ssoButton).toBeVisible();

    // Capture all form inputs
    let formInputs: Array<{ name: string; type: string }> = [];

    await page.addInitScript(() => {
      HTMLFormElement.prototype.submit = function () {
        const inputs = Array.from(this.querySelectorAll('input')) as HTMLInputElement[];
        (window as Window & { __formInputs?: Array<{ name: string; type: string }> }).__formInputs = inputs.map((el: HTMLInputElement) => ({
          name: el.name,
          type: el.type,
        }));
      };
    });

    await page.reload();
    await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

    await ssoButton.click();
    // Wait deterministically for the patched form.submit() to record the
    // form inputs on window
    await page.waitForFunction(() => '__formInputs' in window);

    formInputs = await page.evaluate(() => {
      return (window as Window & { __formInputs?: Array<{ name: string; type: string }> }).__formInputs || [];
    });

    // Verify there's a hidden input named 'shrimp'
    const shrimpInput = formInputs.find((input) => input.name === 'shrimp');
    expect(shrimpInput).toBeDefined();
    expect(shrimpInput?.type).toBe('hidden');

    // Verify there's NO input named 'authenticity_token' (using wrong name for consistency)
    const wrongInput = formInputs.find((input) => input.name === 'authenticity_token');
    expect(wrongInput).toBeUndefined();
  });
});
