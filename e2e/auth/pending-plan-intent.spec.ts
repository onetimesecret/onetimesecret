// e2e/auth/pending-plan-intent.spec.ts
//
// E2E Tests for Issue #3126: Pending Plan Intent Flow
//
// Tests the flow where unauthenticated users:
// 1. Visit a pricing deep link (/billing/plans/identity_plus_v1/yearly)
// 2. Get redirected to signup with product/interval query params
// 3. Complete signup (verification email sent)
// 4. Click verification link
// 5. Get redirected to the original plan page
//
// The backend persists plan intent during signup and restores it after
// email verification via Customer.pending_plan_intent with 24h TTL.
//
// Prerequisites:
// - Application running locally or PLAYWRIGHT_BASE_URL set
// - Plans API returning valid plan data
// - Billing feature enabled
//
// Note: Full verification flow requires email simulation. These tests verify
// the UI preserves query params through the signup form. RSpec integration
// tests cover the backend verification-to-redirect flow.

import { test, expect, Page } from '@playwright/test';

/**
 * Wait for page to stabilize after navigation
 */
async function waitForPageLoad(page: Page): Promise<void> {
  await page.waitForLoadState('networkidle');
  // Ensure Vue has mounted and consumed bootstrap data
  await page.waitForFunction(() => {
    return (window as any).__BOOTSTRAP_ME__ === true;
  }, { timeout: 10000 }).catch(() => {
    // Bootstrap may not be consumed in all environments
  });
}

/**
 * Generate a unique test email to avoid conflicts
 */
function generateTestEmail(): string {
  const timestamp = Date.now();
  const random = Math.random().toString(36).substring(7);
  return `test-${timestamp}-${random}@example.com`;
}

test.describe('Pending Plan Intent - Signup Flow', () => {
  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
  });

  test('pricing deep link preserves product and interval in signup redirect', async ({ page }) => {
    // Visit pricing page with specific plan
    await page.goto('/pricing/identity_plus_v1/yearly');
    await waitForPageLoad(page);

    // Find and click the CTA for the highlighted plan
    const highlightedCard = page.locator('.ring-yellow-500, .ring-yellow-400').first();
    const cardVisible = await highlightedCard.isVisible().catch(() => false);

    if (!cardVisible) {
      // Fall back to any paid plan CTA
      const paidPlanCta = page.getByRole('link', { name: /get started/i }).first();
      const ctaVisible = await paidPlanCta.isVisible().catch(() => false);
      test.skip(!ctaVisible, 'No plan CTAs available - billing may be disabled');
      await paidPlanCta.click();
    } else {
      const cta = highlightedCard.getByRole('link');
      await cta.click();
    }

    // Verify redirect to signup with query params
    await expect(page).toHaveURL(/\/signup\?/);
    const url = new URL(page.url());
    expect(url.searchParams.get('product')).toContain('identity_plus');
    expect(url.searchParams.get('interval')).toBe('yearly');
  });

  test('signup form displays with preserved query params', async ({ page }) => {
    // Navigate directly to signup with billing params
    await page.goto('/signup?product=identity_plus_v1&interval=yearly');
    await waitForPageLoad(page);

    // Verify signup form is displayed
    const signupForm = page.getByTestId('signup-form');
    await expect(signupForm).toBeVisible();

    // Form fields should be accessible
    const emailInput = page.getByTestId('signup-email-input');
    const passwordInput = page.getByTestId('signup-password-input');
    const termsCheckbox = page.getByTestId('signup-terms-checkbox');
    const submitButton = page.getByTestId('signup-submit');

    await expect(emailInput).toBeVisible();
    await expect(passwordInput).toBeVisible();
    await expect(termsCheckbox).toBeVisible();
    await expect(submitButton).toBeVisible();
  });

  test('signin link preserves billing params', async ({ page }) => {
    // Navigate to signup with billing params
    await page.goto('/signup?product=identity_plus_v1&interval=yearly');
    await waitForPageLoad(page);

    // Find the "Sign in" link in the footer
    const signinLink = page.getByRole('link', { name: /sign in|have an account/i });
    await expect(signinLink).toBeVisible();

    // Click and verify params are preserved
    await signinLink.click();
    await expect(page).toHaveURL(/\/signin\?/);

    const url = new URL(page.url());
    expect(url.searchParams.get('product')).toBe('identity_plus_v1');
    expect(url.searchParams.get('interval')).toBe('yearly');
  });

  test('signup form submission includes billing params', async ({ page }) => {
    // Track API request to verify billing params are sent
    let requestBody: Record<string, string> | null = null;
    await page.route('**/auth/create-account', async (route) => {
      const request = route.request();
      try {
        requestBody = await request.postDataJSON();
      } catch {
        // Request may not have JSON body
      }
      // Let the request continue (may fail without valid credentials, that's OK)
      await route.continue();
    });

    await page.goto('/signup?product=identity_plus_v1&interval=yearly');
    await waitForPageLoad(page);

    // Fill form with test data
    const testEmail = generateTestEmail();
    await page.getByTestId('signup-email-input').fill(testEmail);
    await page.getByTestId('signup-password-input').fill('TestPassword123!');
    await page.getByTestId('signup-terms-checkbox').check();

    // Submit form
    await page.getByTestId('signup-submit').click();

    // Wait for request (may succeed or fail)
    await page.waitForResponse(
      (response) => response.url().includes('/auth/create-account'),
      { timeout: 10000 }
    ).catch(() => {
      // Response timeout is OK - we're checking request body
    });

    // Verify billing params were included in request
    expect(requestBody).not.toBeNull();
    if (requestBody) {
      expect(requestBody.product).toBe('identity_plus_v1');
      expect(requestBody.interval).toBe('yearly');
    }
  });
});

test.describe('Pending Plan Intent - Query Param Validation', () => {
  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
  });

  test('monthly interval is preserved through signup flow', async ({ page }) => {
    await page.goto('/signup?product=team_plus_v1&interval=monthly');
    await waitForPageLoad(page);

    // Click signin link to verify param preservation
    const signinLink = page.getByRole('link', { name: /sign in|have an account/i });
    await signinLink.click();

    const url = new URL(page.url());
    expect(url.searchParams.get('product')).toBe('team_plus_v1');
    expect(url.searchParams.get('interval')).toBe('monthly');
  });

  test('redirect param is preserved alongside billing params', async ({ page }) => {
    // Signup with redirect and billing params
    await page.goto('/signup?product=identity_plus_v1&interval=yearly&redirect=/dashboard');
    await waitForPageLoad(page);

    // Verify all params are present
    const url = new URL(page.url());
    expect(url.searchParams.get('product')).toBe('identity_plus_v1');
    expect(url.searchParams.get('interval')).toBe('yearly');
    expect(url.searchParams.get('redirect')).toBe('/dashboard');

    // Check signin link preserves all params
    const signinLink = page.getByRole('link', { name: /sign in|have an account/i });
    await signinLink.click();

    const signinUrl = new URL(page.url());
    expect(signinUrl.searchParams.get('product')).toBe('identity_plus_v1');
    expect(signinUrl.searchParams.get('interval')).toBe('yearly');
    expect(signinUrl.searchParams.get('redirect')).toBe('/dashboard');
  });

  test('email param is preserved with billing params', async ({ page }) => {
    const testEmail = 'prefill@example.com';
    await page.goto(`/signup?email=${encodeURIComponent(testEmail)}&product=identity_plus_v1&interval=yearly`);
    await waitForPageLoad(page);

    // Email should be prefilled
    const emailInput = page.getByTestId('signup-email-input');
    await expect(emailInput).toHaveValue(testEmail);

    // URL should have all params
    const url = new URL(page.url());
    expect(url.searchParams.get('email')).toBe(testEmail);
    expect(url.searchParams.get('product')).toBe('identity_plus_v1');
    expect(url.searchParams.get('interval')).toBe('yearly');
  });
});

test.describe('Pending Plan Intent - Sign In Flow', () => {
  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
  });

  test('signin page displays with preserved billing params', async ({ page }) => {
    await page.goto('/signin?product=identity_plus_v1&interval=yearly');
    await waitForPageLoad(page);

    // Verify signin form is displayed
    const emailInput = page.locator('input[type="email"], input[name="email"]');
    const passwordInput = page.locator('input[type="password"], input[name="password"]');

    await expect(emailInput).toBeVisible();
    await expect(passwordInput).toBeVisible();

    // URL should still have billing params
    const url = new URL(page.url());
    expect(url.searchParams.get('product')).toBe('identity_plus_v1');
    expect(url.searchParams.get('interval')).toBe('yearly');
  });

  test('login request includes billing params', async ({ page }) => {
    // Track API request
    let requestBody: Record<string, string> | null = null;
    await page.route('**/auth/login', async (route) => {
      const request = route.request();
      try {
        requestBody = await request.postDataJSON();
      } catch {
        // Request may not have JSON body
      }
      await route.continue();
    });

    await page.goto('/signin?product=identity_plus_v1&interval=yearly');
    await waitForPageLoad(page);

    // Fill form (credentials don't need to be valid for request capture)
    await page.locator('input[type="email"], input[name="email"]').fill('test@example.com');
    await page.locator('input[type="password"], input[name="password"]').fill('testpass');
    await page.locator('button[type="submit"]').click();

    // Wait for request
    await page.waitForResponse(
      (response) => response.url().includes('/auth/login'),
      { timeout: 10000 }
    ).catch(() => {});

    // Verify billing params were included
    expect(requestBody).not.toBeNull();
    if (requestBody) {
      expect(requestBody.product).toBe('identity_plus_v1');
      expect(requestBody.interval).toBe('yearly');
    }
  });
});

test.describe('Pending Plan Intent - Verify Account Flow', () => {
  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
  });

  test('verify account page handles missing key gracefully', async ({ page }) => {
    await page.goto('/verify-account');
    await waitForPageLoad(page);

    // Should show missing key message
    const missingKeyMessage = page.locator('text=/missing.*key|verification.*link/i');
    await expect(missingKeyMessage.first()).toBeVisible();
  });

  test('verify account page handles invalid key', async ({ page }) => {
    await page.goto('/verify-account?key=invalid-key-12345');
    await waitForPageLoad(page);

    // Should show error message (after API call fails)
    const errorMessage = page.locator('[role="alert"]');
    await expect(errorMessage).toBeVisible({ timeout: 10000 });
  });

  test('verify account page shows signin link on error', async ({ page }) => {
    await page.goto('/verify-account?key=invalid-key-12345');
    await waitForPageLoad(page);

    // Wait for verification to complete (with error)
    await page.waitForSelector('[role="alert"]', { timeout: 10000 }).catch(() => {});

    // Sign in link should be visible
    const signinLink = page.getByRole('link', { name: /sign in/i });
    await expect(signinLink).toBeVisible();
  });
});

test.describe('Pending Plan Intent - E2E Deep Link Flow', () => {
  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
  });

  test('full flow: pricing → signup → preserves params for backend', async ({ page }) => {
    // Step 1: Start at pricing deep link
    await page.goto('/pricing/identity_plus_v1/yearly');
    await waitForPageLoad(page);

    // Step 2: Click CTA to go to signup
    const paidPlanCta = page.getByRole('link', { name: /get started/i }).first();
    const ctaVisible = await paidPlanCta.isVisible().catch(() => false);
    test.skip(!ctaVisible, 'No plan CTAs available - billing may be disabled');

    await paidPlanCta.click();
    await expect(page).toHaveURL(/\/signup\?/);

    // Step 3: Verify signup form has correct params
    let url = new URL(page.url());
    expect(url.searchParams.get('product')).toContain('identity_plus');
    expect(url.searchParams.get('interval')).toBe('yearly');

    // Step 4: Navigate to signin (simulating "already have account")
    const signinLink = page.getByRole('link', { name: /sign in|have an account/i });
    await signinLink.click();

    // Step 5: Verify signin preserves params
    await expect(page).toHaveURL(/\/signin\?/);
    url = new URL(page.url());
    expect(url.searchParams.get('product')).toContain('identity_plus');
    expect(url.searchParams.get('interval')).toBe('yearly');
  });
});

/**
 * Manual Test Checklist - Pending Plan Intent
 *
 * ## Pricing to Signup Flow
 * - [ ] /pricing/identity_plus_v1/yearly shows highlighted plan
 * - [ ] Clicking CTA navigates to /signup?product=identity_plus_v1&interval=yearly
 * - [ ] Signup form accepts and submits form
 * - [ ] POST /auth/create-account includes product and interval params
 *
 * ## Query Parameter Preservation
 * - [ ] Signin link preserves product, interval, email, redirect params
 * - [ ] Back navigation preserves params
 * - [ ] Page refresh preserves params
 *
 * ## Backend Integration (requires RSpec tests)
 * - [ ] Signup stores pending_plan_intent in Customer record
 * - [ ] Verification email click reads pending_plan_intent
 * - [ ] After verification, redirect includes billing params
 * - [ ] pending_plan_intent has 24h TTL
 * - [ ] pending_plan_intent is cleared after use
 *
 * ## Edge Cases
 * - [ ] Invalid product ID is handled gracefully
 * - [ ] Expired pending_plan_intent redirects to dashboard
 * - [ ] User already subscribed to plan shows appropriate message
 */
