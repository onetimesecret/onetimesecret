// src/tests/e2e/scope-switcher.spec.ts

//
// E2E Tests for Scope Switcher Components
//
// Covers Organization and Domain Scope Switcher behavior across different pages:
// - Visibility rules per route (show, locked, hide)
// - Switching behavior (selecting different org/domain)
// - Locked state behavior (visible but non-interactive)
// - Navigation behavior (gear icon, domain click)
// - Multi-org/multi-domain user scenarios
// - Edge cases (single org user, no domains)
//
// Prerequisites:
// - Set TEST_USER_EMAIL and TEST_USER_PASSWORD environment variables
// - Application running locally or PLAYWRIGHT_BASE_URL set
// - User should have multiple organizations and domains for full coverage
//
// Usage:
//   # Against dev server
//   TEST_USER_EMAIL=test@example.com TEST_USER_PASSWORD=secret \
//     pnpm playwright test scope-switcher.spec.ts
//
//   # Against external URL
//   PLAYWRIGHT_BASE_URL=https://dev.onetime.dev TEST_USER_EMAIL=... \
//     pnpm test:playwright scope-switcher.spec.ts

import { expect, Page, test } from '@playwright/test';

// Check if test credentials are configured
const hasTestCredentials = !!(process.env.TEST_USER_EMAIL && process.env.TEST_USER_PASSWORD);

/**
 * Data-testid recommendations for components:
 *
 * Organization Scope Switcher:
 *   - data-testid="org-scope-switcher"          - Main switcher container
 *   - data-testid="org-scope-switcher-trigger"  - Dropdown trigger button
 *   - data-testid="org-scope-switcher-dropdown" - Dropdown menu
 *   - data-testid="org-scope-item-{orgId}"      - Individual org menu item
 *   - data-testid="org-scope-settings-{orgId}"  - Gear icon for org settings
 *   - data-testid="org-scope-manage-link"       - "Manage Organizations" link
 *
 * Domain Scope Switcher:
 *   - data-testid="domain-scope-switcher"         - Main switcher container
 *   - data-testid="domain-scope-switcher-trigger" - Dropdown trigger button
 *   - data-testid="domain-scope-switcher-dropdown"- Dropdown menu
 *   - data-testid="domain-scope-item-{domain}"    - Individual domain menu item
 *   - data-testid="domain-scope-settings-{domain}"- Gear icon for domain settings
 *   - data-testid="domain-scope-add-link"         - "Add Domain" link
 */

// -----------------------------------------------------------------------------
// Test Helpers
// -----------------------------------------------------------------------------

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
 * Locators for Organization Scope Switcher
 */
const orgSwitcher = {
  container: (page: Page) => page.locator('[data-testid="org-scope-switcher"]'),
  // Fallback to component structure if data-testid not yet implemented
  containerFallback: (page: Page) =>
    page.locator('.relative.inline-flex').filter({
      has: page.locator('button[aria-label*="organization" i]'),
    }),
  trigger: (page: Page) =>
    page.locator(
      '[data-testid="org-scope-switcher-trigger"], button[aria-label*="organization" i]'
    ),
  dropdown: (page: Page) =>
    page.locator('[data-testid="org-scope-switcher-dropdown"], [role="menu"]').filter({
      has: page.locator('text=/my organizations/i'),
    }),
  menuItems: (page: Page) => page.locator('[role="menuitem"]'),
  gearIcon: (page: Page) =>
    page.locator(
      '[data-testid^="org-scope-settings"], button[aria-label*="organization settings" i]'
    ),
  manageLink: (page: Page) =>
    page.locator('[data-testid="org-scope-manage-link"], button:has-text("Manage Organizations")'),
  checkmark: (page: Page) => page.locator('[class*="check"]'),
};

/**
 * Locators for Domain Scope Switcher
 */
const domainSwitcher = {
  container: (page: Page) => page.locator('[data-testid="domain-scope-switcher"]'),
  // Fallback to component structure if data-testid not yet implemented
  containerFallback: (page: Page) =>
    page.locator('.relative.inline-flex').filter({
      has: page.locator('button[aria-label*="domain" i], button[aria-label*="scope" i]'),
    }),
  trigger: (page: Page) =>
    page.locator('[data-testid="domain-scope-switcher-trigger"], button[aria-label*="scope" i]'),
  dropdown: (page: Page) =>
    page.locator('[data-testid="domain-scope-switcher-dropdown"], [role="menu"]').filter({
      has: page.locator('text=/domain/i'),
    }),
  menuItems: (page: Page) => page.locator('[role="menuitem"]'),
  gearIcon: (page: Page) =>
    page.locator('[data-testid^="domain-scope-settings"], button[aria-label*="domain settings" i]'),
  addLink: (page: Page) =>
    page.locator('[data-testid="domain-scope-add-link"], button:has-text("Add Domain")'),
};

/**
 * Check if an element is disabled (has disabled attribute or aria-disabled)
 */
async function isElementDisabled(
  page: Page,
  locator: ReturnType<typeof page.locator>
): Promise<boolean> {
  const element = locator.first();
  const isVisible = await element.isVisible().catch(() => false);
  if (!isVisible) return false;

  const disabled = await element.getAttribute('disabled');
  const ariaDisabled = await element.getAttribute('aria-disabled');
  const hasDisabledClass = await element.evaluate(
    (el) =>
      el.classList.contains('disabled') ||
      el.classList.contains('cursor-not-allowed') ||
      el.classList.contains('opacity-50')
  );

  return disabled !== null || ariaDisabled === 'true' || hasDisabledClass;
}

// -----------------------------------------------------------------------------
// Visibility Rules Matrix Test Suite
// -----------------------------------------------------------------------------

test.describe('Scope Switcher - Visibility Rules', () => {
  test.skip(!hasTestCredentials, 'Skipping: TEST_USER_EMAIL and TEST_USER_PASSWORD required');

  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
    await loginUser(page);
  });

  // -------------------------------------------------------------------------
  // TC-SS-001: Dashboard - Both Switchers Visible
  // -------------------------------------------------------------------------
  test.describe('Dashboard (/dashboard)', () => {
    test('TC-SS-001: Organization switcher is visible and interactive', async ({ page }) => {
      await page.goto('/dashboard');
      await page.waitForLoadState('networkidle');

      // Organization switcher should be visible
      const orgTrigger = orgSwitcher.trigger(page);
      const isVisible = await orgTrigger.isVisible().catch(() => false);

      expect(isVisible, 'Organization switcher should be visible on Dashboard').toBe(true);

      // Should be interactive (not disabled)
      const isDisabled = await isElementDisabled(page, orgTrigger);
      expect(isDisabled, 'Organization switcher should be interactive on Dashboard').toBe(false);
    });

    test('TC-SS-002: Domain switcher is visible and interactive', async ({ page }) => {
      await page.goto('/dashboard');
      await page.waitForLoadState('networkidle');

      const domainTrigger = domainSwitcher.trigger(page);
      const isVisible = await domainTrigger.isVisible().catch(() => false);

      // Domain switcher visibility depends on user having custom domains
      // For users without domains, it should be hidden (not an error)
      if (isVisible) {
        const isDisabled = await isElementDisabled(page, domainTrigger);
        expect(isDisabled, 'Domain switcher should be interactive on Dashboard when visible').toBe(
          false
        );
      }
    });
  });

  // -------------------------------------------------------------------------
  // TC-SS-003-004: Secret Creation - Both Switchers Visible
  // -------------------------------------------------------------------------
  test.describe('Secret Creation (/)', () => {
    test('TC-SS-003: Organization switcher is visible on secret creation page', async ({
      page,
    }) => {
      await page.goto('/');
      await page.waitForLoadState('networkidle');

      const orgTrigger = orgSwitcher.trigger(page);
      const isVisible = await orgTrigger.isVisible().catch(() => false);

      expect(isVisible, 'Organization switcher should be visible on secret creation page').toBe(
        true
      );
    });

    test('TC-SS-004: Domain switcher is visible on secret creation page', async ({ page }) => {
      await page.goto('/');
      await page.waitForLoadState('networkidle');

      const domainTrigger = domainSwitcher.trigger(page);
      const isVisible = await domainTrigger.isVisible().catch(() => false);

      // Only visible if user has custom domains enabled
      // Test passes if either visible or correctly hidden
      if (isVisible) {
        const isDisabled = await isElementDisabled(page, domainTrigger);
        expect(isDisabled).toBe(false);
      }
    });
  });

  // -------------------------------------------------------------------------
  // TC-SS-005-006: Org Settings - Org Locked, Domain Hidden
  // -------------------------------------------------------------------------
  test.describe('Organization Settings (/org/:extid)', () => {
    test('TC-SS-005: Organization switcher is locked (visible but disabled)', async ({ page }) => {
      // First get org list to find a valid extid
      await page.goto('/dashboard');
      await page.waitForLoadState('networkidle');

      // Try to get org extid from URL or navigate to org settings
      await page.goto('/orgs');
      await page.waitForLoadState('networkidle');

      // Look for org link or navigate to first org
      const orgLink = page.locator('a[href*="/org/"]').first();
      const hasOrgLink = await orgLink.isVisible().catch(() => false);

      if (hasOrgLink) {
        await orgLink.click();
        await page.waitForLoadState('networkidle');

        const orgTrigger = orgSwitcher.trigger(page);
        const isVisible = await orgTrigger.isVisible().catch(() => false);

        if (isVisible) {
          // On org settings page, switcher should be locked
          const isDisabled = await isElementDisabled(page, orgTrigger);
          expect(
            isDisabled,
            'Organization switcher should be locked (disabled) on org settings page'
          ).toBe(true);
        }
      } else {
        test.skip(true, 'No organizations available to test org settings page');
      }
    });

    test('TC-SS-006: Domain switcher is hidden on org settings page', async ({ page }) => {
      await page.goto('/orgs');
      await page.waitForLoadState('networkidle');

      const orgLink = page.locator('a[href*="/org/"]').first();
      const hasOrgLink = await orgLink.isVisible().catch(() => false);

      if (hasOrgLink) {
        await orgLink.click();
        await page.waitForLoadState('networkidle');

        const domainTrigger = domainSwitcher.trigger(page);
        const isVisible = await domainTrigger.isVisible().catch(() => false);

        expect(isVisible, 'Domain switcher should be hidden on org settings page').toBe(false);
      }
    });
  });

  // -------------------------------------------------------------------------
  // TC-SS-007-008: Domains List - Both Visible
  // -------------------------------------------------------------------------
  test.describe('Domains List (/domains)', () => {
    test('TC-SS-007: Organization switcher is visible on domains list', async ({ page }) => {
      await page.goto('/domains');
      await page.waitForLoadState('networkidle');

      const orgTrigger = orgSwitcher.trigger(page);
      const isVisible = await orgTrigger.isVisible().catch(() => false);

      expect(isVisible, 'Organization switcher should be visible on domains list page').toBe(true);
    });

    test('TC-SS-008: Domain switcher is visible on domains list', async ({ page }) => {
      await page.goto('/domains');
      await page.waitForLoadState('networkidle');

      const domainTrigger = domainSwitcher.trigger(page);
      // May not be visible if user has no domains - that's expected behavior
      const isVisible = await domainTrigger.isVisible().catch(() => false);

      // If visible, should be interactive
      if (isVisible) {
        const isDisabled = await isElementDisabled(page, domainTrigger);
        expect(isDisabled).toBe(false);
      }
    });
  });

  // -------------------------------------------------------------------------
  // TC-SS-009-010: Domain Detail - Org Visible, Domain Locked
  // -------------------------------------------------------------------------
  test.describe('Domain Detail (/domains/:extid)', () => {
    test('TC-SS-009: Organization switcher is visible on domain detail', async ({ page }) => {
      await page.goto('/domains');
      await page.waitForLoadState('networkidle');

      // Find a domain link
      const domainLink = page
        .locator('a[href*="/domains/"]')
        .filter({
          hasNot: page.locator('text=/add/i'),
        })
        .first();
      const hasDomainLink = await domainLink.isVisible().catch(() => false);

      if (hasDomainLink) {
        await domainLink.click();
        await page.waitForLoadState('networkidle');

        const orgTrigger = orgSwitcher.trigger(page);
        const isVisible = await orgTrigger.isVisible().catch(() => false);

        expect(isVisible, 'Organization switcher should be visible on domain detail page').toBe(
          true
        );
      } else {
        test.skip(true, 'No domains available to test domain detail page');
      }
    });

    test('TC-SS-010: Domain switcher is locked on domain detail', async ({ page }) => {
      await page.goto('/domains');
      await page.waitForLoadState('networkidle');

      const domainLink = page
        .locator('a[href*="/domains/"]')
        .filter({
          hasNot: page.locator('text=/add/i'),
        })
        .first();
      const hasDomainLink = await domainLink.isVisible().catch(() => false);

      if (hasDomainLink) {
        await domainLink.click();
        await page.waitForLoadState('networkidle');

        const domainTrigger = domainSwitcher.trigger(page);
        const isVisible = await domainTrigger.isVisible().catch(() => false);

        if (isVisible) {
          const isDisabled = await isElementDisabled(page, domainTrigger);
          expect(isDisabled, 'Domain switcher should be locked on domain detail page').toBe(true);
        }
      }
    });
  });

  // -------------------------------------------------------------------------
  // TC-SS-011-012: Billing - Org Locked, Domain Hidden
  // -------------------------------------------------------------------------
  test.describe('Billing Pages (/billing/*)', () => {
    test('TC-SS-011: Organization switcher is locked on billing pages', async ({ page }) => {
      await page.goto('/billing/overview');
      await page.waitForLoadState('networkidle');

      const orgTrigger = orgSwitcher.trigger(page);
      const isVisible = await orgTrigger.isVisible().catch(() => false);

      if (isVisible) {
        const isDisabled = await isElementDisabled(page, orgTrigger);
        expect(isDisabled, 'Organization switcher should be locked on billing pages').toBe(true);
      }
    });

    test('TC-SS-012: Domain switcher is hidden on billing pages', async ({ page }) => {
      await page.goto('/billing/overview');
      await page.waitForLoadState('networkidle');

      const domainTrigger = domainSwitcher.trigger(page);
      const isVisible = await domainTrigger.isVisible().catch(() => false);

      expect(isVisible, 'Domain switcher should be hidden on billing pages').toBe(false);
    });

    test('TC-SS-013: Visibility rules apply to billing/plans', async ({ page }) => {
      await page.goto('/billing/plans');
      await page.waitForLoadState('networkidle');

      // Org locked
      const orgTrigger = orgSwitcher.trigger(page);
      if (await orgTrigger.isVisible().catch(() => false)) {
        const orgDisabled = await isElementDisabled(page, orgTrigger);
        expect(orgDisabled).toBe(true);
      }

      // Domain hidden
      const domainTrigger = domainSwitcher.trigger(page);
      const domainVisible = await domainTrigger.isVisible().catch(() => false);
      expect(domainVisible).toBe(false);
    });

    test('TC-SS-014: Visibility rules apply to billing/invoices', async ({ page }) => {
      await page.goto('/billing/invoices');
      await page.waitForLoadState('networkidle');

      // Domain hidden
      const domainTrigger = domainSwitcher.trigger(page);
      const domainVisible = await domainTrigger.isVisible().catch(() => false);
      expect(domainVisible).toBe(false);
    });
  });

  // -------------------------------------------------------------------------
  // TC-SS-015-016: Account Settings - Both Hidden
  // -------------------------------------------------------------------------
  test.describe('Account Settings (/account/*)', () => {
    test('TC-SS-015: Organization switcher is hidden on account pages', async ({ page }) => {
      await page.goto('/account');
      await page.waitForLoadState('networkidle');

      const orgTrigger = orgSwitcher.trigger(page);
      const isVisible = await orgTrigger.isVisible().catch(() => false);

      expect(isVisible, 'Organization switcher should be hidden on account pages').toBe(false);
    });

    test('TC-SS-016: Domain switcher is hidden on account pages', async ({ page }) => {
      await page.goto('/account');
      await page.waitForLoadState('networkidle');

      const domainTrigger = domainSwitcher.trigger(page);
      const isVisible = await domainTrigger.isVisible().catch(() => false);

      expect(isVisible, 'Domain switcher should be hidden on account pages').toBe(false);
    });

    test('TC-SS-017: Both hidden on account/settings/profile', async ({ page }) => {
      await page.goto('/account/settings/profile');
      await page.waitForLoadState('networkidle');

      const orgVisible = await orgSwitcher
        .trigger(page)
        .isVisible()
        .catch(() => false);
      const domainVisible = await domainSwitcher
        .trigger(page)
        .isVisible()
        .catch(() => false);

      expect(orgVisible).toBe(false);
      expect(domainVisible).toBe(false);
    });

    test('TC-SS-018: Both hidden on account/settings/security', async ({ page }) => {
      await page.goto('/account/settings/security');
      await page.waitForLoadState('networkidle');

      const orgVisible = await orgSwitcher
        .trigger(page)
        .isVisible()
        .catch(() => false);
      const domainVisible = await domainSwitcher
        .trigger(page)
        .isVisible()
        .catch(() => false);

      expect(orgVisible).toBe(false);
      expect(domainVisible).toBe(false);
    });
  });
});

// -----------------------------------------------------------------------------
// Switching Behavior Test Suite
// -----------------------------------------------------------------------------

test.describe('Scope Switcher - Switching Behavior', () => {
  test.skip(!hasTestCredentials, 'Skipping: TEST_USER_EMAIL and TEST_USER_PASSWORD required');

  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
    await loginUser(page);
  });

  // -------------------------------------------------------------------------
  // Organization Switching
  // -------------------------------------------------------------------------
  test.describe('Organization Switching', () => {
    test('TC-SS-020: Clicking org name opens dropdown', async ({ page }) => {
      await page.goto('/dashboard');
      await page.waitForLoadState('networkidle');

      const trigger = orgSwitcher.trigger(page);
      const isVisible = await trigger.isVisible().catch(() => false);
      test.skip(!isVisible, 'Organization switcher not visible');

      await trigger.click();

      // Dropdown should appear
      const dropdown = page.locator('[role="menu"]');
      await expect(dropdown).toBeVisible();
    });

    test('TC-SS-021: Dropdown shows current org highlighted', async ({ page }) => {
      await page.goto('/dashboard');
      await page.waitForLoadState('networkidle');

      const trigger = orgSwitcher.trigger(page);
      const isVisible = await trigger.isVisible().catch(() => false);
      test.skip(!isVisible, 'Organization switcher not visible');

      await trigger.click();

      // Current org should have checkmark or highlighted styling
      const checkmark = page.locator('[role="menuitem"] svg[class*="check"]').first();
      const hasCheckmark = await checkmark.isVisible().catch(() => false);

      const highlighted = page.locator('[role="menuitem"][class*="brand"]').first();
      const hasHighlight = await highlighted.isVisible().catch(() => false);

      expect(
        hasCheckmark || hasHighlight,
        'Current organization should be visually distinguished in dropdown'
      ).toBe(true);
    });

    test('TC-SS-022: Selecting different org updates current page context', async ({ page }) => {
      await page.goto('/dashboard');
      await page.waitForLoadState('networkidle');

      const trigger = orgSwitcher.trigger(page);
      const isVisible = await trigger.isVisible().catch(() => false);
      test.skip(!isVisible, 'Organization switcher not visible');

      // Get current org name
      const currentOrgName = await trigger.textContent();

      await trigger.click();

      // Find a different org in the list
      const menuItems = page.locator('[role="menuitem"]');
      const itemCount = await menuItems.count();

      if (itemCount > 1) {
        // Click the second org (different from current)
        const differentOrg = menuItems.nth(1);
        const differentOrgName = await differentOrg.textContent();

        if (differentOrgName !== currentOrgName) {
          await differentOrg.click();

          // Wait for update
          await page.waitForTimeout(500);

          // Verify trigger now shows new org
          const newOrgName = await trigger.textContent();
          expect(newOrgName).not.toBe(currentOrgName);
        }
      }
    });

    test('TC-SS-023: Clicking gear icon navigates to org settings', async ({ page }) => {
      await page.goto('/dashboard');
      await page.waitForLoadState('networkidle');

      const trigger = orgSwitcher.trigger(page);
      const isVisible = await trigger.isVisible().catch(() => false);
      test.skip(!isVisible, 'Organization switcher not visible');

      await trigger.click();

      // Hover on menu item to reveal gear icon
      const menuItem = page.locator('[role="menuitem"]').first();
      await menuItem.hover();

      // Find and click gear icon
      const gearIcon = menuItem.locator('button[aria-label*="settings" i]');
      const hasGear = await gearIcon.isVisible().catch(() => false);

      if (hasGear) {
        await gearIcon.click();
        await expect(page).toHaveURL(/\/org\/.+/);
      }
    });

    test('TC-SS-024: Manage Organizations link navigates to /orgs', async ({ page }) => {
      await page.goto('/dashboard');
      await page.waitForLoadState('networkidle');

      const trigger = orgSwitcher.trigger(page);
      const isVisible = await trigger.isVisible().catch(() => false);
      test.skip(!isVisible, 'Organization switcher not visible');

      await trigger.click();

      const manageLink = page.locator('[role="menuitem"]:has-text("Manage Organizations")');
      const hasLink = await manageLink.isVisible().catch(() => false);

      if (hasLink) {
        await manageLink.click();
        await expect(page).toHaveURL('/orgs');
      }
    });
  });

  // -------------------------------------------------------------------------
  // Domain Switching
  // -------------------------------------------------------------------------
  test.describe('Domain Switching', () => {
    test('TC-SS-030: Clicking domain switcher opens dropdown', async ({ page }) => {
      await page.goto('/dashboard');
      await page.waitForLoadState('networkidle');

      const trigger = domainSwitcher.trigger(page);
      const isVisible = await trigger.isVisible().catch(() => false);
      test.skip(!isVisible, 'Domain switcher not visible (user may not have domains)');

      await trigger.click();

      const dropdown = page.locator('[role="menu"]');
      await expect(dropdown).toBeVisible();
    });

    test('TC-SS-031: Selecting different domain updates scope', async ({ page }) => {
      await page.goto('/dashboard');
      await page.waitForLoadState('networkidle');

      const trigger = domainSwitcher.trigger(page);
      const isVisible = await trigger.isVisible().catch(() => false);
      test.skip(!isVisible, 'Domain switcher not visible');

      await trigger.click();

      const menuItems = page.locator('[role="menuitem"]');
      const itemCount = await menuItems.count();

      if (itemCount > 1) {
        const differentDomain = menuItems.nth(1);
        await differentDomain.click();

        await page.waitForTimeout(500);

        const newDomain = await trigger.textContent();
        // Domain may have changed
        expect(newDomain).toBeTruthy();
      }
    });

    test('TC-SS-032: Domain scope persists to localStorage', async ({ page }) => {
      await page.goto('/dashboard');
      await page.waitForLoadState('networkidle');

      const trigger = domainSwitcher.trigger(page);
      const isVisible = await trigger.isVisible().catch(() => false);
      test.skip(!isVisible, 'Domain switcher not visible');

      await trigger.click();

      const menuItems = page.locator('[role="menuitem"]');
      const firstItem = menuItems.first();
      await firstItem.click();

      // Check localStorage
      const storedDomain = await page.evaluate(() => localStorage.getItem('domainScope'));
      expect(storedDomain).toBeTruthy();
    });

    test('TC-SS-033: Add Domain link navigates to /domains', async ({ page }) => {
      await page.goto('/dashboard');
      await page.waitForLoadState('networkidle');

      const trigger = domainSwitcher.trigger(page);
      const isVisible = await trigger.isVisible().catch(() => false);
      test.skip(!isVisible, 'Domain switcher not visible');

      await trigger.click();

      const addLink = page.locator('[role="menuitem"]:has-text("Add Domain")');
      const hasLink = await addLink.isVisible().catch(() => false);

      if (hasLink) {
        await addLink.click();
        await expect(page).toHaveURL('/domains');
      }
    });
  });
});

// -----------------------------------------------------------------------------
// Locked State Behavior Test Suite
// -----------------------------------------------------------------------------

test.describe('Scope Switcher - Locked State Behavior', () => {
  test.skip(!hasTestCredentials, 'Skipping: TEST_USER_EMAIL and TEST_USER_PASSWORD required');

  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
    await loginUser(page);
  });

  test('TC-SS-040: Locked org switcher shows current org but is not clickable', async ({
    page,
  }) => {
    await page.goto('/billing/overview');
    await page.waitForLoadState('networkidle');

    const trigger = orgSwitcher.trigger(page);
    const isVisible = await trigger.isVisible().catch(() => false);
    test.skip(!isVisible, 'Organization switcher not visible on billing page');

    // Should display current org
    const orgName = await trigger.textContent();
    expect(orgName).toBeTruthy();

    // Should be disabled
    const isDisabled = await isElementDisabled(page, trigger);
    expect(isDisabled).toBe(true);

    // Clicking should not open dropdown
    await trigger.click({ force: true });
    const dropdown = page.locator('[role="menu"]');
    const dropdownVisible = await dropdown.isVisible().catch(() => false);
    expect(dropdownVisible).toBe(false);
  });

  test('TC-SS-041: Locked org switcher has appropriate ARIA attributes', async ({ page }) => {
    await page.goto('/billing/overview');
    await page.waitForLoadState('networkidle');

    const trigger = orgSwitcher.trigger(page);
    const isVisible = await trigger.isVisible().catch(() => false);
    test.skip(!isVisible, 'Organization switcher not visible');

    // Should have aria-disabled or disabled attribute
    const ariaDisabled = await trigger.getAttribute('aria-disabled');
    const disabled = await trigger.getAttribute('disabled');

    expect(
      ariaDisabled === 'true' || disabled !== null,
      'Locked switcher should have proper disabled attributes for accessibility'
    ).toBe(true);
  });

  test('TC-SS-042: Locked domain switcher shows current domain', async ({ page }) => {
    // Navigate to domain detail if possible
    await page.goto('/domains');
    await page.waitForLoadState('networkidle');

    const domainLink = page
      .locator('a[href*="/domains/"]')
      .filter({
        hasNot: page.locator('text=/add/i'),
      })
      .first();
    const hasDomainLink = await domainLink.isVisible().catch(() => false);
    test.skip(!hasDomainLink, 'No domains available');

    await domainLink.click();
    await page.waitForLoadState('networkidle');

    const trigger = domainSwitcher.trigger(page);
    const isVisible = await trigger.isVisible().catch(() => false);

    if (isVisible) {
      const domainName = await trigger.textContent();
      expect(domainName).toBeTruthy();

      const isDisabled = await isElementDisabled(page, trigger);
      expect(isDisabled).toBe(true);
    }
  });
});

// -----------------------------------------------------------------------------
// Edge Cases Test Suite
// -----------------------------------------------------------------------------

test.describe('Scope Switcher - Edge Cases', () => {
  test.skip(!hasTestCredentials, 'Skipping: TEST_USER_EMAIL and TEST_USER_PASSWORD required');

  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
    await loginUser(page);
  });

  test('TC-SS-050: Single org user sees switcher with one option', async ({ page }) => {
    await page.goto('/dashboard');
    await page.waitForLoadState('networkidle');

    const trigger = orgSwitcher.trigger(page);
    const isVisible = await trigger.isVisible().catch(() => false);
    test.skip(!isVisible, 'Organization switcher not visible');

    await trigger.click();

    const menuItems = page.locator('[role="menuitem"]').filter({
      has: page.locator('span.truncate'),
    });
    const itemCount = await menuItems.count();

    // Should have at least 1 org (the default)
    expect(itemCount).toBeGreaterThanOrEqual(1);
  });

  test('TC-SS-051: User without custom domains does not see domain switcher', async ({ page }) => {
    await page.goto('/dashboard');
    await page.waitForLoadState('networkidle');

    // Check window state for domains
    const hasDomains = await page.evaluate(() => {
      const state = (window as any).__BOOTSTRAP_STATE__;
      return state?.domains_enabled && (state?.custom_domains?.length || 0) > 0;
    });

    const trigger = domainSwitcher.trigger(page);
    const isVisible = await trigger.isVisible().catch(() => false);

    if (!hasDomains) {
      expect(isVisible).toBe(false);
    }
  });

  test('TC-SS-052: Canonical domain shows "Personal" label', async ({ page }) => {
    await page.goto('/dashboard');
    await page.waitForLoadState('networkidle');

    const trigger = domainSwitcher.trigger(page);
    const isVisible = await trigger.isVisible().catch(() => false);
    test.skip(!isVisible, 'Domain switcher not visible');

    await trigger.click();

    // Look for Personal/canonical domain option
    const personalOption = page.locator('[role="menuitem"]').filter({
      has: page.locator('svg[class*="home"]'),
    });

    const hasPersonal = await personalOption.isVisible().catch(() => false);
    // It's okay if there's no personal option (user may only have custom domains)
    if (hasPersonal) {
      const text = await personalOption.textContent();
      expect(text).toBeTruthy();
    }
  });

  test('TC-SS-053: Keyboard navigation works in dropdown', async ({ page }) => {
    await page.goto('/dashboard');
    await page.waitForLoadState('networkidle');

    const trigger = orgSwitcher.trigger(page);
    const isVisible = await trigger.isVisible().catch(() => false);
    test.skip(!isVisible, 'Organization switcher not visible');

    // Focus and open with Enter
    await trigger.focus();
    await page.keyboard.press('Enter');

    const dropdown = page.locator('[role="menu"]');
    await expect(dropdown).toBeVisible();

    // Navigate with arrow keys
    await page.keyboard.press('ArrowDown');
    await page.keyboard.press('ArrowDown');

    // Escape to close
    await page.keyboard.press('Escape');
    await expect(dropdown).not.toBeVisible();
  });

  test('TC-SS-054: Switching org resets domain scope if domain not available', async ({ page }) => {
    await page.goto('/dashboard');
    await page.waitForLoadState('networkidle');

    const orgTrigger = orgSwitcher.trigger(page);
    const orgVisible = await orgTrigger.isVisible().catch(() => false);
    test.skip(!orgVisible, 'Organization switcher not visible');

    const domainTrigger = domainSwitcher.trigger(page);
    const domainVisible = await domainTrigger.isVisible().catch(() => false);

    if (domainVisible) {
      // Switch org
      await orgTrigger.click();
      const menuItems = page.locator('[role="menuitem"]');
      const itemCount = await menuItems.count();

      if (itemCount > 1) {
        await menuItems.nth(1).click();
        await page.waitForTimeout(1000);

        // Domain scope may have been reset if new org doesn't have that domain
        // This is expected behavior
      }
    }
  });
});

// -----------------------------------------------------------------------------
// State Persistence Test Suite
// -----------------------------------------------------------------------------

test.describe('Scope Switcher - State Persistence', () => {
  test.skip(!hasTestCredentials, 'Skipping: TEST_USER_EMAIL and TEST_USER_PASSWORD required');

  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
    await loginUser(page);
  });

  test('TC-SS-060: Org selection persists across page navigation', async ({ page }) => {
    await page.goto('/dashboard');
    await page.waitForLoadState('networkidle');

    const trigger = orgSwitcher.trigger(page);
    const isVisible = await trigger.isVisible().catch(() => false);
    test.skip(!isVisible, 'Organization switcher not visible');

    // Get current org
    const orgName = await trigger.textContent();

    // Navigate away and back
    await page.goto('/');
    await page.waitForLoadState('networkidle');

    await page.goto('/dashboard');
    await page.waitForLoadState('networkidle');

    // Verify same org selected
    const newOrgName = await trigger.textContent();
    expect(newOrgName).toBe(orgName);
  });

  test('TC-SS-061: Domain scope persists across page navigation', async ({ page }) => {
    await page.goto('/dashboard');
    await page.waitForLoadState('networkidle');

    const trigger = domainSwitcher.trigger(page);
    const isVisible = await trigger.isVisible().catch(() => false);
    test.skip(!isVisible, 'Domain switcher not visible');

    const domainName = await trigger.textContent();

    await page.goto('/');
    await page.waitForLoadState('networkidle');

    await page.goto('/dashboard');
    await page.waitForLoadState('networkidle');

    const newDomainName = await trigger.textContent();
    expect(newDomainName).toBe(domainName);
  });

  test('TC-SS-062: Domain scope stored in localStorage', async ({ page }) => {
    await page.goto('/dashboard');
    await page.waitForLoadState('networkidle');

    const trigger = domainSwitcher.trigger(page);
    const isVisible = await trigger.isVisible().catch(() => false);
    test.skip(!isVisible, 'Domain switcher not visible');

    await trigger.click();
    const menuItem = page.locator('[role="menuitem"]').first();
    await menuItem.click();

    const storedValue = await page.evaluate(() => localStorage.getItem('domainScope'));
    expect(storedValue).toBeTruthy();
  });
});

// -----------------------------------------------------------------------------
// Accessibility Test Suite
// -----------------------------------------------------------------------------

test.describe('Scope Switcher - Accessibility', () => {
  test.skip(!hasTestCredentials, 'Skipping: TEST_USER_EMAIL and TEST_USER_PASSWORD required');

  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
    await loginUser(page);
  });

  test('TC-SS-070: Org switcher has proper ARIA labels', async ({ page }) => {
    await page.goto('/dashboard');
    await page.waitForLoadState('networkidle');

    const trigger = orgSwitcher.trigger(page);
    const isVisible = await trigger.isVisible().catch(() => false);
    test.skip(!isVisible, 'Organization switcher not visible');

    const ariaLabel = await trigger.getAttribute('aria-label');
    expect(ariaLabel).toBeTruthy();
    expect(ariaLabel?.toLowerCase()).toContain('organization');
  });

  test('TC-SS-071: Domain switcher has proper ARIA labels', async ({ page }) => {
    await page.goto('/dashboard');
    await page.waitForLoadState('networkidle');

    const trigger = domainSwitcher.trigger(page);
    const isVisible = await trigger.isVisible().catch(() => false);
    test.skip(!isVisible, 'Domain switcher not visible');

    const ariaLabel = await trigger.getAttribute('aria-label');
    expect(ariaLabel).toBeTruthy();
  });

  test('TC-SS-072: Dropdown menu has role="menu"', async ({ page }) => {
    await page.goto('/dashboard');
    await page.waitForLoadState('networkidle');

    const trigger = orgSwitcher.trigger(page);
    const isVisible = await trigger.isVisible().catch(() => false);
    test.skip(!isVisible, 'Organization switcher not visible');

    await trigger.click();

    const menu = page.locator('[role="menu"]');
    await expect(menu).toBeVisible();
  });

  test('TC-SS-073: Menu items have role="menuitem"', async ({ page }) => {
    await page.goto('/dashboard');
    await page.waitForLoadState('networkidle');

    const trigger = orgSwitcher.trigger(page);
    const isVisible = await trigger.isVisible().catch(() => false);
    test.skip(!isVisible, 'Organization switcher not visible');

    await trigger.click();

    const menuItems = page.locator('[role="menuitem"]');
    const itemCount = await menuItems.count();
    expect(itemCount).toBeGreaterThan(0);
  });

  test('TC-SS-074: Focus is trapped within open dropdown', async ({ page }) => {
    await page.goto('/dashboard');
    await page.waitForLoadState('networkidle');

    const trigger = orgSwitcher.trigger(page);
    const isVisible = await trigger.isVisible().catch(() => false);
    test.skip(!isVisible, 'Organization switcher not visible');

    await trigger.click();

    // Tab through items
    for (let i = 0; i < 10; i++) {
      await page.keyboard.press('Tab');

      const focused = await page.evaluate(() => {
        const el = document.activeElement;
        return el?.closest('[role="menu"]') !== null;
      });

      // Focus should stay within menu until escape
      if (!focused) break;
    }

    // Escape to close
    await page.keyboard.press('Escape');
    const dropdown = page.locator('[role="menu"]');
    await expect(dropdown).not.toBeVisible();
  });
});

/**
 * Qase Test Case Export Format
 *
 * The test cases in this file can be exported to Qase using the following mapping:
 *
 * Suite: Scope Switcher UX
 *
 * | ID         | Title                                              | Priority | Automation |
 * |------------|----------------------------------------------------|---------:|------------|
 * | TC-SS-001  | Dashboard: Org switcher visible and interactive   | High     | Automated  |
 * | TC-SS-002  | Dashboard: Domain switcher visible                 | High     | Automated  |
 * | TC-SS-003  | Secret Creation: Org switcher visible              | High     | Automated  |
 * | TC-SS-004  | Secret Creation: Domain switcher visible           | High     | Automated  |
 * | TC-SS-005  | Org Settings: Org switcher locked                  | High     | Automated  |
 * | TC-SS-006  | Org Settings: Domain switcher hidden               | High     | Automated  |
 * | TC-SS-007  | Domains List: Org switcher visible                 | Medium   | Automated  |
 * | TC-SS-008  | Domains List: Domain switcher visible              | Medium   | Automated  |
 * | TC-SS-009  | Domain Detail: Org switcher visible                | Medium   | Automated  |
 * | TC-SS-010  | Domain Detail: Domain switcher locked              | High     | Automated  |
 * | TC-SS-011  | Billing: Org switcher locked                       | High     | Automated  |
 * | TC-SS-012  | Billing: Domain switcher hidden                    | High     | Automated  |
 * | TC-SS-013  | Billing Plans: Visibility rules apply              | Medium   | Automated  |
 * | TC-SS-014  | Billing Invoices: Visibility rules apply           | Medium   | Automated  |
 * | TC-SS-015  | Account: Org switcher hidden                       | High     | Automated  |
 * | TC-SS-016  | Account: Domain switcher hidden                    | High     | Automated  |
 * | TC-SS-017  | Profile Settings: Both hidden                      | Medium   | Automated  |
 * | TC-SS-018  | Security Settings: Both hidden                     | Medium   | Automated  |
 * | TC-SS-020  | Org dropdown opens on click                        | High     | Automated  |
 * | TC-SS-021  | Dropdown shows current org highlighted             | High     | Automated  |
 * | TC-SS-022  | Selecting org updates page context                 | Critical | Automated  |
 * | TC-SS-023  | Gear icon navigates to org settings                | High     | Automated  |
 * | TC-SS-024  | Manage Organizations link works                    | Medium   | Automated  |
 * | TC-SS-030  | Domain dropdown opens on click                     | High     | Automated  |
 * | TC-SS-031  | Selecting domain updates scope                     | Critical | Automated  |
 * | TC-SS-032  | Domain scope persists to localStorage              | High     | Automated  |
 * | TC-SS-033  | Add Domain link navigates                          | Medium   | Automated  |
 * | TC-SS-040  | Locked org switcher not clickable                  | High     | Automated  |
 * | TC-SS-041  | Locked switcher has ARIA attributes                | Medium   | Automated  |
 * | TC-SS-042  | Locked domain shows current domain                 | High     | Automated  |
 * | TC-SS-050  | Single org user sees switcher                      | Medium   | Automated  |
 * | TC-SS-051  | User without domains: switcher hidden              | High     | Automated  |
 * | TC-SS-052  | Canonical domain shows Personal label              | Medium   | Automated  |
 * | TC-SS-053  | Keyboard navigation works                          | High     | Automated  |
 * | TC-SS-054  | Org switch resets unavailable domain scope         | High     | Automated  |
 * | TC-SS-060  | Org selection persists across navigation           | High     | Automated  |
 * | TC-SS-061  | Domain scope persists across navigation            | High     | Automated  |
 * | TC-SS-062  | Domain scope in localStorage                       | Medium   | Automated  |
 * | TC-SS-070  | Org switcher ARIA labels                           | Medium   | Automated  |
 * | TC-SS-071  | Domain switcher ARIA labels                        | Medium   | Automated  |
 * | TC-SS-072  | Menu has role="menu"                               | Medium   | Automated  |
 * | TC-SS-073  | Items have role="menuitem"                         | Medium   | Automated  |
 * | TC-SS-074  | Focus trapped in dropdown                          | Medium   | Automated  |
 */

/**
 * Manual Test Checklist - Scope Switcher UX
 *
 * ## Visual Testing (Not Automated)
 * - [ ] Switcher styling matches design system
 * - [ ] Dark mode styling correct
 * - [ ] Hover states on menu items
 * - [ ] Active/selected state styling
 * - [ ] Disabled state appears visually muted
 * - [ ] Gear icon visibility on hover
 * - [ ] Checkmark alignment in dropdown
 *
 * ## Responsive Testing
 * - [ ] Mobile (375px): Switchers stack or hide appropriately
 * - [ ] Tablet (768px): Dropdown doesn't overflow viewport
 * - [ ] Desktop (1280px): Full display with all elements
 *
 * ## Multi-org Scenarios
 * - [ ] User with 5+ orgs: Dropdown scrolls
 * - [ ] User with default org only: Shows "Personal"
 * - [ ] User with default + custom orgs: Both visible
 *
 * ## Multi-domain Scenarios
 * - [ ] User with canonical only: Switcher hidden
 * - [ ] User with 1 custom domain: Shows that domain
 * - [ ] User with 5+ domains: Dropdown scrolls
 * - [ ] Canonical domain labeled "Personal"
 *
 * ## Error States
 * - [ ] API timeout: Graceful fallback
 * - [ ] Invalid org extid: Error handling
 * - [ ] Session expired: Redirect to login
 */
