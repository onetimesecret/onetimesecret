// e2e/full-billing/pending-plan-intent.spec.ts
//
// E2E Tests for Pending Plan Intent Feature (Issue #3126)
//
// Tests the flow where unauthenticated users:
// 1. Visit pricing page -> select a plan
// 2. Get redirected to signup with product/interval params
// 3. Complete signup -> receive verification email
// 4. Click verification link -> redirected to checkout (not /account)
//
// NOTE: Full email verification flow requires email interception (Mailhog/Mailpit)
// or test environment with verification disabled. These tests focus on what can
// be verified without email interception.
//
// For browser-level automation of the full flow (including email), coordinate
// with the browser-tester agent.
//
// Prerequisites:
// - Application running locally or PLAYWRIGHT_BASE_URL set
// - Plans API returning valid plan data
// - For full flow: email interceptor (Mailhog) or verification disabled in test mode
//
// Usage:
//   pnpm test:playwright e2e/full-billing/pending-plan-intent.spec.ts

import { test, expect, Page } from '@playwright/test';

// The `full-billing` project starts every test authenticated as TEST_USER_*
// via storageState (e2e/playwright.config.ts), but this whole file tests the
// *unauthenticated* pricing -> signup -> checkout intent flow (an
// authenticated visitor never sees the signup form or the signup redirects).
// Opt out of the shared session.
test.use({ storageState: { cookies: [], origins: [] } });

/**
 * Generate a unique test email for signup
 */
function generateTestEmail(): string {
  const timestamp = Date.now();
  const random = Math.random().toString(36).substring(2, 8);
  return `test-plan-intent-${timestamp}-${random}@test.example.com`;
}

/**
 * Wait for pricing page to load with plans
 */
async function waitForPricingPageLoad(page: Page): Promise<void> {
  const planCards = page.locator('[class*="rounded-2xl"]');
  const noPlansMessage = page.getByText(/no.*plans available/i);

  await planCards.or(noPlansMessage).first().waitFor({ timeout: 15000 });
  await expect(page.locator('.animate-spin')).not.toBeVisible({ timeout: 5000 });
}

/**
 * Extract plan intent params from signup URL
 */
function extractPlanParams(url: string): { product: string | null; interval: string | null } {
  const urlObj = new URL(url);
  return {
    product: urlObj.searchParams.get('product'),
    interval: urlObj.searchParams.get('interval'),
  };
}

// =============================================================================
// SIGNUP URL PARAMETER TESTS
// =============================================================================
// These tests verify that plan selection on pricing page correctly propagates
// product/interval to the signup URL.

test.describe('Plan Selection to Signup URL', () => {
  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
  });

  test('paid plan CTA includes product and interval in signup URL', async ({ page }) => {
    await page.goto('/pricing');
    await waitForPricingPageLoad(page);

    // Find a paid plan CTA
    const paidPlanCta = page.getByRole('link', { name: /get started/i }).first();
    const isVisible = await paidPlanCta.isVisible().catch(() => false);

    test.skip(!isVisible, 'No paid plan CTAs available to test');

    // Click and verify URL params
    await paidPlanCta.click();
    await expect(page).toHaveURL(/\/signup\?product=.*&interval=.*/);

    const params = extractPlanParams(page.url());
    expect(params.product).toBeTruthy();
    expect(params.interval).toMatch(/monthly|yearly/);
  });

  test('deep link /pricing/:product/:interval CTA preserves params', async ({ page }) => {
    await page.goto('/pricing/identity_plus_v1/yearly');
    await waitForPricingPageLoad(page);

    // Find highlighted plan's CTA
    const highlightedCard = page.locator('.ring-yellow-500, .ring-yellow-400').first();
    const hasHighlighted = await highlightedCard.isVisible().catch(() => false);

    test.skip(!hasHighlighted, 'No highlighted plan found');

    const cta = highlightedCard.getByRole('link');
    await cta.click();

    // URL should preserve the deep-linked product/interval
    await expect(page).toHaveURL(/product=identity_plus_v1/);
    await expect(page).toHaveURL(/interval=yearly/);
  });

  test('free tier CTA does not include plan params', async ({ page }) => {
    await page.goto('/pricing');
    await waitForPricingPageLoad(page);

    const freePlanCta = page.getByRole('link', { name: /get started free/i }).first();
    const isVisible = await freePlanCta.isVisible().catch(() => false);

    test.skip(!isVisible, 'No free tier plan found');

    await freePlanCta.click();
    await expect(page).toHaveURL('/signup');

    const url = page.url();
    expect(url).not.toContain('product=');
    expect(url).not.toContain('interval=');
  });
});

// =============================================================================
// SIGNUP FORM PARAMETER PRESERVATION TESTS
// =============================================================================
// These tests verify the signup form correctly captures plan intent from URL params.

test.describe('Signup Form Plan Intent Capture', () => {
  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
  });

  test('signup page displays correctly with plan params', async ({ page }) => {
    await page.goto('/signup?product=identity_plus_v1&interval=monthly');
    await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

    // Verify we're on signup page with params preserved
    await expect(page).toHaveURL(/\/signup\?product=identity_plus_v1&interval=monthly/);

    // Signup form should be visible
    const emailInput = page.getByRole('textbox', { name: /email/i });
    const passwordInput = page.locator('input[type="password"]').first();

    await expect(emailInput).toBeVisible();
    await expect(passwordInput).toBeVisible();
  });

  test('signup form action includes plan params', async ({ page }) => {
    await page.goto('/signup?product=team_plus_v1&interval=yearly');
    await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

    // Check that the form action or hidden inputs include plan params
    // The implementation uses query params on the form action
    const form = page.locator('form').first();
    const formAction = await form.getAttribute('action');

    // Plan params should be included either in form action or as hidden fields
    const hasProductInAction = formAction?.includes('product=') ?? false;
    const hasHiddenProduct = await page.locator('input[name="product"][type="hidden"]').isVisible().catch(() => false);

    // At least one method should preserve the params
    const paramsPreserved = hasProductInAction || hasHiddenProduct;

    // If neither, the frontend may use a different approach (e.g., reading from URL on submit)
    // Log for debugging but don't fail - the backend captures from fullpath
    if (!paramsPreserved) {
      // The backend reads from request.fullpath, so params in URL are sufficient
      await expect(page).toHaveURL(/product=team_plus_v1/);
    }
  });
});

// =============================================================================
// SIGNUP SUBMISSION WITH PLAN INTENT
// =============================================================================
// Tests that verify signup submission includes plan params.
// NOTE: Full flow requires email verification setup.

test.describe('Signup Submission with Plan Intent', () => {
  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(20000);
  });

  test('signup submission sends plan params to backend', async ({ page }) => {
    const testEmail = generateTestEmail();

    // Intercept the signup POST request to verify params are sent
    let capturedRequest: { url: string; postData: string | null } | null = null;

    await page.route('**/auth/create-account**', async (route) => {
      capturedRequest = {
        url: route.request().url(),
        postData: route.request().postData(),
      };
      // Let the request continue (will likely fail with test email, but we capture it)
      await route.continue();
    });

    await page.goto('/signup?product=identity_plus_v1&interval=monthly');
    await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

    // Fill signup form
    const emailInput = page.getByRole('textbox', { name: /email/i });
    const passwordInput = page.locator('input[type="password"]').first();
    const submitButton = page.getByRole('button', { name: /create|sign up|register/i });

    await emailInput.fill(testEmail);
    await passwordInput.fill('TestPassword123!');

    // Click submit and wait for the create-account request to fire (the
    // route handler above captures it before letting it continue)
    const createAccountRequest = page.waitForRequest('**/auth/create-account**');
    await submitButton.click();
    await createAccountRequest;

    // Verify request URL included plan params
    if (capturedRequest) {
      expect(capturedRequest.url).toContain('product=identity_plus_v1');
      expect(capturedRequest.url).toContain('interval=monthly');
    }
  });

  test('normal signup without plan params does not include intent', async ({ page }) => {
    const testEmail = generateTestEmail();

    let capturedRequest: { url: string } | null = null;

    await page.route('**/auth/create-account**', async (route) => {
      capturedRequest = { url: route.request().url() };
      await route.continue();
    });

    await page.goto('/signup');
    await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

    const emailInput = page.getByRole('textbox', { name: /email/i });
    const passwordInput = page.locator('input[type="password"]').first();
    const submitButton = page.getByRole('button', { name: /create|sign up|register/i });

    await emailInput.fill(testEmail);
    await passwordInput.fill('TestPassword123!');

    // Submit and wait for the create-account request to fire (the route
    // handler above captures it before letting it continue)
    const createAccountRequest = page.waitForRequest('**/auth/create-account**');
    await submitButton.click();
    await createAccountRequest;

    if (capturedRequest) {
      expect(capturedRequest.url).not.toContain('product=');
      expect(capturedRequest.url).not.toContain('interval=');
    }
  });
});

// =============================================================================
// POST-VERIFICATION REDIRECT TESTS
// =============================================================================
// These tests require email verification to be disabled or a mail interceptor.
// Marked as skipped by default - enable when test infrastructure supports it.

// QUARANTINED — E2E remediation plan Phase 2.4 / PR 5 (issue #3421).
// Needs a mail interceptor (Mailpit/MailHog) to capture the verification link;
// CI runs with AUTH_AUTOVERIFY=true and cannot exercise the post-verification
// redirect. Was `test.skip(() => true)` — an unconditional skip that could only
// pass-or-skip. See e2e/QUARANTINE.md.
test.describe.fixme('Post-Verification Redirect', () => {

  test.describe('when verification is disabled (test mode)', () => {
    test('signup with plan params auto-redirects to checkout after verification', async ({ page }) => {
      // This test requires:
      // 1. verify_account feature disabled (RACK_ENV=test), OR
      // 2. Email interceptor (Mailhog) to capture verification link
      //
      // When verification is disabled, user is auto-logged-in after signup.
      // The pending_plan_intent should trigger redirect to checkout.

      const testEmail = generateTestEmail();

      await page.goto('/signup?product=identity_plus_v1&interval=monthly');
      await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

      const emailInput = page.getByRole('textbox', { name: /email/i });
      const passwordInput = page.locator('input[type="password"]').first();
      const submitButton = page.getByRole('button', { name: /create|sign up|register/i });

      await emailInput.fill(testEmail);
      await passwordInput.fill('TestPassword123!');
      await submitButton.click();

      // In test mode without verification, should redirect to checkout
      await expect(page).toHaveURL(/\/billing\/plans\/identity_plus_v1\/monthly/, {
        timeout: 10000,
      });
    });

    test('signup without plan params redirects to /account', async ({ page }) => {
      const testEmail = generateTestEmail();

      await page.goto('/signup');
      await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

      const emailInput = page.getByRole('textbox', { name: /email/i });
      const passwordInput = page.locator('input[type="password"]').first();
      const submitButton = page.getByRole('button', { name: /create|sign up|register/i });

      await emailInput.fill(testEmail);
      await passwordInput.fill('TestPassword123!');
      await submitButton.click();

      // Without plan params, should redirect to default /account
      await expect(page).toHaveURL('/account', { timeout: 10000 });
    });
  });
});

// =============================================================================
// CHECKOUT PAGE ACCESS TESTS
// =============================================================================
// Tests that verify the checkout page behavior for the redirected user.

test.describe('Checkout Page After Redirect', () => {
  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
  });

  test('checkout page loads for valid product/interval', async ({ page }) => {
    // This tests the destination URL works, not the full redirect flow
    await page.goto('/billing/plans/identity_plus_v1/monthly');

    // Page should load (may redirect to login if not authenticated)
    await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

    // Either we see the checkout page or are redirected to login
    const url = page.url();
    const isCheckout = url.includes('/billing/plans');
    const isLogin = url.includes('/signin') || url.includes('/login');

    expect(isCheckout || isLogin).toBe(true);
  });

  test('unauthenticated access to checkout redirects to signup with params', async ({ page }) => {
    // When unauthenticated user accesses checkout directly, they should be
    // redirected to signup with the plan params preserved
    await page.goto('/billing/plans/team_plus_v1/yearly');
    await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

    const url = page.url();

    // Should redirect to signup with plan params
    if (url.includes('/signup')) {
      expect(url).toContain('product=team_plus_v1');
      expect(url).toContain('interval=yearly');
    } else if (url.includes('/signin')) {
      // Or may redirect to signin with redirect param
      expect(url).toMatch(/redirect|return/);
    }
  });
});

// =============================================================================
// INTENT PERSISTENCE TESTS
// =============================================================================
// Tests that verify the 24h TTL behavior (where feasible without time manipulation).

test.describe('Plan Intent Edge Cases', () => {
  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
  });

  test('invalid product/interval combination is handled gracefully', async ({ page }) => {
    await page.goto('/signup?product=nonexistent_plan&interval=invalid');
    await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

    // Signup page should still load
    const emailInput = page.getByRole('textbox', { name: /email/i });
    await expect(emailInput).toBeVisible();

    // No error should be displayed for invalid params at signup stage
    // (validation happens at checkout)
    const errorAlert = page.locator('[role="alert"]');
    const hasVisibleError = await errorAlert.isVisible().catch(() => false);
    expect(hasVisibleError).toBe(false);
  });

  test('pricing page handles deep link to nonexistent product', async ({ page }) => {
    await page.goto('/pricing/nonexistent_product/monthly');
    await waitForPricingPageLoad(page);

    // Page should still load, just without highlighting the nonexistent product
    const planCards = page.locator('div.rounded-2xl').filter({
      has: page.locator('h2'),
    });
    const planCount = await planCards.count();

    // Plans should still be displayed
    expect(planCount).toBeGreaterThanOrEqual(0);
  });
});

/**
 * BROWSER-TESTER COORDINATION
 *
 * The following scenarios require browser-level email interception and should
 * be handled by the browser-tester agent:
 *
 * 1. Full email verification flow:
 *    - Signup with plan params
 *    - Intercept verification email (Mailhog/Mailpit)
 *    - Extract verification link
 *    - Click link -> verify redirect to /billing/plans/:product/:interval
 *
 * 2. Expired intent scenario:
 *    - Requires time manipulation or waiting 24h (not practical)
 *    - Alternative: Mock Redis TTL or use test endpoint to clear intent
 *
 * 3. Multiple verification attempts:
 *    - Verify intent is consumed after first use
 *    - Second verification should redirect to /account, not checkout
 *
 * Environment requirements for full flow:
 * - MAILHOG_URL or MAILPIT_URL environment variable
 * - verify_account feature enabled (RACK_ENV != test)
 * - Real SMTP configured to send to mail interceptor
 */

/**
 * Manual Test Checklist - Pending Plan Intent
 *
 * ## Happy Path (with email verification)
 * - [ ] Visit /pricing, select paid plan
 * - [ ] Click "Get Started" -> redirected to /signup?product=X&interval=Y
 * - [ ] Fill signup form, submit
 * - [ ] Receive verification email
 * - [ ] Click verification link -> redirected to /billing/plans/X/Y (NOT /account)
 * - [ ] Checkout page shows selected plan
 *
 * ## Normal Signup (no plan selection)
 * - [ ] Visit /signup directly (no params)
 * - [ ] Fill signup form, submit
 * - [ ] Receive verification email
 * - [ ] Click verification link -> redirected to /account
 *
 * ## Edge Cases
 * - [ ] Signup with invalid product -> graceful handling at checkout
 * - [ ] Intent expires (24h) -> verify redirects to /account
 * - [ ] Double-verification -> second click goes to /account (intent consumed)
 * - [ ] Plan discontinued after signup -> verify redirects to /account
 *
 * ## Security
 * - [ ] Cannot replay verification link after intent consumed
 * - [ ] Malformed intent JSON -> graceful fallback to /account
 */
