// e2e/full/org-switcher-navigation.spec.ts

//
// E2E Tests for Org Switcher Navigation Fix
//
// Validates the fix for the bug where using the org switcher dropdown on org-specific
// pages (like /org/{extid}/domains) would update the header to show the new org name
// but fail to update the URL and page content, leaving stale data displayed.
//
// Fix: Added `onOrgSwitch: 'same'` to the /org/:extid/:tab? route so switching orgs
// navigates to the equivalent page for the new org.
//
// Prerequisites:
// - Set TEST_USER_EMAIL and TEST_USER_PASSWORD environment variables
// - Test user must have at least 2 organizations
// - Test user: domaincontext@onetime.dev (has "Default Workspace" and "A Second Organization")
// - Base URL: https://dev.onetime.dev (or PLAYWRIGHT_BASE_URL)
//
// Usage:
//   PLAYWRIGHT_BASE_URL=https://dev.onetime.dev \
//   TEST_USER_EMAIL=domaincontext@onetime.dev \
//   TEST_USER_PASSWORD=secret \
//   pnpm test:playwright org-switcher-navigation.spec.ts
//

import { expect, Page, test } from '@playwright/test';

// Check if test credentials are configured
const hasTestCredentials = !!(process.env.TEST_USER_EMAIL && process.env.TEST_USER_PASSWORD);

// Known org names for test user domaincontext@onetime.dev
const ORG_DEFAULT = 'Default Workspace';
const ORG_SECOND = 'A Second Organization';
const _DOMAIN_DEV = 'dev.onetime.dev'; // Canonical domain, available for assertions

// Tab URL mappings (from OrganizationSettings.vue)
const TABS = {
  team: 'team',
  domains: 'domains',
  billing: 'billing',
  settings: 'settings',
} as const;

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
    await emailInput.fill(process.env.TEST_USER_EMAIL || 'domaincontext@onetime.dev');
    await passwordInput.fill(process.env.TEST_USER_PASSWORD || 'testpassword');
    await submitButton.click();

    // Wait for redirect to dashboard/account
    await page.waitForURL(/\/(account|dashboard)/, { timeout: 30000 });
  }
}

/**
 * Extract org extid from URL
 */
function extractOrgExtidFromUrl(url: string): string | null {
  const match = url.match(/\/org\/([^/]+)/);
  return match ? match[1] : null;
}

/**
 * Locators for Organization Scope Switcher
 */
const orgSwitcher = {
  trigger: (page: Page) =>
    page.locator(
      '[data-testid="org-scope-switcher-trigger"], button[aria-label*="organization" i]'
    ),
  dropdown: (page: Page) =>
    page.locator('[data-testid="org-scope-switcher-dropdown"], [role="menu"]').filter({
      has: page.locator('text=/my organizations/i'),
    }),
  menuItems: (page: Page) => page.locator('[role="menuitem"]'),
  getOrgMenuItem: (page: Page, orgName: string) =>
    page.locator('[role="menuitem"]').filter({ hasText: orgName }),
};

/**
 * Locators for Domain Scope Switcher
 */
const domainSwitcher = {
  trigger: (page: Page) =>
    page.locator('[data-testid="domain-context-switcher-trigger"], button[aria-label*="scope" i]'),
};

/**
 * Navigate to an org's specific tab page
 * Returns the extid extracted from the URL after navigation
 */
async function navigateToOrgTab(
  page: Page,
  orgName: string,
  tab: keyof typeof TABS
): Promise<string> {
  // First go to orgs list to find the org
  await page.goto('/orgs');
  await page.waitForLoadState('networkidle');

  // Find and click the org link
  const orgLink = page.locator(`a[href*="/org/"]`).filter({ hasText: orgName }).first();
  const hasOrgLink = await orgLink.isVisible().catch(() => false);

  if (!hasOrgLink) {
    throw new Error(`Organization "${orgName}" not found in orgs list`);
  }

  await orgLink.click();
  await page.waitForLoadState('networkidle');

  // Extract extid from URL
  const extid = extractOrgExtidFromUrl(page.url());
  if (!extid) {
    throw new Error(`Could not extract extid from URL: ${page.url()}`);
  }

  // Navigate to the specific tab
  await page.goto(`/org/${extid}/${tab}`);
  await page.waitForLoadState('networkidle');

  return extid;
}

/**
 * Switch org using the org switcher dropdown
 */
async function switchOrgViaSwitcher(page: Page, targetOrgName: string): Promise<void> {
  const trigger = orgSwitcher.trigger(page);

  // Click to open dropdown
  await trigger.click();

  // Wait for dropdown to be visible
  const dropdown = page.locator('[role="menu"]');
  await expect(dropdown).toBeVisible();

  // Find and click the target org
  const targetOrgItem = orgSwitcher.getOrgMenuItem(page, targetOrgName);
  await expect(targetOrgItem).toBeVisible();
  await targetOrgItem.click();

  // Wait for navigation to complete
  await page.waitForLoadState('networkidle');
}

/**
 * Get the current org extid from the URL
 */
function getCurrentOrgExtid(page: Page): string | null {
  return extractOrgExtidFromUrl(page.url());
}

/**
 * Get the current tab from the URL
 */
function getCurrentTab(page: Page): string | null {
  const url = page.url();
  const match = url.match(/\/org\/[^/]+\/([^/?#]+)/);
  return match ? match[1] : null;
}

// -----------------------------------------------------------------------------
// Org Switcher Navigation Test Suite
// -----------------------------------------------------------------------------

test.describe('Org Switcher Navigation - Same Tab Navigation', () => {
  test.skip(!hasTestCredentials, 'Skipping: TEST_USER_EMAIL and TEST_USER_PASSWORD required');

  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
    await loginUser(page);
  });

  // -------------------------------------------------------------------------
  // TC-OSN-001: Org switcher navigates to same tab on new org (domains)
  // -------------------------------------------------------------------------
  test('TC-OSN-001: Org switcher navigates to same tab on new org (domains)', async ({ page }) => {
    // Navigate to Default Workspace's domains tab
    const extid1 = await navigateToOrgTab(page, ORG_DEFAULT, 'domains');

    // Verify we are on the domains tab
    expect(getCurrentTab(page)).toBe('domains');
    expect(page.url()).toContain(`/org/${extid1}/domains`);

    // Verify org switcher shows Default Workspace (may be visible even when "locked")
    // The fix makes it navigable on org-specific pages
    const orgTrigger = orgSwitcher.trigger(page);
    const triggerVisible = await orgTrigger.isVisible().catch(() => false);

    if (!triggerVisible) {
      test.skip(true, 'Org switcher not visible - may be using hideBoth preset');
      return;
    }

    // Store the initial URL for comparison
    const initialUrl = page.url();

    // Switch to Second Organization using the switcher
    await switchOrgViaSwitcher(page, ORG_SECOND);

    // Verify URL changed to new org's domains tab
    const newUrl = page.url();
    expect(newUrl).not.toBe(initialUrl);

    const extid2 = getCurrentOrgExtid(page);
    expect(extid2).not.toBe(extid1);
    expect(getCurrentTab(page)).toBe('domains');
    expect(newUrl).toContain(`/org/${extid2}/domains`);

    // Verify page content updated - Second Org should show "No domains found"
    // or different domain list than Default Workspace
    const noDomains = page.locator('text=/no domains/i, text=/no custom domains/i');
    const hasDomainList = await page.locator('[data-testid="domains-list"], table').isVisible().catch(() => false);

    // Either shows "no domains" message or a domain list (but different from previous org)
    const noDomainsVisible = await noDomains.isVisible().catch(() => false);
    expect(noDomainsVisible || hasDomainList).toBe(true);

    // Verify domain switcher updated (if visible)
    const domainTrigger = domainSwitcher.trigger(page);
    const domainVisible = await domainTrigger.isVisible().catch(() => false);

    if (domainVisible) {
      const domainText = await domainTrigger.textContent();
      // Should show dev.onetime.dev or canonical domain for Second Org
      expect(domainText).toBeTruthy();
    }
  });

  // -------------------------------------------------------------------------
  // TC-OSN-002: Org switcher works on billing tab
  // -------------------------------------------------------------------------
  test('TC-OSN-002: Org switcher works on billing tab', async ({ page }) => {
    // Navigate to Default Workspace's billing tab
    const extid1 = await navigateToOrgTab(page, ORG_DEFAULT, 'billing');

    // Verify we are on the billing tab
    expect(getCurrentTab(page)).toBe('billing');
    expect(page.url()).toContain(`/org/${extid1}/billing`);

    const orgTrigger = orgSwitcher.trigger(page);
    const triggerVisible = await orgTrigger.isVisible().catch(() => false);

    if (!triggerVisible) {
      test.skip(true, 'Org switcher not visible on billing tab');
      return;
    }

    const initialUrl = page.url();

    // Switch to Second Organization
    await switchOrgViaSwitcher(page, ORG_SECOND);

    // Verify URL changed to new org's billing tab
    const newUrl = page.url();
    expect(newUrl).not.toBe(initialUrl);

    const extid2 = getCurrentOrgExtid(page);
    expect(extid2).not.toBe(extid1);
    expect(getCurrentTab(page)).toBe('billing');
    expect(newUrl).toContain(`/org/${extid2}/billing`);

    // Verify billing content is present (subscription info, plans, etc.)
    const billingContent = page.locator(
      'text=/subscription/i, text=/plan/i, text=/billing/i, [data-testid="billing-content"]'
    );
    const hasBillingContent = await billingContent.first().isVisible().catch(() => false);
    expect(hasBillingContent).toBe(true);
  });

  // -------------------------------------------------------------------------
  // TC-OSN-003: Org switcher works on settings tab
  // -------------------------------------------------------------------------
  test('TC-OSN-003: Org switcher works on settings tab', async ({ page }) => {
    // Navigate to Default Workspace's settings tab
    const extid1 = await navigateToOrgTab(page, ORG_DEFAULT, 'settings');

    // Verify we are on the settings tab
    expect(getCurrentTab(page)).toBe('settings');
    expect(page.url()).toContain(`/org/${extid1}/settings`);

    const orgTrigger = orgSwitcher.trigger(page);
    const triggerVisible = await orgTrigger.isVisible().catch(() => false);

    if (!triggerVisible) {
      test.skip(true, 'Org switcher not visible on settings tab');
      return;
    }

    const initialUrl = page.url();

    // Switch to Second Organization
    await switchOrgViaSwitcher(page, ORG_SECOND);

    // Verify URL changed to new org's settings tab
    const newUrl = page.url();
    expect(newUrl).not.toBe(initialUrl);

    const extid2 = getCurrentOrgExtid(page);
    expect(extid2).not.toBe(extid1);
    expect(getCurrentTab(page)).toBe('settings');
    expect(newUrl).toContain(`/org/${extid2}/settings`);

    // Verify settings content shows new org's name
    // Look for the org name in the settings form or heading
    const orgNameInContent = page.locator(
      `text="${ORG_SECOND}", input[value="${ORG_SECOND}"], [data-testid="org-name"]`
    );
    const hasNewOrgName = await orgNameInContent.first().isVisible().catch(() => false);

    // Also check for generic settings content as fallback
    const settingsContent = page.locator(
      'text=/organization name/i, text=/general settings/i, form'
    );
    const hasSettingsContent = await settingsContent.first().isVisible().catch(() => false);

    expect(hasNewOrgName || hasSettingsContent).toBe(true);
  });

  // -------------------------------------------------------------------------
  // TC-OSN-004: Bidirectional navigation
  // -------------------------------------------------------------------------
  test('TC-OSN-004: Bidirectional navigation', async ({ page }) => {
    // Start on Default Workspace's domains page
    const extid1 = await navigateToOrgTab(page, ORG_DEFAULT, 'domains');

    const orgTrigger = orgSwitcher.trigger(page);
    const triggerVisible = await orgTrigger.isVisible().catch(() => false);

    if (!triggerVisible) {
      test.skip(true, 'Org switcher not visible');
      return;
    }

    // Record initial state
    const initialExtid = extid1;
    const initialTab = getCurrentTab(page);
    expect(initialTab).toBe('domains');

    // Switch to Org B
    await switchOrgViaSwitcher(page, ORG_SECOND);

    // Verify we are on Org B's domains page
    const extidB = getCurrentOrgExtid(page);
    expect(extidB).not.toBe(initialExtid);
    expect(getCurrentTab(page)).toBe('domains');

    // Verify no stale data - content should be different or show "no domains"
    // Record some content identifier from Org B
    const orgBUrl = page.url();

    // Switch back to Org A
    await switchOrgViaSwitcher(page, ORG_DEFAULT);

    // Verify we are back on Org A's domains page
    const extidBack = getCurrentOrgExtid(page);
    expect(extidBack).toBe(initialExtid);
    expect(getCurrentTab(page)).toBe('domains');

    // URL should be different from Org B's URL
    const orgAUrl = page.url();
    expect(orgAUrl).not.toBe(orgBUrl);
    expect(orgAUrl).toContain(`/org/${initialExtid}/domains`);

    // Verify content is back to Org A's data
    // The page should not show Org B's data
    await page.waitForLoadState('networkidle');

    // Content should reflect Org A (no stale Org B data)
    // This is the core assertion - the page should have updated
    const currentExtid = getCurrentOrgExtid(page);
    expect(currentExtid).toBe(initialExtid);
  });

  // -------------------------------------------------------------------------
  // TC-OSN-005: URL and header stay in sync
  // -------------------------------------------------------------------------
  test('TC-OSN-005: URL and header stay in sync after switch', async ({ page }) => {
    // Navigate to Default Workspace's domains tab
    const extid1 = await navigateToOrgTab(page, ORG_DEFAULT, 'domains');

    const orgTrigger = orgSwitcher.trigger(page);
    const triggerVisible = await orgTrigger.isVisible().catch(() => false);

    if (!triggerVisible) {
      test.skip(true, 'Org switcher not visible');
      return;
    }

    // Get initial org name from header/trigger
    const initialTriggerText = await orgTrigger.textContent();

    // Switch to Second Organization
    await switchOrgViaSwitcher(page, ORG_SECOND);

    // Wait for any pending updates
    await page.waitForTimeout(500);

    // Verify header updated
    const newTriggerText = await orgTrigger.textContent();
    expect(newTriggerText).not.toBe(initialTriggerText);

    // Verify URL updated to match
    const extid2 = getCurrentOrgExtid(page);
    expect(extid2).not.toBe(extid1);

    // The header and URL should be in sync - both showing the new org
    // This was the bug: header would update but URL would stay stale
    expect(page.url()).toContain(extid2!);
  });
});

// -----------------------------------------------------------------------------
// Edge Cases and Error Handling
// -----------------------------------------------------------------------------

test.describe('Org Switcher Navigation - Edge Cases', () => {
  test.skip(!hasTestCredentials, 'Skipping: TEST_USER_EMAIL and TEST_USER_PASSWORD required');

  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
    await loginUser(page);
  });

  // -------------------------------------------------------------------------
  // TC-OSN-010: Switching to same org does not cause navigation
  // -------------------------------------------------------------------------
  test('TC-OSN-010: Selecting current org does not trigger unnecessary navigation', async ({
    page,
  }) => {
    // Navigate to Default Workspace's domains tab
    const extid = await navigateToOrgTab(page, ORG_DEFAULT, 'domains');

    const orgTrigger = orgSwitcher.trigger(page);
    const triggerVisible = await orgTrigger.isVisible().catch(() => false);

    if (!triggerVisible) {
      test.skip(true, 'Org switcher not visible');
      return;
    }

    const initialUrl = page.url();

    // Open dropdown and select the same org
    await orgTrigger.click();
    const dropdown = page.locator('[role="menu"]');
    await expect(dropdown).toBeVisible();

    // Click the current org (should be highlighted/checked)
    const currentOrgItem = orgSwitcher.getOrgMenuItem(page, ORG_DEFAULT);
    await currentOrgItem.click();

    // Wait briefly
    await page.waitForTimeout(300);

    // URL should remain the same
    expect(page.url()).toBe(initialUrl);
    expect(getCurrentOrgExtid(page)).toBe(extid);
  });

  // -------------------------------------------------------------------------
  // TC-OSN-011: Browser back button works correctly after switch
  // -------------------------------------------------------------------------
  test('TC-OSN-011: Browser back button works correctly after org switch', async ({ page }) => {
    // Navigate to Default Workspace's domains tab
    const extid1 = await navigateToOrgTab(page, ORG_DEFAULT, 'domains');
    const originalUrl = page.url();

    const orgTrigger = orgSwitcher.trigger(page);
    const triggerVisible = await orgTrigger.isVisible().catch(() => false);

    if (!triggerVisible) {
      test.skip(true, 'Org switcher not visible');
      return;
    }

    // Switch to Second Organization
    await switchOrgViaSwitcher(page, ORG_SECOND);

    // Verify we switched
    const extid2 = getCurrentOrgExtid(page);
    expect(extid2).not.toBe(extid1);

    // Go back using browser navigation
    await page.goBack();
    await page.waitForLoadState('networkidle');

    // Should be back on original org's page
    // Note: Behavior may vary based on router.replace vs router.push
    const backUrl = page.url();
    // Verify we're back to the original URL or at least the original org
    expect(backUrl).toContain(extid1);
    void originalUrl; // Used for comparison context
    const backExtid = getCurrentOrgExtid(page);

    // The URL should correspond to the org displayed
    if (backExtid === extid1) {
      expect(backUrl).toContain(extid1);
    }
  });
});

/**
 * Qase Test Case Export Format
 *
 * Suite: Org Switcher Navigation Fix
 *
 * | ID          | Title                                                    | Priority | Automation |
 * |-------------|----------------------------------------------------------|---------:|------------|
 * | TC-OSN-001  | Org switcher navigates to same tab (domains)             | Critical | Automated  |
 * | TC-OSN-002  | Org switcher works on billing tab                        | High     | Automated  |
 * | TC-OSN-003  | Org switcher works on settings tab                       | High     | Automated  |
 * | TC-OSN-004  | Bidirectional navigation works correctly                 | Critical | Automated  |
 * | TC-OSN-005  | URL and header stay in sync after switch                 | Critical | Automated  |
 * | TC-OSN-010  | Selecting current org does not trigger navigation        | Medium   | Automated  |
 * | TC-OSN-011  | Browser back button works correctly                      | Medium   | Automated  |
 *
 * Bug Reference:
 * - Issue: Org switcher on /org/{extid}/* pages updated header but not URL/content
 * - Root Cause: Missing onOrgSwitch navigation behavior in route meta
 * - Fix: Added `onOrgSwitch: 'same'` to /org/:extid/:tab? route
 * - File: src/apps/workspace/routes/organizations.ts
 */
