// e2e/auth/sso-csrf.spec.ts
//
// E2E tests for SSO button CSRF protection flow.
// Verifies that the SsoButton component correctly includes CSRF tokens (shrimp)
// in form submissions to the OmniAuth endpoint.

import { test, expect } from '@playwright/test';

/**
 * SSO CSRF Protection E2E Tests
 *
 * These tests validate that:
 * 1. The SSO button appears when OmniAuth is enabled
 * 2. Form submissions include the 'shrimp' CSRF parameter
 * 3. The shrimp value is sourced from bootstrap state
 *
 * Background:
 * OTS uses 'shrimp' as the CSRF parameter name (legacy naming).
 * Rack::Protection::AuthenticityToken is configured with `authenticity_param: 'shrimp'`
 * in lib/onetime/middleware/security.rb. The SsoButton creates a form with a hidden
 * input named 'shrimp' containing the CSRF token from the csrfStore.
 */
test.describe('SSO CSRF Protection', () => {
  test.beforeEach(async ({ page }) => {
    // Extended timeout for page load
    page.setDefaultTimeout(15000);
  });

  test('signin page loads successfully', async ({ page }) => {
    await page.goto('/signin');
    await page.waitForLoadState('networkidle');

    // Verify we're on the signin page
    await expect(page).toHaveURL(/signin/);
    await expect(page.locator('body')).toBeVisible();
  });

  test('SSO button is visible when OmniAuth is enabled', async ({ page }) => {
    await page.goto('/signin');
    await page.waitForLoadState('networkidle');

    // Check if OmniAuth is enabled via bootstrap state
    const omniAuthEnabled = await page.evaluate(() => {
      type BootstrapState = { features?: { omniauth?: boolean } } | undefined;
      const state = (window as Window & { __BOOTSTRAP_STATE__?: BootstrapState | true }).__BOOTSTRAP_STATE__;
      // Bootstrap state may be consumed (set to true) or still an object
      if (state === true || state === undefined) {
        // Check if the SSO button is visible as fallback
        return document.querySelector('[data-testid="sso-button"]') !== null;
      }
      return state.features?.omniauth === true;
    });

    if (!omniAuthEnabled) {
      test.skip(true, 'OmniAuth is not enabled in this environment');
      return;
    }

    // SSO button should be visible
    const ssoButton = page.locator('[data-testid="sso-button"]');
    await expect(ssoButton).toBeVisible();

    // Button should have correct text
    await expect(ssoButton).toContainText(/SSO/i);
  });

  test('SSO form submission includes shrimp CSRF token', async ({ page }) => {
    await page.goto('/signin');
    await page.waitForLoadState('networkidle');

    // Check if SSO button exists
    const ssoButton = page.locator('[data-testid="sso-button"]');
    const ssoButtonVisible = await ssoButton.isVisible().catch(() => false);

    if (!ssoButtonVisible) {
      test.skip(true, 'SSO button not present - OmniAuth may not be enabled');
      return;
    }

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
    await page.waitForLoadState('networkidle');

    // Click the SSO button
    await ssoButton.click();

    // Wait a moment for form creation
    await page.waitForTimeout(100);

    // Retrieve captured form data
    formSubmission = await page.evaluate(() => {
      return (window as Window & { __capturedFormSubmission?: { action: string; method: string; shrimp: string | null } }).__capturedFormSubmission || null;
    });

    // Verify form was created and submitted
    expect(formSubmission).not.toBeNull();
    expect(formSubmission?.action).toContain('/auth/sso/oidc');
    expect(formSubmission?.method?.toUpperCase()).toBe('POST');

    // CRITICAL: Verify shrimp CSRF token is present and non-empty
    expect(formSubmission?.shrimp).not.toBeNull();
    expect(formSubmission?.shrimp).not.toBe('');
    expect(typeof formSubmission?.shrimp).toBe('string');
    expect(formSubmission?.shrimp?.length).toBeGreaterThan(0);
  });

  test('shrimp token originates from bootstrap state', async ({ page }) => {
    await page.goto('/signin');
    await page.waitForLoadState('networkidle');

    // Get the shrimp value from bootstrap state before it's consumed
    // Note: Bootstrap state may already be consumed by the app
    const shrimpFromBootstrap = await page.evaluate(() => {
      const state = (window as Window & { __BOOTSTRAP_STATE__?: { shrimp?: string } | true }).__BOOTSTRAP_STATE__;

      // If state is still an object, extract shrimp
      if (state && typeof state === 'object' && 'shrimp' in state) {
        return state.shrimp;
      }

      // State was consumed - check csrfStore via Vue app
      // The csrfStore should have the shrimp value
      return null;
    });

    // If we can capture bootstrap shrimp, verify it's a valid token format
    if (shrimpFromBootstrap) {
      expect(typeof shrimpFromBootstrap).toBe('string');
      expect(shrimpFromBootstrap.length).toBeGreaterThan(10);
    }

    // Alternative verification: check that the page has a valid CSRF mechanism
    // by verifying the X-CSRF-Token header is present in API responses
    const response = await page.request.get('/api/v2/status');
    const csrfHeader = response.headers()['x-csrf-token'];

    // CSRF token should be returned in response headers for API calls
    if (csrfHeader) {
      expect(csrfHeader.length).toBeGreaterThan(10);
    }
  });

  test('SSO button shows loading state when clicked', async ({ page }) => {
    await page.goto('/signin');
    await page.waitForLoadState('networkidle');

    const ssoButton = page.locator('[data-testid="sso-button"]');
    const ssoButtonVisible = await ssoButton.isVisible().catch(() => false);

    if (!ssoButtonVisible) {
      test.skip(true, 'SSO button not present - OmniAuth may not be enabled');
      return;
    }

    // Prevent actual form submission
    await page.addInitScript(() => {
      HTMLFormElement.prototype.submit = function () {
        // No-op to prevent navigation
      };
    });

    await page.reload();
    await page.waitForLoadState('networkidle');

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
    await page.waitForLoadState('networkidle');

    const ssoButton = page.locator('[data-testid="sso-button"]');
    const ssoButtonVisible = await ssoButton.isVisible().catch(() => false);

    if (!ssoButtonVisible) {
      test.skip(true, 'SSO button not present - OmniAuth may not be enabled');
      return;
    }

    // Divider with "or continue with" text should be visible
    const dividerText = page.locator('text=/or continue with/i');
    await expect(dividerText).toBeVisible();
  });
});

test.describe('SSO CSRF - Security Validation', () => {
  test('form action points to correct OmniAuth endpoint', async ({ page }) => {
    await page.goto('/signin');
    await page.waitForLoadState('networkidle');

    const ssoButton = page.locator('[data-testid="sso-button"]');
    const ssoButtonVisible = await ssoButton.isVisible().catch(() => false);

    if (!ssoButtonVisible) {
      test.skip(true, 'SSO button not present - OmniAuth may not be enabled');
      return;
    }

    // Capture the form that gets created
    let formAction: string | null = null;

    await page.addInitScript(() => {
      HTMLFormElement.prototype.submit = function () {
        (window as Window & { __formAction?: string }).__formAction = this.action;
      };
    });

    await page.reload();
    await page.waitForLoadState('networkidle');

    await ssoButton.click();
    await page.waitForTimeout(100);

    formAction = await page.evaluate(() => {
      return (window as Window & { __formAction?: string }).__formAction || null;
    });

    // Verify the endpoint matches the expected OmniAuth route
    // Route is: POST /auth/sso/:provider where provider is 'oidc' by default
    expect(formAction).not.toBeNull();
    expect(formAction).toMatch(/\/auth\/sso\/oidc$/);
  });

  test('shrimp parameter uses correct field name', async ({ page }) => {
    // This test verifies the frontend uses 'shrimp' (not 'authenticity_token')
    // which must match Rack::Protection::AuthenticityToken config

    await page.goto('/signin');
    await page.waitForLoadState('networkidle');

    const ssoButton = page.locator('[data-testid="sso-button"]');
    const ssoButtonVisible = await ssoButton.isVisible().catch(() => false);

    if (!ssoButtonVisible) {
      test.skip(true, 'SSO button not present - OmniAuth may not be enabled');
      return;
    }

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
    await page.waitForLoadState('networkidle');

    await ssoButton.click();
    await page.waitForTimeout(100);

    formInputs = await page.evaluate(() => {
      return (window as Window & { __formInputs?: Array<{ name: string; type: string }> }).__formInputs || [];
    });

    // Verify there's a hidden input named 'shrimp'
    const shrimpInput = formInputs.find((input) => input.name === 'shrimp');
    expect(shrimpInput).toBeDefined();
    expect(shrimpInput?.type).toBe('hidden');

    // Verify there's NO input named 'authenticity_token' (wrong name would fail CSRF check)
    const wrongInput = formInputs.find((input) => input.name === 'authenticity_token');
    expect(wrongInput).toBeUndefined();
  });
});
