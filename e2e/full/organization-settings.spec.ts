// e2e/full/organization-settings.spec.ts

/**
 * E2E Tests for Organization Settings Pages
 *
 * Tests the organization management pages:
 * - /orgs (OrganizationsSettings) - List of all user organizations
 * - /org/:extid/:tab? (OrganizationSettings) - Single organization detail with tabs
 *
 * Key testids verified:
 * - OrganizationsSettings (/orgs):
 *   - organizations-list: Container for org cards
 *   - org-card-{extid}: Individual org card
 *   - org-link-{extid}: Clickable org name link
 *   - org-name: Display name text
 *
 * - OrganizationSettings (/org/:extid/:tab?):
 *   - org-tab-domains: Domains tab button
 *   - org-tab-subscription: Subscription tab button
 *   - org-tab-sso: SSO tab button (entitlement-gated)
 *   - org-tab-settings: Settings tab button
 *   - org-section-domains: Domains panel
 *   - org-section-subscription: Subscription panel
 *   - org-section-sso: SSO panel
 *   - org-section-settings: Settings panel
 *
 * Prerequisites:
 * - Set TEST_USER_EMAIL and TEST_USER_PASSWORD environment variables
 * - Test user must have at least one organization
 *
 * Usage:
 *   TEST_USER_EMAIL=user@example.com TEST_USER_PASSWORD=secret \
 *     pnpm test:playwright organization-settings.spec.ts
 */

import { expect, Page, test } from '@playwright/test';

// Check if test credentials are configured
const hasTestCredentials = !!(process.env.TEST_USER_EMAIL && process.env.TEST_USER_PASSWORD);

// -----------------------------------------------------------------------------
// Types
// -----------------------------------------------------------------------------

interface OrgInfo {
  extid: string;
  name: string;
}

// -----------------------------------------------------------------------------
// Test Helpers
// -----------------------------------------------------------------------------

/**
 * Authenticate user via login form
 */
async function loginUser(page: Page): Promise<void> {
  await page.goto('/signin');

  // Click Password tab - Magic Link is the default, password input is hidden
  const passwordTab = page.getByRole('tab', { name: /password/i });
  await passwordTab.waitFor({ state: 'visible', timeout: 5000 });
  await passwordTab.click();

  // Wait for password input to be visible after tab switch
  const passwordInput = page.locator('input[type="password"]');
  await passwordInput.waitFor({ state: 'visible', timeout: 5000 });

  // Fill the form
  const emailInput = page.locator('#signin-email-password');
  await emailInput.fill(process.env.TEST_USER_EMAIL || '');
  await passwordInput.fill(process.env.TEST_USER_PASSWORD || '');

  // Submit
  const submitButton = page.locator('button[type="submit"]');
  await submitButton.click();

  // Wait for redirect to dashboard/account
  await page.waitForURL(/\/(account|dashboard|org)/, { timeout: 30000 });
}

/**
 * Get the first organization from the /orgs page
 */
async function getFirstOrganization(page: Page): Promise<OrgInfo | null> {
  await page.goto('/orgs');
  await page.waitForLoadState('networkidle');

  const orgsList = page.getByTestId('organizations-list');
  const isOrgListVisible = await orgsList.isVisible().catch(() => false);

  if (!isOrgListVisible) {
    return null;
  }

  // Get the first org card
  const orgCard = orgsList.locator('[data-testid^="org-card-"]').first();
  if (!(await orgCard.isVisible().catch(() => false))) {
    return null;
  }

  // Extract extid from data-testid attribute
  const cardTestId = await orgCard.getAttribute('data-testid');
  const extid = cardTestId?.replace('org-card-', '') || '';

  // Get org name
  const orgNameElement = orgCard.getByTestId('org-name');
  const name = (await orgNameElement.textContent()) || '';

  return { extid, name: name.trim() };
}

/**
 * Extract current tab from URL
 */
function getCurrentTab(page: Page): string | null {
  const url = page.url();
  const match = url.match(/\/org\/[^/]+\/([^/?#]+)/);
  return match ? match[1] : null;
}

// -----------------------------------------------------------------------------
// Organizations List Page Tests (/orgs)
// -----------------------------------------------------------------------------

test.describe('ORG-LIST: Organizations List Page (/orgs)', () => {
  test.skip(!hasTestCredentials, 'Skipping: TEST_USER_EMAIL and TEST_USER_PASSWORD required');

  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
    await loginUser(page);
  });

  test('ORG-LIST-001: Organizations list renders with correct testids', async ({ page }) => {
    await page.goto('/orgs');
    await page.waitForLoadState('networkidle');

    // Verify organizations-list container exists
    const orgsList = page.getByTestId('organizations-list');
    const isLoading = page.locator('text=/loading/i');

    // Either we have orgs list or empty state (no loading spinner after networkidle)
    await expect(isLoading).not.toBeVisible({ timeout: 5000 }).catch(() => {
      // Loading may have completed before we checked
    });

    const hasOrgsList = await orgsList.isVisible().catch(() => false);
    const hasEmptyState = await page.locator('text=/no organizations/i').isVisible().catch(() => false);

    // One of these must be true
    expect(hasOrgsList || hasEmptyState).toBe(true);

    if (hasOrgsList) {
      // Verify at least one org card exists
      const orgCards = orgsList.locator('[data-testid^="org-card-"]');
      const cardCount = await orgCards.count();
      expect(cardCount).toBeGreaterThan(0);

      // Verify first card has expected testids
      const firstCard = orgCards.first();
      await expect(firstCard).toBeVisible();

      // Check for org-link-{extid}
      const orgLink = firstCard.locator('[data-testid^="org-link-"]');
      await expect(orgLink).toBeVisible();

      // Check for org-name
      const orgName = firstCard.getByTestId('org-name');
      await expect(orgName).toBeVisible();
      const nameText = await orgName.textContent();
      expect(nameText?.trim().length).toBeGreaterThan(0);
    }
  });

  test('ORG-LIST-002: Empty state displays when no organizations', async ({ page }) => {
    // This test verifies the empty state UI exists - it may not trigger for users with orgs
    await page.goto('/orgs');
    await page.waitForLoadState('networkidle');

    const orgsList = page.getByTestId('organizations-list');
    const hasOrgsList = await orgsList.isVisible().catch(() => false);

    if (!hasOrgsList) {
      // Verify empty state elements
      const emptyStateIcon = page.locator('[class*="building-office"], svg[class*="text-gray-400"]');
      const emptyStateText = page.locator('text=/no organizations/i');

      // At least the empty state message should be present
      await expect(emptyStateText).toBeVisible();

      // Create button should be visible in empty state
      const createButton = page.locator('button:has-text("Create")');
      await expect(createButton).toBeVisible();
    } else {
      // User has organizations - skip empty state verification
      test.skip(true, 'User has organizations - empty state not applicable');
    }
  });

  test('ORG-LIST-003: Navigation to org detail page works', async ({ page }) => {
    const org = await getFirstOrganization(page);

    if (!org) {
      test.skip(true, 'No organizations available for testing');
      return;
    }

    // Click the org link to navigate to detail page
    const orgLink = page.getByTestId(`org-link-${org.extid}`);
    await orgLink.click();

    // Verify navigation to org detail page
    await page.waitForURL(/\/org\/[^/]+/);
    expect(page.url()).toContain(`/org/${org.extid}`);

    // Verify org name is displayed on detail page
    await expect(page.locator(`text="${org.name}"`).first()).toBeVisible({ timeout: 10000 });
  });

  test('ORG-LIST-004: Org cards display plan badges correctly', async ({ page }) => {
    await page.goto('/orgs');
    await page.waitForLoadState('networkidle');

    const orgsList = page.getByTestId('organizations-list');
    const hasOrgsList = await orgsList.isVisible().catch(() => false);

    if (!hasOrgsList) {
      test.skip(true, 'No organizations available for testing');
      return;
    }

    // Get first org card
    const firstCard = orgsList.locator('[data-testid^="org-card-"]').first();

    // Check for badge presence (Pro, Early Supporter, or Default badge)
    const badges = firstCard.locator('span:has-text("PRO"), span:has-text("Early"), span:has-text("Default")');
    const badgeCount = await badges.count();

    // Badges are optional - just verify they render correctly if present
    if (badgeCount > 0) {
      const firstBadge = badges.first();
      await expect(firstBadge).toBeVisible();
    }
  });
});

// -----------------------------------------------------------------------------
// Organization Detail Page Tests (/org/:extid/:tab?)
// -----------------------------------------------------------------------------

test.describe('ORG-DETAIL: Organization Settings Page (/org/:extid/:tab?)', () => {
  test.skip(!hasTestCredentials, 'Skipping: TEST_USER_EMAIL and TEST_USER_PASSWORD required');

  let testOrg: OrgInfo | null = null;

  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
    await loginUser(page);
    testOrg = await getFirstOrganization(page);
  });

  test('ORG-DETAIL-001: Tab navigation structure renders correctly', async ({ page }) => {
    if (!testOrg) {
      test.skip(true, 'No organizations available for testing');
      return;
    }

    await page.goto(`/org/${testOrg.extid}`);
    await page.waitForLoadState('networkidle');

    // Verify tab buttons exist with correct testids
    const domainsTab = page.getByTestId('org-tab-domains');
    const subscriptionTab = page.getByTestId('org-tab-subscription');
    const settingsTab = page.getByTestId('org-tab-settings');

    await expect(domainsTab).toBeVisible();
    await expect(subscriptionTab).toBeVisible();
    await expect(settingsTab).toBeVisible();

    // SSO tab is entitlement-gated - may or may not be visible
    const ssoTab = page.getByTestId('org-tab-sso');
    const hasSsoTab = await ssoTab.isVisible().catch(() => false);

    // Verify tabs have correct ARIA attributes
    await expect(domainsTab).toHaveAttribute('role', 'tab');
    await expect(subscriptionTab).toHaveAttribute('role', 'tab');
    await expect(settingsTab).toHaveAttribute('role', 'tab');

    if (hasSsoTab) {
      await expect(ssoTab).toHaveAttribute('role', 'tab');
    }
  });

  test('ORG-DETAIL-002: Default tab is domains', async ({ page }) => {
    if (!testOrg) {
      test.skip(true, 'No organizations available for testing');
      return;
    }

    // Navigate without specifying tab
    await page.goto(`/org/${testOrg.extid}`);
    await page.waitForLoadState('networkidle');

    // Domains tab should be selected
    const domainsTab = page.getByTestId('org-tab-domains');
    await expect(domainsTab).toHaveAttribute('aria-selected', 'true');

    // Domains panel should be visible
    const domainsPanel = page.getByTestId('org-section-domains');
    await expect(domainsPanel).toBeVisible();
  });

  test('ORG-DETAIL-003: Domains tab navigation and panel', async ({ page }) => {
    if (!testOrg) {
      test.skip(true, 'No organizations available for testing');
      return;
    }

    await page.goto(`/org/${testOrg.extid}/domains`);
    await page.waitForLoadState('networkidle');

    // Verify tab is selected
    const domainsTab = page.getByTestId('org-tab-domains');
    await expect(domainsTab).toHaveAttribute('aria-selected', 'true');

    // Verify panel is visible
    const domainsPanel = page.getByTestId('org-section-domains');
    await expect(domainsPanel).toBeVisible();

    // Panel should have correct ARIA attributes
    await expect(domainsPanel).toHaveAttribute('role', 'tabpanel');
    await expect(domainsPanel).toHaveAttribute('aria-labelledby', 'org-tab-domains');

    // Verify "Add Domain" button is visible
    const addDomainButton = domainsPanel.locator('a:has-text("Add")');
    await expect(addDomainButton).toBeVisible();
  });

  test('ORG-DETAIL-004: Subscription tab navigation and panel', async ({ page }) => {
    if (!testOrg) {
      test.skip(true, 'No organizations available for testing');
      return;
    }

    await page.goto(`/org/${testOrg.extid}/subscription`);
    await page.waitForLoadState('networkidle');

    // Verify tab is selected
    const subscriptionTab = page.getByTestId('org-tab-subscription');
    await expect(subscriptionTab).toHaveAttribute('aria-selected', 'true');

    // Verify panel is visible
    const subscriptionPanel = page.getByTestId('org-section-subscription');
    await expect(subscriptionPanel).toBeVisible();

    // Panel should have content (billing info or "coming soon")
    const hasSubscriptionContent =
      (await page.locator('text=/subscription|plan|billing|coming soon/i').first().isVisible().catch(() => false));
    expect(hasSubscriptionContent).toBe(true);
  });

  test('ORG-DETAIL-005: Settings tab navigation and panel', async ({ page }) => {
    if (!testOrg) {
      test.skip(true, 'No organizations available for testing');
      return;
    }

    await page.goto(`/org/${testOrg.extid}/settings`);
    await page.waitForLoadState('networkidle');

    // Verify tab is selected
    const settingsTab = page.getByTestId('org-tab-settings');
    await expect(settingsTab).toHaveAttribute('aria-selected', 'true');

    // Verify panel is visible
    const settingsPanel = page.getByTestId('org-section-settings');
    await expect(settingsPanel).toBeVisible();

    // Settings panel should have form elements
    const displayNameInput = settingsPanel.locator('input#display-name');
    await expect(displayNameInput).toBeVisible();

    // Verify org name is in the input
    const inputValue = await displayNameInput.inputValue();
    expect(inputValue).toBe(testOrg.name);
  });

  test('ORG-DETAIL-006: SSO tab (entitlement-gated)', async ({ page }) => {
    if (!testOrg) {
      test.skip(true, 'No organizations available for testing');
      return;
    }

    await page.goto(`/org/${testOrg.extid}`);
    await page.waitForLoadState('networkidle');

    const ssoTab = page.getByTestId('org-tab-sso');
    const hasSsoTab = await ssoTab.isVisible().catch(() => false);

    if (!hasSsoTab) {
      test.skip(true, 'SSO tab not visible - user may not have manage_sso entitlement');
      return;
    }

    // Click SSO tab
    await ssoTab.click();
    await page.waitForLoadState('networkidle');

    // Verify tab is selected
    await expect(ssoTab).toHaveAttribute('aria-selected', 'true');

    // Verify URL updated
    expect(page.url()).toContain('/sso');

    // Verify SSO panel is visible
    const ssoPanel = page.getByTestId('org-section-sso');
    await expect(ssoPanel).toBeVisible();
  });

  test('ORG-DETAIL-007: Tab click updates URL', async ({ page }) => {
    if (!testOrg) {
      test.skip(true, 'No organizations available for testing');
      return;
    }

    await page.goto(`/org/${testOrg.extid}`);
    await page.waitForLoadState('networkidle');

    // Click subscription tab
    const subscriptionTab = page.getByTestId('org-tab-subscription');
    await subscriptionTab.click();
    await page.waitForLoadState('networkidle');

    expect(page.url()).toContain('/subscription');
    expect(getCurrentTab(page)).toBe('subscription');

    // Click settings tab
    const settingsTab = page.getByTestId('org-tab-settings');
    await settingsTab.click();
    await page.waitForLoadState('networkidle');

    expect(page.url()).toContain('/settings');
    expect(getCurrentTab(page)).toBe('settings');

    // Click domains tab
    const domainsTab = page.getByTestId('org-tab-domains');
    await domainsTab.click();
    await page.waitForLoadState('networkidle');

    expect(page.url()).toContain('/domains');
    expect(getCurrentTab(page)).toBe('domains');
  });

  test('ORG-DETAIL-008: Back navigation to /orgs works', async ({ page }) => {
    if (!testOrg) {
      test.skip(true, 'No organizations available for testing');
      return;
    }

    await page.goto(`/org/${testOrg.extid}`);
    await page.waitForLoadState('networkidle');

    // Find the back link (arrow-left icon with org name)
    const backLink = page.locator('a[href="/orgs"]');
    await expect(backLink).toBeVisible();

    // Click back link
    await backLink.click();
    await page.waitForURL('/orgs');

    // Verify we're on the orgs list page
    expect(page.url()).toContain('/orgs');
  });

  test('ORG-DETAIL-009: Direct URL navigation to specific tabs works', async ({ page }) => {
    if (!testOrg) {
      test.skip(true, 'No organizations available for testing');
      return;
    }

    // Test direct navigation to each tab
    const tabs = [
      { url: 'domains', testid: 'org-section-domains' },
      { url: 'subscription', testid: 'org-section-subscription' },
      { url: 'settings', testid: 'org-section-settings' },
    ];

    for (const tab of tabs) {
      await page.goto(`/org/${testOrg.extid}/${tab.url}`);
      await page.waitForLoadState('networkidle');

      const panel = page.getByTestId(tab.testid);
      await expect(panel).toBeVisible({ timeout: 10000 });
    }
  });

  test('ORG-DETAIL-010: Browser back/forward navigation preserves tab state', async ({ page }) => {
    if (!testOrg) {
      test.skip(true, 'No organizations available for testing');
      return;
    }

    // Start on domains tab
    await page.goto(`/org/${testOrg.extid}/domains`);
    await page.waitForLoadState('networkidle');

    // Navigate to subscription tab
    const subscriptionTab = page.getByTestId('org-tab-subscription');
    await subscriptionTab.click();
    await page.waitForURL(/\/subscription/);

    // Navigate to settings tab
    const settingsTab = page.getByTestId('org-tab-settings');
    await settingsTab.click();
    await page.waitForURL(/\/settings/);

    // Go back to subscription
    await page.goBack();
    await page.waitForLoadState('networkidle');
    expect(getCurrentTab(page)).toBe('subscription');

    // Go back to domains
    await page.goBack();
    await page.waitForLoadState('networkidle');
    expect(getCurrentTab(page)).toBe('domains');

    // Go forward to subscription
    await page.goForward();
    await page.waitForLoadState('networkidle');
    expect(getCurrentTab(page)).toBe('subscription');
  });
});

// -----------------------------------------------------------------------------
// Organization Not Found Error State
// -----------------------------------------------------------------------------

test.describe('ORG-ERROR: Organization Error States', () => {
  test.skip(!hasTestCredentials, 'Skipping: TEST_USER_EMAIL and TEST_USER_PASSWORD required');

  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
    await loginUser(page);
  });

  test('ORG-ERROR-001: Invalid org extid shows error state', async ({ page }) => {
    // Navigate to a non-existent org
    await page.goto('/org/invalid-org-id-12345');
    await page.waitForLoadState('networkidle');

    // Should show error state, not tabs
    const domainsTab = page.getByTestId('org-tab-domains');
    const hasDomainsTab = await domainsTab.isVisible().catch(() => false);
    expect(hasDomainsTab).toBe(false);

    // Error icon or message should be visible
    const errorIndicator = page.locator('text=/not found|error|could not/i');
    await expect(errorIndicator.first()).toBeVisible();

    // Back link to /orgs should be present
    const backLink = page.locator('a[href="/orgs"]');
    await expect(backLink).toBeVisible();
  });
});

// -----------------------------------------------------------------------------
// Keyboard Accessibility
// -----------------------------------------------------------------------------

test.describe('ORG-A11Y: Organization Settings Accessibility', () => {
  test.skip(!hasTestCredentials, 'Skipping: TEST_USER_EMAIL and TEST_USER_PASSWORD required');

  let testOrg: OrgInfo | null = null;

  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
    await loginUser(page);
    testOrg = await getFirstOrganization(page);
  });

  test('ORG-A11Y-001: Tab navigation with keyboard (Arrow keys)', async ({ page }) => {
    if (!testOrg) {
      test.skip(true, 'No organizations available for testing');
      return;
    }

    await page.goto(`/org/${testOrg.extid}`);
    await page.waitForLoadState('networkidle');

    // Focus the domains tab
    const domainsTab = page.getByTestId('org-tab-domains');
    await domainsTab.focus();

    // Press ArrowRight to move to next tab
    await page.keyboard.press('ArrowRight');

    // Subscription tab should now be focused
    const subscriptionTab = page.getByTestId('org-tab-subscription');
    await expect(subscriptionTab).toBeFocused();

    // Press ArrowRight again
    await page.keyboard.press('ArrowRight');

    // Next visible tab should be focused (either SSO or Settings)
    const ssoTab = page.getByTestId('org-tab-sso');
    const hasSsoTab = await ssoTab.isVisible().catch(() => false);

    if (hasSsoTab) {
      await expect(ssoTab).toBeFocused();
    } else {
      const settingsTab = page.getByTestId('org-tab-settings');
      await expect(settingsTab).toBeFocused();
    }
  });

  test('ORG-A11Y-002: Tab panels have correct ARIA attributes', async ({ page }) => {
    if (!testOrg) {
      test.skip(true, 'No organizations available for testing');
      return;
    }

    await page.goto(`/org/${testOrg.extid}/domains`);
    await page.waitForLoadState('networkidle');

    // Verify tabpanel role
    const domainsPanel = page.getByTestId('org-section-domains');
    await expect(domainsPanel).toHaveAttribute('role', 'tabpanel');

    // Navigate to settings
    await page.goto(`/org/${testOrg.extid}/settings`);
    await page.waitForLoadState('networkidle');

    const settingsPanel = page.getByTestId('org-section-settings');
    await expect(settingsPanel).toHaveAttribute('role', 'tabpanel');
    await expect(settingsPanel).toHaveAttribute('tabindex', '0');
  });
});

/**
 * Test Case Reference (Qase-compatible)
 *
 * Suite: Organization Settings Pages
 *
 * | ID              | Title                                          | Priority   | Automation |
 * |-----------------|------------------------------------------------|------------|------------|
 * | ORG-LIST-001    | Organizations list renders with correct testids| Critical   | Automated  |
 * | ORG-LIST-002    | Empty state displays when no organizations     | Medium     | Automated  |
 * | ORG-LIST-003    | Navigation to org detail page works            | Critical   | Automated  |
 * | ORG-LIST-004    | Org cards display plan badges correctly        | Low        | Automated  |
 * | ORG-DETAIL-001  | Tab navigation structure renders correctly     | Critical   | Automated  |
 * | ORG-DETAIL-002  | Default tab is domains                         | High       | Automated  |
 * | ORG-DETAIL-003  | Domains tab navigation and panel               | Critical   | Automated  |
 * | ORG-DETAIL-004  | Subscription tab navigation and panel          | High       | Automated  |
 * | ORG-DETAIL-005  | Settings tab navigation and panel              | High       | Automated  |
 * | ORG-DETAIL-006  | SSO tab (entitlement-gated)                    | Medium     | Automated  |
 * | ORG-DETAIL-007  | Tab click updates URL                          | Critical   | Automated  |
 * | ORG-DETAIL-008  | Back navigation to /orgs works                 | High       | Automated  |
 * | ORG-DETAIL-009  | Direct URL navigation to specific tabs works   | High       | Automated  |
 * | ORG-DETAIL-010  | Browser back/forward preserves tab state       | Medium     | Automated  |
 * | ORG-ERROR-001   | Invalid org extid shows error state            | High       | Automated  |
 * | ORG-A11Y-001    | Tab navigation with keyboard (Arrow keys)      | Medium     | Automated  |
 * | ORG-A11Y-002    | Tab panels have correct ARIA attributes        | Medium     | Automated  |
 */
