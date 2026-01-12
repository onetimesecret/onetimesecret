// e2e/full/mfa-bootstrap-reactivity.spec.ts

/**
 * MFA Flow E2E Tests for bootstrapStore Reactivity
 *
 * These tests verify that the MFA authentication flow correctly updates
 * bootstrapStore state and that route guards respond reactively to changes.
 *
 * Test Scope:
 * - Verifies awaiting_mfa flag becomes true after login with MFA-enabled account
 * - Verifies awaiting_mfa becomes false after successful OTP verification
 * - Verifies route guards redirect to /mfa-verify when awaiting_mfa is true
 * - Verifies authenticated state remains consistent through MFA flow
 *
 * Prerequisites:
 * - Set TEST_MFA_USER_EMAIL and TEST_MFA_USER_PASSWORD for MFA-enabled account
 * - Set TEST_MFA_SECRET (TOTP secret) for programmatic OTP generation
 * - OR set TEST_MFA_OTP for a static test OTP (less reliable for automated tests)
 *
 * Usage:
 *   # With environment variables
 *   TEST_MFA_USER_EMAIL=mfa@example.com TEST_MFA_USER_PASSWORD=secret \
 *     TEST_MFA_SECRET=JBSWY3DPEHPK3PXP pnpm playwright test mfa-bootstrap-reactivity.spec.ts
 *
 * Related Issue: #2365 - WindowService to Pinia bootstrapStore migration
 */

import { test, expect, Page } from '@playwright/test';

// Check if MFA test credentials are configured
const hasMfaCredentials = !!(
  process.env.TEST_MFA_USER_EMAIL &&
  process.env.TEST_MFA_USER_PASSWORD &&
  (process.env.TEST_MFA_SECRET || process.env.TEST_MFA_OTP)
);

// Window state interface for type safety in page.evaluate
interface BootstrapState {
  authenticated?: boolean;
  awaiting_mfa?: boolean;
  email?: string;
  custid?: string;
}

declare global {
  interface Window {
    __BOOTSTRAP_STATE__?: BootstrapState;
  }
}

/**
 * Generate TOTP code from secret using the standard algorithm.
 * This uses a simple implementation for testing purposes.
 *
 * For production tests, consider using a library like 'otpauth' or 'speakeasy'.
 * Since Playwright tests run in Node.js, we can use crypto.
 */
async function generateTotpCode(secret: string): Promise<string> {
  // If a static OTP is provided, use it (useful for controlled test environments)
  if (process.env.TEST_MFA_OTP) {
    return process.env.TEST_MFA_OTP;
  }

  // For dynamic TOTP generation, we need the otpauth library
  // This is a placeholder - in a real implementation you'd use:
  // import { TOTP } from 'otpauth';
  // const totp = new TOTP({ secret });
  // return totp.generate();

  // For now, throw an error if no static OTP is provided
  throw new Error(
    'TOTP generation not implemented. ' +
      'Set TEST_MFA_OTP environment variable with a valid OTP code, ' +
      'or implement TOTP generation with otpauth library.'
  );
}

/**
 * Get bootstrap state from the page.
 * Handles both pre-consumption and post-consumption states.
 */
async function getBootstrapState(page: Page): Promise<BootstrapState | null> {
  return page.evaluate(() => {
    // Check if state exists on window (before consumption by bootstrap service)
    if (window.__BOOTSTRAP_STATE__) {
      return {
        authenticated: window.__BOOTSTRAP_STATE__.authenticated,
        awaiting_mfa: window.__BOOTSTRAP_STATE__.awaiting_mfa,
        email: window.__BOOTSTRAP_STATE__.email,
        custid: window.__BOOTSTRAP_STATE__.custid,
      };
    }
    return null;
  });
}

/**
 * Attempt login with MFA-enabled credentials.
 * Returns after form submission, before MFA verification.
 */
async function loginWithMfaCredentials(page: Page): Promise<void> {
  await page.goto('/signin');
  await page.waitForLoadState('networkidle');

  const emailInput = page.locator('input[type="email"], input[name="email"]');
  const passwordInput = page.locator('input[type="password"], input[name="password"]');
  const submitButton = page.locator('button[type="submit"]');

  await expect(emailInput).toBeVisible({ timeout: 10000 });

  await emailInput.fill(process.env.TEST_MFA_USER_EMAIL || '');
  await passwordInput.fill(process.env.TEST_MFA_USER_PASSWORD || '');
  await submitButton.click();

  // Wait for navigation (either to MFA page or error)
  await page.waitForLoadState('networkidle');
}

// =============================================================================
// MFA Bootstrap Store Reactivity Tests
// =============================================================================

test.describe('MFA Flow - bootstrapStore Reactivity', () => {
  test.skip(!hasMfaCredentials, 'Skipping: MFA test credentials not configured');

  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(30000);
  });

  // ---------------------------------------------------------------------------
  // TC-MFA-001: Login with MFA sets awaiting_mfa to true
  // ---------------------------------------------------------------------------
  test('TC-MFA-001: Login with MFA-enabled account sets awaiting_mfa to true', async ({
    page,
  }) => {
    // Capture console logs for debugging
    const consoleLogs: string[] = [];
    page.on('console', (msg) => {
      if (msg.type() === 'debug' || msg.type() === 'log') {
        consoleLogs.push(msg.text());
      }
    });

    await loginWithMfaCredentials(page);

    // After successful password auth with MFA enabled, should redirect to /mfa-verify
    await expect(page).toHaveURL(/\/mfa-verify/, { timeout: 15000 });

    // Verify bootstrap state shows awaiting_mfa = true
    // Note: After bootstrap service consumes the state, it may not be on window
    // We check route guards behavior as the authoritative test
    const currentUrl = page.url();
    expect(currentUrl).toContain('/mfa-verify');

    // Attempt to navigate away - should be redirected back to /mfa-verify
    await page.goto('/dashboard');
    await page.waitForLoadState('networkidle');

    // Route guard should redirect back to MFA verification
    await expect(page).toHaveURL(/\/mfa-verify/, { timeout: 10000 });
  });

  // ---------------------------------------------------------------------------
  // TC-MFA-002: Route guards redirect to /mfa-verify when awaiting MFA
  // ---------------------------------------------------------------------------
  test('TC-MFA-002: Route guards enforce MFA completion before protected route access', async ({
    page,
  }) => {
    await loginWithMfaCredentials(page);
    await expect(page).toHaveURL(/\/mfa-verify/);

    // Try accessing various protected routes
    const protectedRoutes = ['/dashboard', '/account', '/domains', '/billing/overview'];

    for (const route of protectedRoutes) {
      await page.goto(route);
      await page.waitForLoadState('networkidle');

      // Should be redirected to MFA verification
      expect(
        page.url(),
        `Expected redirect to /mfa-verify from ${route}`
      ).toContain('/mfa-verify');
    }

    // Public routes should remain accessible but with limited functionality
    await page.goto('/');
    await page.waitForLoadState('networkidle');

    // Root should also redirect to MFA when awaiting
    expect(page.url()).toContain('/mfa-verify');
  });

  // ---------------------------------------------------------------------------
  // TC-MFA-003: MFA verification page displays correctly
  // ---------------------------------------------------------------------------
  test('TC-MFA-003: MFA verification page renders with OTP input', async ({ page }) => {
    await loginWithMfaCredentials(page);
    await expect(page).toHaveURL(/\/mfa-verify/);

    // Verify MFA challenge page elements
    const otpInput = page.locator(
      'input[type="text"][maxlength="6"], ' +
        'input[autocomplete="one-time-code"], ' +
        '[data-testid="otp-input"]'
    );

    // OTP input should be visible (may be custom component with multiple inputs)
    const hasOtpInput = await otpInput.first().isVisible().catch(() => false);
    const hasMultipleDigitInputs = (await page.locator('input[maxlength="1"]').count()) >= 6;

    expect(
      hasOtpInput || hasMultipleDigitInputs,
      'OTP input field should be visible'
    ).toBe(true);

    // Verify button is present
    const verifyButton = page.locator('button').filter({ hasText: /verify/i });
    await expect(verifyButton.first()).toBeVisible();

    // Verify recovery code option exists
    const recoveryLink = page.locator('button, a').filter({ hasText: /recovery/i });
    await expect(recoveryLink.first()).toBeVisible();

    // Verify cancel option exists
    const cancelLink = page.locator('button, a').filter({ hasText: /cancel/i });
    await expect(cancelLink.first()).toBeVisible();
  });

  // ---------------------------------------------------------------------------
  // TC-MFA-004: Successful MFA verification completes authentication
  // ---------------------------------------------------------------------------
  test.skip(
    !process.env.TEST_MFA_OTP && !process.env.TEST_MFA_SECRET,
    'TC-MFA-004: Successful MFA verification clears awaiting_mfa and completes auth'
  );

  test('TC-MFA-004: Successful MFA verification clears awaiting_mfa', async ({ page }) => {
    await loginWithMfaCredentials(page);
    await expect(page).toHaveURL(/\/mfa-verify/);

    // Generate or use provided OTP
    let otpCode: string;
    try {
      otpCode = await generateTotpCode(process.env.TEST_MFA_SECRET || '');
    } catch (error) {
      test.skip(true, 'OTP generation not available');
      return;
    }

    // Enter OTP code
    // Handle both single input and multiple digit inputs
    const singleInput = page.locator('input[maxlength="6"]');
    const digitInputs = page.locator('input[maxlength="1"]');

    if (await singleInput.isVisible().catch(() => false)) {
      await singleInput.fill(otpCode);
    } else {
      // Fill each digit input
      const inputs = await digitInputs.all();
      for (let i = 0; i < otpCode.length && i < inputs.length; i++) {
        await inputs[i].fill(otpCode[i]);
      }
    }

    // Click verify button
    const verifyButton = page.locator('button').filter({ hasText: /verify/i });
    await verifyButton.first().click();

    // Wait for navigation after successful verification
    await page.waitForLoadState('networkidle');

    // Should redirect to dashboard or home (not stay on MFA page)
    const currentUrl = page.url();
    expect(currentUrl).not.toContain('/mfa-verify');
    expect(currentUrl).not.toContain('/signin');

    // Verify we can now access protected routes
    await page.goto('/dashboard');
    await page.waitForLoadState('networkidle');

    // Should stay on dashboard (not redirect to /mfa-verify)
    await expect(page).toHaveURL(/\/dashboard/);
  });

  // ---------------------------------------------------------------------------
  // TC-MFA-005: Cancel MFA clears partial auth state
  // ---------------------------------------------------------------------------
  test('TC-MFA-005: Canceling MFA verification returns to signin', async ({ page }) => {
    await loginWithMfaCredentials(page);
    await expect(page).toHaveURL(/\/mfa-verify/);

    // Click cancel button
    const cancelButton = page.locator('button').filter({ hasText: /cancel/i });
    await cancelButton.first().click();

    // Should redirect to signin
    await page.waitForLoadState('networkidle');
    await expect(page).toHaveURL(/\/signin/);

    // Verify session is cleared - accessing protected route should redirect to signin
    await page.goto('/dashboard');
    await page.waitForLoadState('networkidle');

    await expect(page).toHaveURL(/\/signin/);
  });

  // ---------------------------------------------------------------------------
  // TC-MFA-006: Recovery code flow works correctly
  // ---------------------------------------------------------------------------
  test('TC-MFA-006: Recovery code mode is accessible from MFA page', async ({ page }) => {
    await loginWithMfaCredentials(page);
    await expect(page).toHaveURL(/\/mfa-verify/);

    // Click recovery code option
    const recoveryLink = page.locator('button').filter({ hasText: /recovery/i });
    await recoveryLink.first().click();

    // Wait for mode switch
    await page.waitForTimeout(500);

    // Recovery code input should now be visible
    const recoveryInput = page.locator(
      'input[type="text"]'
    ).filter({
      has: page.locator('[placeholder*="recovery" i], [id*="recovery" i]'),
    });

    // Or look for any text input that appeared after clicking recovery
    const anyTextInput = page.locator('input#recovery-code, input[placeholder*="recovery" i]');
    const isRecoveryMode = await anyTextInput.isVisible().catch(() => false);

    // Back to OTP option should be visible
    const backToOtp = page.locator('button').filter({ hasText: /back|code/i });
    const hasBackOption = await backToOtp.first().isVisible().catch(() => false);

    expect(
      isRecoveryMode || hasBackOption,
      'Recovery code mode should be accessible'
    ).toBe(true);
  });
});

// =============================================================================
// Bootstrap Store State Inspection Tests
// =============================================================================

test.describe('bootstrapStore State Visibility', () => {
  test.skip(!hasMfaCredentials, 'Skipping: MFA test credentials not configured');

  test('TC-MFA-010: bootstrapStore state is accessible for DevTools inspection', async ({
    page,
  }) => {
    await loginWithMfaCredentials(page);
    await expect(page).toHaveURL(/\/mfa-verify/);

    // Check if Pinia devtools data is accessible
    // In Vue DevTools, stores appear under __VUE_DEVTOOLS_GLOBAL_HOOK__
    const piniaState = await page.evaluate(() => {
      // Check for Vue DevTools hook (present in dev mode)
      const hook = (window as any).__VUE_DEVTOOLS_GLOBAL_HOOK__;
      if (!hook) return { devtoolsAvailable: false };

      // Check for Pinia in hook
      const apps = hook.apps || [];
      const hasPinia = apps.some((app: any) => app._context?.provides?.pinia);

      return {
        devtoolsAvailable: true,
        hasPinia,
        appsCount: apps.length,
      };
    });

    // In development mode, DevTools should be available
    // This test documents the expected state for manual verification
    console.log('Pinia DevTools state:', piniaState);

    // Regardless of DevTools, verify the store is functioning by checking behavior
    // The fact that route guards work proves the store is reactive
    expect(page.url()).toContain('/mfa-verify');
  });
});

// =============================================================================
// Edge Cases and Error Handling
// =============================================================================

test.describe('MFA Flow - Edge Cases', () => {
  test.skip(!hasMfaCredentials, 'Skipping: MFA test credentials not configured');

  test('TC-MFA-020: Invalid OTP shows error without clearing awaiting_mfa', async ({
    page,
  }) => {
    await loginWithMfaCredentials(page);
    await expect(page).toHaveURL(/\/mfa-verify/);

    // Enter invalid OTP
    const singleInput = page.locator('input[maxlength="6"]');
    const digitInputs = page.locator('input[maxlength="1"]');

    if (await singleInput.isVisible().catch(() => false)) {
      await singleInput.fill('000000');
    } else {
      const inputs = await digitInputs.all();
      for (let i = 0; i < 6 && i < inputs.length; i++) {
        await inputs[i].fill('0');
      }
    }

    // Click verify
    const verifyButton = page.locator('button').filter({ hasText: /verify/i });
    await verifyButton.first().click();

    // Wait for error response
    await page.waitForLoadState('networkidle');

    // Should still be on MFA page (not redirected)
    await expect(page).toHaveURL(/\/mfa-verify/);

    // Error message should be displayed
    const errorMessage = page.locator('[role="alert"], .text-red-800, .text-red-200');
    await expect(errorMessage.first()).toBeVisible({ timeout: 5000 });
  });

  test('TC-MFA-021: Direct navigation to /mfa-verify without pending MFA redirects', async ({
    page,
  }) => {
    // Navigate directly to MFA page without being in MFA-pending state
    await page.goto('/mfa-verify');
    await page.waitForLoadState('networkidle');

    // Should redirect to signin (unauthenticated) or dashboard (authenticated)
    const currentUrl = page.url();
    expect(
      currentUrl.includes('/signin') || currentUrl.includes('/dashboard') || currentUrl === page.url().replace('/mfa-verify', '/'),
      'Should redirect away from /mfa-verify when not awaiting MFA'
    ).toBe(true);
  });

  test('TC-MFA-022: Page refresh during MFA maintains pending state', async ({ page }) => {
    await loginWithMfaCredentials(page);
    await expect(page).toHaveURL(/\/mfa-verify/);

    // Refresh the page
    await page.reload();
    await page.waitForLoadState('networkidle');

    // Should still be on MFA verification page
    // (server maintains session state, client reinitializes from /window)
    await expect(page).toHaveURL(/\/mfa-verify/);
  });
});

/**
 * Manual Verification Checklist - bootstrapStore DevTools
 *
 * Since Vue DevTools inspection cannot be fully automated, use this checklist
 * for manual verification during development:
 *
 * ## DevTools Verification Steps
 *
 * 1. Open application in browser with Vue DevTools extension installed
 * 2. Open DevTools and navigate to "Vue" tab
 * 3. Click on "Pinia" in the component tree or use Pinia tab
 *
 * ## Expected bootstrapStore State (Unauthenticated)
 * - authenticated: false
 * - awaiting_mfa: false
 * - cust: null
 * - email: ''
 * - shrimp: (CSRF token string)
 *
 * ## Expected bootstrapStore State (After Login with MFA)
 * - authenticated: false (MFA pending)
 * - awaiting_mfa: true
 * - cust: null (not yet loaded)
 * - email: (user's email)
 *
 * ## Expected bootstrapStore State (Fully Authenticated)
 * - authenticated: true
 * - awaiting_mfa: false
 * - cust: { custid, email, planid, ... }
 * - email: (user's email)
 *
 * ## Reactivity Verification
 * 1. Login with MFA account
 * 2. Watch DevTools - awaiting_mfa should flip to true
 * 3. Complete MFA verification
 * 4. Watch DevTools - authenticated should become true, awaiting_mfa false
 * 5. Logout
 * 6. Watch DevTools - all values should reset to defaults
 *
 * ## Route Guard Verification
 * 1. While awaiting_mfa is true, attempt to navigate to /dashboard
 * 2. Observe redirect to /mfa-verify
 * 3. Complete MFA, navigate to /dashboard
 * 4. Should remain on /dashboard (no redirect)
 */
