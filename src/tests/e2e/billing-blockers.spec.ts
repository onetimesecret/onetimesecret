// src/tests/e2e/billing-blockers.spec.ts

//
// E2E Tests for Stripe Integration Blockers (Issue #2309)
//
// Covers UX-related blockers:
// - BLOCKER 1 & 2: Monthly/Yearly plans tabs empty at /billing/plans
// - BLOCKER 4: Dashboard missing upgrade banner
// - BLOCKER 5: Account settings missing billing link
// - BLOCKER 6: Billing overview shows "No features available"
// - BLOCKER 9: Billing history shows "Organization not found"
// - BLOCKER 10: /org/domains route broken
//
// Prerequisites:
// - Set TEST_USER_EMAIL and TEST_USER_PASSWORD environment variables
// - Application running locally or PLAYWRIGHT_BASE_URL set
//
// Usage:
//   # Against dev server
//   TEST_USER_EMAIL=test@example.com TEST_USER_PASSWORD=secret \
//     pnpm playwright test billing-blockers.spec.ts
//
//   # Against external URL
//   PLAYWRIGHT_BASE_URL=https://dev.onetime.dev TEST_USER_EMAIL=... pnpm test:playwright billing-blockers.spec.ts

import { test, expect, Page } from '@playwright/test';

// Check if test credentials are configured
const hasTestCredentials = !!(process.env.TEST_USER_EMAIL && process.env.TEST_USER_PASSWORD);

/**
 * Authenticate user via login form
 */
async function loginUser(page: Page): Promise<void> {
  await page.goto('/signin');

  const emailInput = page.locator('input[type="email"], input[name="email"]');
  const passwordInput = page.locator('input[type="password"], input[name="password"]');
  const submitButton = page.locator('button[type="submit"]');

  if (await emailInput.isVisible()) {
    await emailInput.fill(process.env.TEST_USER_EMAIL || 'test@example.com');
    await passwordInput.fill(process.env.TEST_USER_PASSWORD || 'testpassword');
    await submitButton.click();

    // Wait for redirect to dashboard/account
    await page.waitForURL(/\/(account|dashboard)/, { timeout: 30000 });
  }
}

/**
 * Wait for API response and capture result
 */
async function _waitForApiResponse(page: Page, urlPattern: string | RegExp): Promise<{
  status: number;
  body: unknown;
}> {
  const response = await page.waitForResponse(
    (response) => {
      const url = response.url();
      if (typeof urlPattern === 'string') {
        return url.includes(urlPattern);
      }
      return urlPattern.test(url);
    },
    { timeout: 10000 }
  );

  const status = response.status();
  let body: unknown;
  try {
    body = await response.json();
  } catch {
    body = await response.text();
  }

  return { status, body };
}

test.describe('Stripe Integration Blockers - E2E', () => {
  test.skip(!hasTestCredentials, 'Skipping: TEST_USER_EMAIL and TEST_USER_PASSWORD required');

  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
  });

  // ---------------------------------------------------------------------------
  // BLOCKER 1 & 2: Plans Page - Monthly/Yearly tabs
  // TC-2309-001, TC-2309-002
  // ---------------------------------------------------------------------------
  test.describe('BLOCKER 1 & 2: Billing Plans Page', () => {
    test('TC-2309-001: Monthly plans tab displays available plans', async ({ page }) => {
      await loginUser(page);
      await page.goto('/billing/plans');

      // Wait for page to load
      await page.waitForLoadState('networkidle');

      // Monthly tab should be active by default or click to activate
      const monthlyTab = page.getByRole('button', { name: /monthly/i });
      if (await monthlyTab.isVisible()) {
        await monthlyTab.click();
      }

      // BLOCKER 1 ASSERTION: Check for empty state message
      const emptyMessage = page.locator('text=/no monthly plans available/i');
      const hasEmptyMessage = await emptyMessage.isVisible().catch(() => false);

      // Check for plan cards
      const planCards = page.locator('[class*="plan"], [class*="card"]').filter({
        has: page.locator('text=/month|price|upgrade/i'),
      });
      const planCount = await planCards.count();

      expect(
        hasEmptyMessage,
        'BLOCKER 1 FAILURE: "No monthly plans available" message is displayed. ' +
          'Plans API likely returning empty array.'
      ).toBe(false);

      expect(
        planCount,
        'BLOCKER 1 FAILURE: No plan cards visible on Monthly tab. ' +
          'Verify Stripe products have interval=month prices.'
      ).toBeGreaterThan(0);
    });

    test('TC-2309-002: Yearly plans tab displays available plans', async ({ page }) => {
      await loginUser(page);
      await page.goto('/billing/plans');

      await page.waitForLoadState('networkidle');

      // Click yearly tab
      const yearlyTab = page.getByRole('button', { name: /yearly|annual/i });
      await expect(yearlyTab).toBeVisible();
      await yearlyTab.click();

      // Wait for tab switch
      await page.waitForTimeout(500);

      // BLOCKER 2 ASSERTION: Check for empty state
      const emptyMessage = page.locator('text=/no yearly plans available/i');
      const hasEmptyMessage = await emptyMessage.isVisible().catch(() => false);

      const planCards = page.locator('[class*="plan"], [class*="card"]').filter({
        has: page.locator('text=/year|annual|price/i'),
      });
      const planCount = await planCards.count();

      expect(
        hasEmptyMessage,
        'BLOCKER 2 FAILURE: "No yearly plans available" message is displayed.'
      ).toBe(false);

      expect(
        planCount,
        'BLOCKER 2 FAILURE: No plan cards visible on Yearly tab. ' +
          'Verify Stripe products have interval=year prices.'
      ).toBeGreaterThan(0);
    });

    test('Plans API returns non-empty plans array', async ({ page }) => {
      await loginUser(page);

      // Intercept API call
      const apiPromise = page.waitForResponse(
        (response) => response.url().includes('/billing/api/plans'),
        { timeout: 15000 }
      );

      await page.goto('/billing/plans');
      const response = await apiPromise;

      expect(response.status()).toBe(200);

      const data = (await response.json()) as { plans: unknown[] };

      expect(
        data.plans,
        'BLOCKER 7 (API): Plans array should not be empty'
      ).toBeDefined();

      expect(
        data.plans.length,
        'BLOCKER 7 (API): Plans array is empty - check Stripe products and cache population'
      ).toBeGreaterThan(0);
    });

    test('Plan cards include required information', async ({ page }) => {
      await loginUser(page);
      await page.goto('/billing/plans');
      await page.waitForLoadState('networkidle');

      // Find any visible plan card
      const planCard = page
        .locator('[class*="plan"], [class*="card"]')
        .filter({ has: page.locator('button') })
        .first();

      const isVisible = await planCard.isVisible().catch(() => false);
      test.skip(!isVisible, 'No plan cards available to verify structure');

      // Plan cards should have name, price, and action button
      await expect(planCard.locator('h2, h3, [class*="title"]').first()).toBeVisible();
      await expect(planCard.locator('text=/$|EUR|price/i').first()).toBeVisible();
      await expect(planCard.locator('button').first()).toBeVisible();
    });
  });

  // ---------------------------------------------------------------------------
  // BLOCKER 4: Dashboard missing upgrade banner
  // TC-2309-004
  // ---------------------------------------------------------------------------
  test.describe('BLOCKER 4: Dashboard Upgrade Banner', () => {
    test('TC-2309-004: Free user sees plan indicator or upgrade prompt', async ({ page }) => {
      await loginUser(page);
      await page.goto('/dashboard');
      await page.waitForLoadState('networkidle');

      // Look for plan status indicator (badge, text, etc.)
      const planIndicator = page.locator(
        'text=/free|current plan|upgrade|view plans/i'
      );

      const upgradeLink = page.locator(
        'a[href*="/billing"], a[href*="/plans"], button:has-text(/upgrade/i)'
      );

      const hasIndicator = await planIndicator.first().isVisible().catch(() => false);
      const hasUpgradeLink = await upgradeLink.first().isVisible().catch(() => false);

      // At least one of these should be present for free users
      expect(
        hasIndicator || hasUpgradeLink,
        'BLOCKER 4 FAILURE: Dashboard has no plan indicator or upgrade prompt. ' +
          'Free users should see their plan status and upgrade options.'
      ).toBe(true);
    });

    test('Upgrade link navigates to plans page', async ({ page }) => {
      await loginUser(page);
      await page.goto('/dashboard');
      await page.waitForLoadState('networkidle');

      const upgradeLink = page.locator(
        'a[href*="/billing/plans"], a[href*="/plans"]:not([href*="pricing"])'
      ).first();

      const isVisible = await upgradeLink.isVisible().catch(() => false);
      test.skip(!isVisible, 'No upgrade link found on dashboard (may already be on paid plan)');

      await upgradeLink.click();
      await expect(page).toHaveURL(/\/billing\/plans|\/plans/);
    });
  });

  // ---------------------------------------------------------------------------
  // BLOCKER 5: Account settings missing billing link
  // TC-2309-005
  // ---------------------------------------------------------------------------
  test.describe('BLOCKER 5: Account Settings Billing Link', () => {
    test('TC-2309-005: Account settings includes billing navigation', async ({ page }) => {
      await loginUser(page);
      await page.goto('/account');
      await page.waitForLoadState('networkidle');

      // Look for billing/subscription link in navigation
      const billingLink = page.locator(
        'nav a:has-text(/billing|subscription/i), ' +
        'aside a:has-text(/billing|subscription/i), ' +
        '[class*="sidebar"] a:has-text(/billing|subscription/i), ' +
        '[class*="nav"] a:has-text(/billing|subscription/i)'
      );

      const isVisible = await billingLink.first().isVisible().catch(() => false);

      expect(
        isVisible,
        'BLOCKER 5 FAILURE: Account settings missing Billing navigation link. ' +
          'Sidebar currently has Profile, Security, API Key, Region, Danger Zone but no Billing.'
      ).toBe(true);
    });

    test('Billing link navigates to billing overview', async ({ page }) => {
      await loginUser(page);
      await page.goto('/account');
      await page.waitForLoadState('networkidle');

      const billingLink = page.locator('a:has-text(/billing|subscription/i)').first();
      const isVisible = await billingLink.isVisible().catch(() => false);
      test.skip(!isVisible, 'Billing link not found - BLOCKER 5 prevents this test');

      await billingLink.click();
      await expect(page).toHaveURL(/\/billing/);
    });
  });

  // ---------------------------------------------------------------------------
  // BLOCKER 6: Billing overview shows "No features available"
  // TC-2309-006
  // ---------------------------------------------------------------------------
  test.describe('BLOCKER 6: Billing Overview Features', () => {
    test('TC-2309-006: Billing overview displays plan features', async ({ page }) => {
      await loginUser(page);
      await page.goto('/billing/overview');
      await page.waitForLoadState('networkidle');

      // Check for "No features available" message
      const noFeaturesMessage = page.locator('text=/no features available|no entitlements/i');
      const hasNoFeatures = await noFeaturesMessage.isVisible().catch(() => false);

      expect(
        hasNoFeatures,
        'BLOCKER 6 FAILURE: Billing overview shows "No features available". ' +
          'Entitlements API likely failing. Check BLOCKER 8.'
      ).toBe(false);

      // Look for feature list
      const featureList = page.locator(
        '[class*="feature"], [class*="entitlement"], ul li:has-text(/access|secret|api/i)'
      );
      const featureCount = await featureList.count();

      expect(
        featureCount,
        'BLOCKER 6 FAILURE: No plan features displayed. Expected features like ' +
          'create_secrets, view_receipt, api_access.'
      ).toBeGreaterThan(0);
    });

    test('Current plan card displays correctly', async ({ page }) => {
      await loginUser(page);
      await page.goto('/billing/overview');
      await page.waitForLoadState('networkidle');

      // Current plan card should show plan name
      const planCard = page.locator('text=/current plan|your plan/i').first();
      await expect(planCard).toBeVisible();

      // Should show plan name (Free, Identity Plus, etc.)
      const planName = page.locator(
        'text=/free|identity|team|org|plus/i'
      );
      const hasPlanName = await planName.first().isVisible().catch(() => false);

      expect(
        hasPlanName,
        'Billing overview should display current plan name'
      ).toBe(true);
    });

    test('Entitlements API returns 200', async ({ page }) => {
      await loginUser(page);

      // Intercept entitlements API call
      const apiPromise = page.waitForResponse(
        (response) => response.url().includes('/billing/api/entitlements/'),
        { timeout: 15000 }
      );

      await page.goto('/billing/overview');

      const response = await apiPromise;

      // BLOCKER 8 ASSERTION
      expect(
        response.status(),
        'BLOCKER 8 (API): Entitlements API returned ' + response.status() +
          '. Expected 200. Check organization lookup and plan resolution.'
      ).not.toBe(500);

      expect(response.status()).toBe(200);
    });
  });

  // ---------------------------------------------------------------------------
  // BLOCKER 9: Billing history shows "Organization not found"
  // TC-2309-009
  // ---------------------------------------------------------------------------
  test.describe('BLOCKER 9: Billing History Organization Resolution', () => {
    test('TC-2309-009: Billing history loads without organization error', async ({ page }) => {
      await loginUser(page);
      await page.goto('/billing/invoices');
      await page.waitForLoadState('networkidle');

      // Check for organization not found error
      const orgError = page.locator('text=/organization not found/i');
      const hasOrgError = await orgError.isVisible().catch(() => false);

      expect(
        hasOrgError,
        'BLOCKER 9 FAILURE: Billing history shows "Organization not found". ' +
          'Check organization resolution logic and default org creation.'
      ).toBe(false);

      // Page should show either invoices or "No invoices yet" (both valid)
      const content = page.locator('text=/invoice|no invoices|billing history/i');
      const hasContent = await content.first().isVisible().catch(() => false);

      expect(
        hasContent,
        'Billing history page should display content (invoices or empty state)'
      ).toBe(true);
    });

    test('Organization selector works correctly', async ({ page }) => {
      await loginUser(page);
      await page.goto('/billing/invoices');
      await page.waitForLoadState('networkidle');

      // Look for org selector (only shown when multiple orgs exist)
      const orgSelector = page.locator('select[id*="org"], [class*="org-select"]');
      const hasSelector = await orgSelector.isVisible().catch(() => false);

      // If selector exists, it should be functional
      if (hasSelector) {
        const options = await orgSelector.locator('option').count();
        expect(options).toBeGreaterThan(0);
      }
    });
  });

  // ---------------------------------------------------------------------------
  // BLOCKER 10: /org/domains route broken
  // TC-2309-010
  // ---------------------------------------------------------------------------
  test.describe('BLOCKER 10: Organization Domains Route', () => {
    test('TC-2309-010: /org/domains route loads correctly', async ({ page }) => {
      await loginUser(page);
      await page.goto('/org/domains');
      await page.waitForLoadState('networkidle');

      // Check for error treating "domains" as org ID
      const orgIdError = page.locator('text=/organization not found.*domains/i');
      const hasOrgIdError = await orgIdError.isVisible().catch(() => false);

      expect(
        hasOrgIdError,
        'BLOCKER 10 FAILURE: Route treats "domains" as organization ID. ' +
          'Check router configuration for /org/domains path.'
      ).toBe(false);

      // Page should show domain management or upgrade prompt
      const pageContent = page.locator(
        'text=/domain|custom domain|upgrade|add domain/i'
      );
      const hasContent = await pageContent.first().isVisible().catch(() => false);

      expect(
        hasContent,
        'BLOCKER 10 FAILURE: Domains page not rendering correctly.'
      ).toBe(true);
    });

    test('Domains page accessible from organization navigation', async ({ page }) => {
      await loginUser(page);
      await page.goto('/org');
      await page.waitForLoadState('networkidle');

      // Look for domains link in org navigation
      const domainsLink = page.locator('a:has-text(/domain/i)').first();
      const isVisible = await domainsLink.isVisible().catch(() => false);

      if (isVisible) {
        await domainsLink.click();
        await page.waitForLoadState('networkidle');

        // Should not show org ID error
        const orgIdError = page.locator('text=/organization not found.*domains/i');
        const hasError = await orgIdError.isVisible().catch(() => false);

        expect(
          hasError,
          'Navigating to domains via org menu should not treat "domains" as org ID'
        ).toBe(false);
      }
    });
  });

  // ---------------------------------------------------------------------------
  // Cross-cutting: Navigation and Integration
  // ---------------------------------------------------------------------------
  test.describe('Billing Navigation Integration', () => {
    test('User menu has billing option', async ({ page }) => {
      await loginUser(page);
      await page.goto('/dashboard');

      // Open user menu
      const userMenu = page.locator(
        '[class*="user-menu"], [class*="avatar"], button[aria-haspopup="menu"]'
      ).first();
      const hasMenu = await userMenu.isVisible().catch(() => false);

      if (hasMenu) {
        await userMenu.click();
        await page.waitForTimeout(300);

        const billingOption = page.locator(
          '[role="menuitem"]:has-text(/billing/i), a:has-text(/billing/i)'
        );
        const hasBilling = await billingOption.first().isVisible().catch(() => false);

        expect(
          hasBilling,
          'User menu should have Billing option'
        ).toBe(true);
      }
    });

    test('Footer has Plans link', async ({ page }) => {
      await loginUser(page);
      await page.goto('/dashboard');
      await page.waitForLoadState('networkidle');

      const footerPlansLink = page.locator('footer a:has-text(/plans|pricing/i)');
      const isVisible = await footerPlansLink.first().isVisible().catch(() => false);

      if (isVisible) {
        await footerPlansLink.first().click();
        await expect(page).toHaveURL(/\/plans|\/billing\/plans|\/pricing/);
      }
    });

    test('Complete upgrade flow is accessible', async ({ page }) => {
      await loginUser(page);

      // Start from dashboard
      await page.goto('/dashboard');
      await page.waitForLoadState('networkidle');

      // Navigate to billing plans (however the app exposes it)
      await page.goto('/billing/plans');
      await page.waitForLoadState('networkidle');

      // Verify plans are displayed
      const planCards = page.locator('[class*="plan"], [class*="card"]').filter({
        has: page.locator('button'),
      });

      const hasPlans = (await planCards.count()) > 0;

      expect(
        hasPlans,
        'Complete upgrade flow: Plans page should display selectable plans'
      ).toBe(true);
    });
  });
});

/**
 * Manual Test Checklist - Stripe Integration Blockers
 *
 * ## BLOCKER 1 & 2: Plans Page
 * - [ ] Monthly tab shows Identity Plus, Team Plus, Org Plus plans
 * - [ ] Yearly tab shows same plans with annual pricing
 * - [ ] Price displayed correctly (EUR/USD based on region)
 * - [ ] "Most Popular" badge on recommended plan
 * - [ ] Feature lists are populated on each card
 *
 * ## BLOCKER 4: Dashboard Upgrade Banner
 * - [ ] Free user sees "Free" plan indicator
 * - [ ] Upgrade CTA visible and styled appropriately
 * - [ ] Link navigates to /billing/plans
 *
 * ## BLOCKER 5: Account Settings Billing Link
 * - [ ] Billing item in settings sidebar navigation
 * - [ ] Positioned logically (after Account, before Danger Zone)
 * - [ ] Icon matches other navigation items
 *
 * ## BLOCKER 6: Billing Overview Features
 * - [ ] Current plan card shows plan name
 * - [ ] Plan Features section populated
 * - [ ] Green checkmarks next to each feature
 * - [ ] Upgrade button present for free users
 *
 * ## BLOCKER 9: Billing History
 * - [ ] No error banner on page load
 * - [ ] Organization selector works (if multiple orgs)
 * - [ ] "No invoices yet" for free users (not error)
 *
 * ## BLOCKER 10: Organization Domains
 * - [ ] /org/domains loads without error
 * - [ ] Domain management UI or upgrade prompt displayed
 * - [ ] No "Organization not found: domains" message
 */
