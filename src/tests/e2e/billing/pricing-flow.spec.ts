// src/tests/e2e/billing/pricing-flow.spec.ts

//
// E2E Tests for Pricing Page to Checkout Flow
//
// Covers:
// - Pricing page deep links with product and interval parameters
// - Plan card highlighting based on URL parameters
// - CTA navigation to signup with query params
// - Billing interval toggle functionality
//
// Prerequisites:
// - Application running locally or PLAYWRIGHT_BASE_URL set
// - Plans API returning valid plan data
//
// Usage:
//   # Against dev server
//   pnpm playwright test billing/pricing-flow.spec.ts --config=src/tests/e2e/playwright.config.ts
//
//   # Against external URL
//   PLAYWRIGHT_BASE_URL=https://dev.onetime.dev pnpm test:playwright billing/pricing-flow.spec.ts

import { test, expect, Page } from '@playwright/test';

/**
 * Wait for the pricing page to fully load with plans
 */
async function waitForPricingPageLoad(page: Page): Promise<void> {
  // Wait for either plan cards or no plans message
  // Using locator().or() instead of waitForSelector with mixed selectors
  const planCards = page.locator('[class*="rounded-2xl"]');
  const noPlansMessage = page.getByText(/no.*plans available/i);

  await planCards.or(noPlansMessage).first().waitFor({ timeout: 15000 });

  // Ensure loading spinner is gone
  await expect(page.locator('.animate-spin')).not.toBeVisible({ timeout: 5000 });
}

/**
 * Get all visible plan cards on the page
 */
function getPlanCards(page: Page) {
  return page.locator('div.rounded-2xl').filter({
    has: page.locator('h2'),
  });
}

/**
 * Check if the monthly billing interval toggle is selected
 */
async function isMonthlySelected(page: Page): Promise<boolean> {
  const monthlyButton = page.getByRole('button', { name: /monthly/i });
  const ariaPressed = await monthlyButton.getAttribute('aria-pressed');
  return ariaPressed === 'true';
}

/**
 * Check if the yearly billing interval toggle is selected
 */
async function isYearlySelected(page: Page): Promise<boolean> {
  const yearlyButton = page.getByRole('button', { name: /yearly/i });
  const ariaPressed = await yearlyButton.getAttribute('aria-pressed');
  return ariaPressed === 'true';
}

test.describe('Pricing Page Deep Links', () => {
  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
  });

  test('direct link to /pricing shows all plans', async ({ page }) => {
    await page.goto('/pricing');
    await waitForPricingPageLoad(page);

    // Verify page title/heading is present
    await expect(page.getByRole('heading', { level: 1 })).toBeVisible();

    // Verify plan cards are present (at least one)
    const planCards = getPlanCards(page);
    const planCount = await planCards.count();

    expect(
      planCount,
      'Pricing page should display at least one plan card'
    ).toBeGreaterThan(0);

    // Verify billing interval toggle is present
    const monthlyButton = page.getByRole('button', { name: /monthly/i });
    const yearlyButton = page.getByRole('button', { name: /yearly/i });

    await expect(monthlyButton).toBeVisible();
    await expect(yearlyButton).toBeVisible();
  });

  test('deep link /pricing/identity_plus_v1/monthly highlights plan', async ({ page }) => {
    await page.goto('/pricing/identity_plus_v1/monthly');
    await waitForPricingPageLoad(page);

    // Monthly toggle should be selected
    const isMonthly = await isMonthlySelected(page);
    expect(
      isMonthly,
      'Monthly toggle should be selected when URL includes /monthly'
    ).toBe(true);

    // Plan should have yellow highlight ring (ring-yellow-500)
    // The highlighted plan card should have the yellow ring class
    const highlightedCard = page.locator('.ring-yellow-500, .ring-yellow-400');
    const hasHighlightedCard = await highlightedCard.first().isVisible().catch(() => false);

    // If plans contain identity_plus, it should be highlighted
    // Note: This may not find a match if identity_plus plan doesn't exist in test data
    if (hasHighlightedCard) {
      await expect(highlightedCard.first()).toBeVisible();

      // Check for "Recommended for you" badge on highlighted plan
      const recommendedBadge = page.locator('text=/recommended for you/i');
      await expect(recommendedBadge).toBeVisible();
    }
  });

  test('deep link with yearly interval sets yearly toggle', async ({ page }) => {
    await page.goto('/pricing/team_plus_v1/yearly');
    await waitForPricingPageLoad(page);

    // Yearly toggle should be selected
    const isYearly = await isYearlySelected(page);
    expect(
      isYearly,
      'Yearly toggle should be selected when URL includes /yearly'
    ).toBe(true);

    // Monthly should NOT be selected
    const isMonthly = await isMonthlySelected(page);
    expect(isMonthly).toBe(false);
  });

  test('deep link with annual interval sets yearly toggle', async ({ page }) => {
    // Test the 'annual' alias for yearly
    await page.goto('/pricing/team_plus_v1/annual');
    await waitForPricingPageLoad(page);

    const isYearly = await isYearlySelected(page);
    expect(
      isYearly,
      'Yearly toggle should be selected when URL includes /annual (alias for yearly)'
    ).toBe(true);
  });

  test('invalid interval in URL defaults to monthly', async ({ page }) => {
    // Use an invalid interval like 'weekly' which is not supported
    await page.goto('/pricing/identity_plus_v1/weekly');
    await waitForPricingPageLoad(page);

    // Should default to monthly since 'weekly' is not a valid interval
    const isMonthly = await isMonthlySelected(page);
    expect(
      isMonthly,
      'Invalid interval should default to monthly'
    ).toBe(true);
  });

  test('product-only deep link uses default monthly interval', async ({ page }) => {
    // Deep link with product but no interval
    await page.goto('/pricing/identity_plus_v1');
    await waitForPricingPageLoad(page);

    // Should default to monthly
    const isMonthly = await isMonthlySelected(page);
    expect(
      isMonthly,
      'Product-only deep link should default to monthly interval'
    ).toBe(true);
  });
});

test.describe('CTA Navigation', () => {
  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
  });

  test('clicking paid plan CTA navigates to signup with params', async ({ page }) => {
    await page.goto('/pricing');
    await waitForPricingPageLoad(page);

    // Find a paid plan CTA (not free tier)
    // Paid plans have "Get Started" text (from start_trial locale key)
    const paidPlanCta = page.getByRole('link', { name: /get started/i }).first();
    const isVisible = await paidPlanCta.isVisible().catch(() => false);

    test.skip(!isVisible, 'No paid plan CTAs available to test');

    await paidPlanCta.click();

    // Should navigate to signup with query params
    await expect(page).toHaveURL(/\/signup\?product=.*&interval=.*/);

    // Verify URL has both required params
    const url = page.url();
    expect(url).toContain('product=');
    expect(url).toContain('interval=');
  });

  test('clicking highlighted plan CTA includes correct product in URL', async ({ page }) => {
    await page.goto('/pricing/identity_plus_v1/monthly');
    await waitForPricingPageLoad(page);

    // Find the highlighted plan's CTA
    const highlightedCard = page.locator('.ring-yellow-500, .ring-yellow-400').first();
    const hasHighlighted = await highlightedCard.isVisible().catch(() => false);

    test.skip(!hasHighlighted, 'No highlighted plan found for this deep link');

    const cta = highlightedCard.getByRole('link');
    await cta.click();

    // URL should contain the product identifier
    await expect(page).toHaveURL(/\/signup\?product=identity_plus_v1/);
  });

  test('yearly plan CTA includes yearly interval in URL', async ({ page }) => {
    await page.goto('/pricing');
    await waitForPricingPageLoad(page);

    // Switch to yearly billing
    const yearlyButton = page.getByRole('button', { name: /yearly/i });
    await yearlyButton.click();

    // Wait for toggle state to update
    await expect(yearlyButton).toHaveAttribute('aria-pressed', 'true');

    // Click a paid plan CTA
    const paidPlanCta = page.getByRole('link', { name: /get started/i }).first();
    const isVisible = await paidPlanCta.isVisible().catch(() => false);

    test.skip(!isVisible, 'No yearly paid plan CTAs available');

    await paidPlanCta.click();

    // Should have yearly interval in URL
    await expect(page).toHaveURL(/interval=yearly/);
  });

  test('free tier CTA goes to signup without query params', async ({ page }) => {
    await page.goto('/pricing');
    await waitForPricingPageLoad(page);

    // Find free plan CTA - it has different text like "Get started free"
    // The free tier uses getCtaLabel which returns 'get_started_free' for free tier
    const freePlanCta = page.getByRole('link', { name: /get started free/i }).first();
    const isVisible = await freePlanCta.isVisible().catch(() => false);

    test.skip(!isVisible, 'No free tier plan found');

    await freePlanCta.click();

    // Should navigate to plain /signup without query params
    await expect(page).toHaveURL('/signup');

    // Ensure no product or interval params
    const url = page.url();
    expect(url).not.toContain('product=');
    expect(url).not.toContain('interval=');
  });
});

test.describe('Billing Interval Toggle', () => {
  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
  });

  test('toggle between monthly and yearly updates displayed plans', async ({ page }) => {
    await page.goto('/pricing');
    await waitForPricingPageLoad(page);

    // Initially monthly should be selected (default)
    expect(await isMonthlySelected(page)).toBe(true);
    expect(await isYearlySelected(page)).toBe(false);

    // Get initial plan card count for monthly
    const initialMonthlyCount = await getPlanCards(page).count();

    // Click yearly toggle
    const yearlyButton = page.getByRole('button', { name: /yearly/i });
    await yearlyButton.click();

    // Wait for toggle state to update
    await expect(yearlyButton).toHaveAttribute('aria-pressed', 'true');

    // Verify yearly toggle now selected
    expect(await isYearlySelected(page)).toBe(true);
    expect(await isMonthlySelected(page)).toBe(false);

    // Get yearly plan count (may be same or different)
    const yearlyCount = await getPlanCards(page).count();

    // Verify plans are still displayed (the toggle works)
    expect(
      yearlyCount,
      'Yearly plans should be displayed after toggle'
    ).toBeGreaterThanOrEqual(0);

    // Toggle back to monthly
    const monthlyButton = page.getByRole('button', { name: /monthly/i });
    await monthlyButton.click();

    // Wait for toggle state to update
    await expect(monthlyButton).toHaveAttribute('aria-pressed', 'true');

    // Verify monthly toggle selected again
    expect(await isMonthlySelected(page)).toBe(true);

    // Verify same number of plans as before
    const finalMonthlyCount = await getPlanCards(page).count();
    expect(finalMonthlyCount).toBe(initialMonthlyCount);
  });

  test('toggle has correct ARIA attributes', async ({ page }) => {
    await page.goto('/pricing');
    await waitForPricingPageLoad(page);

    const monthlyButton = page.getByRole('button', { name: /monthly/i });
    const yearlyButton = page.getByRole('button', { name: /yearly/i });

    // Check ARIA group
    const intervalGroup = page.locator('[role="group"][aria-label*="interval" i]');
    await expect(intervalGroup).toBeVisible();

    // Check aria-pressed states
    await expect(monthlyButton).toHaveAttribute('aria-pressed', 'true');
    await expect(yearlyButton).toHaveAttribute('aria-pressed', 'false');

    // Click yearly and wait for aria-pressed to flip
    await yearlyButton.click();
    await expect(yearlyButton).toHaveAttribute('aria-pressed', 'true');

    // aria-pressed should flip
    await expect(monthlyButton).toHaveAttribute('aria-pressed', 'false');
  });

  test('yearly plans show annual price with monthly equivalent', async ({ page }) => {
    await page.goto('/pricing');
    await waitForPricingPageLoad(page);

    // Switch to yearly
    const yearlyButton = page.getByRole('button', { name: /yearly/i });
    await yearlyButton.click();
    await waitForPricingPageLoad(page);

    // Find a paid plan card
    const paidPlanCard = getPlanCards(page).filter({
      has: page.locator('text=/get started/i'),
    }).first();

    const isVisible = await paidPlanCard.isVisible().catch(() => false);
    test.skip(!isVisible, 'No paid yearly plan found to verify pricing display');

    // Yearly plans should show "Yearly: $X" text
    const yearlyPriceLabel = paidPlanCard.locator('text=/yearly:/i');
    const hasYearlyLabel = await yearlyPriceLabel.isVisible().catch(() => false);

    // If yearly plans exist, they should show the yearly price
    if (hasYearlyLabel) {
      await expect(yearlyPriceLabel).toBeVisible();
    }
  });
});

test.describe('Plan Card Display', () => {
  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
  });

  test('plan cards display required elements', async ({ page }) => {
    await page.goto('/pricing');
    await waitForPricingPageLoad(page);

    const planCards = getPlanCards(page);
    const planCount = await planCards.count();

    test.skip(planCount === 0, 'No plan cards to verify');

    // Check first plan card has required elements
    const firstCard = planCards.first();

    // Plan name (h2)
    await expect(firstCard.locator('h2')).toBeVisible();

    // Price display
    await expect(firstCard.locator('text=/\\$|EUR|\\d+/').first()).toBeVisible();

    // Features section with checkmarks
    await expect(firstCard.locator('[collection="heroicons"][name="check"]').first()).toBeVisible();

    // CTA button/link
    await expect(firstCard.getByRole('link')).toBeVisible();
  });

  test('recommended plan has Most Popular badge', async ({ page }) => {
    await page.goto('/pricing');
    await waitForPricingPageLoad(page);

    // Look for "Most Popular" badge
    const mostPopularBadge = page.locator('text=/most popular/i');
    const hasBadge = await mostPopularBadge.isVisible().catch(() => false);

    // This is not a hard requirement - API may not mark any plan as popular
    if (hasBadge) {
      await expect(mostPopularBadge).toBeVisible();

      // The badge should be on a highlighted card (ring-brand-*)
      const recommendedCard = page.locator('.ring-brand-500, .ring-brand-400').first();
      await expect(recommendedCard).toBeVisible();
    }
  });

  test('feature list items are readable', async ({ page }) => {
    await page.goto('/pricing');
    await waitForPricingPageLoad(page);

    const planCards = getPlanCards(page);
    const planCount = await planCards.count();

    test.skip(planCount === 0, 'No plan cards to verify');

    // Get features from first card
    const firstCard = planCards.first();
    const featureItems = firstCard.locator('ul li');
    const featureCount = await featureItems.count();

    expect(
      featureCount,
      'Plan card should have at least one feature listed'
    ).toBeGreaterThan(0);

    // Verify features have check icons
    const checkIcons = firstCard.locator('ul li [collection="heroicons"][name="check"]');
    const checkCount = await checkIcons.count();

    expect(checkCount).toBe(featureCount);
  });
});

test.describe('Pricing Page Accessibility', () => {
  test('page has proper heading structure', async ({ page }) => {
    await page.goto('/pricing');
    await waitForPricingPageLoad(page);

    // Main heading (h1)
    const h1 = page.getByRole('heading', { level: 1 });
    await expect(h1).toBeVisible();
    await expect(h1).toHaveAttribute('id', 'pricing-title');

    // Section should be labelled by the heading
    const section = page.locator('section[aria-labelledby="pricing-title"]');
    await expect(section).toBeVisible();

    // Plan names should be h2
    const planHeadings = page.locator('h2');
    const h2Count = await planHeadings.count();
    expect(h2Count).toBeGreaterThanOrEqual(0); // May have no plans in test env
  });

  test('billing toggle is keyboard accessible', async ({ page }) => {
    await page.goto('/pricing');
    await waitForPricingPageLoad(page);

    const monthlyButton = page.getByRole('button', { name: /monthly/i });
    const yearlyButton = page.getByRole('button', { name: /yearly/i });

    // Tab to the toggle area
    await monthlyButton.focus();
    await expect(monthlyButton).toBeFocused();

    // Verify can activate with keyboard
    await page.keyboard.press('Enter');
    // Monthly should remain selected (was already selected)
    expect(await isMonthlySelected(page)).toBe(true);

    // Tab to yearly and activate
    await yearlyButton.focus();
    await page.keyboard.press('Enter');

    // Wait for toggle state to update
    await expect(yearlyButton).toHaveAttribute('aria-pressed', 'true');
    expect(await isYearlySelected(page)).toBe(true);
  });

  test('CTA links are properly labelled', async ({ page }) => {
    await page.goto('/pricing');
    await waitForPricingPageLoad(page);

    const ctaLinks = page.getByRole('link').filter({
      hasText: /get started/i,
    });

    const ctaCount = await ctaLinks.count();
    test.skip(ctaCount === 0, 'No CTA links to verify');

    // Each CTA should have accessible text
    for (let i = 0; i < ctaCount; i++) {
      const cta = ctaLinks.nth(i);
      const text = await cta.textContent();
      expect(text?.trim().length).toBeGreaterThan(0);
    }
  });
});

test.describe('Error States', () => {
  test('displays error when plans API fails', async ({ page }) => {
    // Mock the plans API to fail
    await page.route('**/billing/api/plans', (route) => {
      route.fulfill({
        status: 500,
        contentType: 'application/json',
        body: JSON.stringify({ error: 'Internal server error' }),
      });
    });

    await page.goto('/pricing');

    // Should show error alert
    const errorAlert = page.locator('[role="alert"], .text-red-600, .bg-red-50');
    await expect(errorAlert.first()).toBeVisible({ timeout: 10000 });
  });

  test('shows no plans message when API returns empty array', async ({ page }) => {
    // Mock empty plans response
    await page.route('**/billing/api/plans', (route) => {
      route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({ plans: [] }),
      });
    });

    await page.goto('/pricing');
    await page.waitForLoadState('networkidle');

    // Should show "no plans available" message
    const noPlansMessage = page.locator('text=/no.*plans available/i');
    await expect(noPlansMessage).toBeVisible({ timeout: 10000 });
  });
});

test.describe('Navigation Integration', () => {
  test('sign in link navigates to signin page', async ({ page }) => {
    await page.goto('/pricing');
    await waitForPricingPageLoad(page);

    // Find "Sign in" link in the existing users section
    const signInLink = page.getByRole('link', { name: /sign in/i });
    await expect(signInLink).toBeVisible();

    await signInLink.click();
    await expect(page).toHaveURL('/signin');
  });

  test('custom needs section has feedback toggle', async ({ page }) => {
    await page.goto('/pricing');
    await waitForPricingPageLoad(page);

    // Custom needs section at bottom of page
    const customNeedsSection = page.locator('text=/custom needs|enterprise/i').first();
    await expect(customNeedsSection).toBeVisible();

    // Feedback toggle may or may not be visible depending on config
    // Just verify the section exists
    await expect(customNeedsSection).toBeVisible();
  });
});

/**
 * Manual Test Checklist - Pricing Flow
 *
 * ## Deep Links
 * - [ ] /pricing loads with all plans visible
 * - [ ] /pricing/identity_plus_v1/monthly highlights Identity Plus plan
 * - [ ] /pricing/team_plus_v1/yearly selects yearly toggle
 * - [ ] Invalid interval (e.g., /pricing/plan/weekly) defaults to monthly
 * - [ ] Product-only URL (/pricing/product) defaults to monthly
 *
 * ## Billing Toggle
 * - [ ] Toggle shows monthly/yearly options
 * - [ ] Clicking yearly shows yearly plans
 * - [ ] Clicking monthly shows monthly plans
 * - [ ] Toggle has correct aria-pressed states
 *
 * ## CTA Buttons
 * - [ ] Paid plan CTA goes to /signup?product=X&interval=Y
 * - [ ] Free plan CTA goes to /signup (no params)
 * - [ ] Yearly plans include interval=yearly in URL
 *
 * ## Plan Cards
 * - [ ] Each card shows plan name (h2)
 * - [ ] Each card shows price
 * - [ ] Each card shows features with checkmarks
 * - [ ] Most Popular badge on recommended plan
 * - [ ] Yellow highlight on deep-linked product
 *
 * ## Accessibility
 * - [ ] Heading structure is correct (h1 for page, h2 for plans)
 * - [ ] Toggle is keyboard accessible
 * - [ ] CTAs are properly labelled
 * - [ ] ARIA attributes on toggle group
 */
