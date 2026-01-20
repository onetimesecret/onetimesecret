// e2e/full/domains-store-org-cache.spec.ts

/**
 * E2E Tests for DomainsStore Organization Context Cache Fix
 *
 * Tests the fix for a bug where the domainsStore used a single `_initialized` boolean
 * but never tracked which organization the cached data belonged to. Once domains were
 * loaded for Org A, navigating to Org B's page would return cached Org A data.
 *
 * Fix: Added `_currentOrgId` tracking to domainsStore that re-fetches when the
 * requested org differs from the cached org.
 *
 * Prerequisites:
 * - TEST_USER_EMAIL=domaincontext@onetime.dev
 * - TEST_USER_PASSWORD from environment variable
 * - User must have 2 organizations:
 *   - "Default Workspace" with custom domains
 *   - "A Second Organization" with no custom domains
 * - Application running at https://dev.onetime.dev or PLAYWRIGHT_BASE_URL set
 *
 * Usage:
 *   PLAYWRIGHT_BASE_URL=https://dev.onetime.dev \
 *   TEST_USER_EMAIL=domaincontext@onetime.dev \
 *   TEST_USER_PASSWORD=secret \
 *     pnpm playwright test domains-store-org-cache.spec.ts
 */

import { expect, Page, Request, test } from '@playwright/test';

// Check if test credentials are configured
const hasTestCredentials = !!(process.env.TEST_USER_EMAIL && process.env.TEST_USER_PASSWORD);

// Test user should be domaincontext@onetime.dev per requirements
const TEST_USER_EMAIL = process.env.TEST_USER_EMAIL || 'domaincontext@onetime.dev';

// -----------------------------------------------------------------------------
// Types
// -----------------------------------------------------------------------------

interface OrgInfo {
  extid: string;
  name: string;
  hasDomains: boolean;
}

interface ApiCallInfo {
  url: string;
  method: string;
  orgId: string | null;
  timestamp: number;
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

  // Now fill the form (email input is in the password tab panel)
  const emailInput = page.locator('#signin-email-password');
  await emailInput.fill(TEST_USER_EMAIL);
  await passwordInput.fill(process.env.TEST_USER_PASSWORD || '');

  // Submit
  const submitButton = page.locator('button[type="submit"]');
  await submitButton.click();

  // Wait for redirect to dashboard/account
  await page.waitForURL(/\/(account|dashboard|org)/, { timeout: 30000 });
}

/**
 * Get list of organizations the user has access to
 * Returns array of org info with extid and name
 */
async function getUserOrganizations(page: Page): Promise<OrgInfo[]> {
  // Navigate to orgs list
  await page.goto('/orgs');

  // Wait for organizations list to load using test ID
  const orgsList = page.getByTestId('organizations-list');
  await orgsList.waitFor({ state: 'visible', timeout: 10000 });

  // Find all organization cards using test ID pattern
  const orgCards = orgsList.locator('[data-testid^="org-card-"]');
  const count = await orgCards.count();

  const orgs: OrgInfo[] = [];

  for (let i = 0; i < count; i++) {
    const card = orgCards.nth(i);
    const testId = await card.getAttribute('data-testid');
    const extid = testId?.replace('org-card-', '') || '';

    if (extid) {
      // Get org name from the org-name test ID element
      const nameElement = card.getByTestId('org-name');
      const name = (await nameElement.textContent())?.trim() || extid;

      orgs.push({
        extid,
        name,
        hasDomains: false, // Will be determined later
      });
    }
  }

  return orgs;
}

/**
 * Find org by name pattern (case-insensitive partial match)
 */
function findOrgByName(orgs: OrgInfo[], namePattern: string): OrgInfo | undefined {
  const lowerPattern = namePattern.toLowerCase();
  return orgs.find((org) => org.name.toLowerCase().includes(lowerPattern));
}

/**
 * Check if domain switcher shows custom domains
 * Returns true if custom domains are visible in the switcher
 * @internal Helper function available for future test expansion
 */
async function domainSwitcherHasCustomDomains(page: Page): Promise<boolean> {
  // Look for domain switcher trigger using test ID
  const domainTrigger = page.getByTestId('domain-context-switcher-trigger');

  const isVisible = await domainTrigger.isVisible().catch(() => false);
  if (!isVisible) {
    return false;
  }

  // Open the dropdown
  await domainTrigger.click();

  // Wait for dropdown to appear using test ID
  const dropdown = page.getByTestId('domain-context-switcher-dropdown');
  await dropdown.waitFor({ state: 'visible', timeout: 5000 }).catch(() => {});

  // Check if there are domain menu items beyond just the canonical domain
  // Custom domains would have domain-like text (e.g., something.com)
  const menuItems = dropdown.locator('[role="menuitem"]');
  const itemCount = await menuItems.count();

  // Check if any menu item contains a custom domain (not just dev.onetime.dev)
  let hasCustom = false;
  for (let i = 0; i < itemCount; i++) {
    const text = await menuItems.nth(i).textContent();
    // Custom domain would be a domain that's not the canonical one
    if (text && !text.includes('dev.onetime.dev') && /\.[a-z]{2,}$/i.test(text.trim())) {
      hasCustom = true;
      break;
    }
  }

  // Close dropdown by pressing Escape or clicking elsewhere
  await page.keyboard.press('Escape');

  return hasCustom;
}

// Expose helper for potential future use (suppresses unused warning)
void domainSwitcherHasCustomDomains;

/**
 * Get all domain names visible in the domain switcher dropdown
 */
async function getDomainSwitcherDomains(page: Page): Promise<string[]> {
  const domainTrigger = page.getByTestId('domain-context-switcher-trigger');

  const isVisible = await domainTrigger.isVisible().catch(() => false);
  if (!isVisible) {
    return ['dev.onetime.dev']; // Return canonical only if no switcher
  }

  await domainTrigger.click();

  const dropdown = page.getByTestId('domain-context-switcher-dropdown');
  await dropdown.waitFor({ state: 'visible', timeout: 5000 }).catch(() => {});

  const menuItems = dropdown.locator('[role="menuitem"]');
  const itemCount = await menuItems.count();

  const domains: string[] = [];
  for (let i = 0; i < itemCount; i++) {
    const text = await menuItems.nth(i).textContent();
    if (text) {
      // Extract domain-like text
      const domainMatch = text.match(/([a-z0-9-]+\.)+[a-z]{2,}/i);
      if (domainMatch) {
        domains.push(domainMatch[0]);
      }
    }
  }

  await page.keyboard.press('Escape');

  return domains.length > 0 ? domains : ['dev.onetime.dev'];
}

/**
 * Check if empty domains state is shown on the Manage Domains page
 */
async function isEmptyDomainsState(page: Page): Promise<boolean> {
  const emptyState = page.getByText(/no domains found|get started by adding/i);
  return emptyState.isVisible().catch(() => false);
}

/**
 * Check if domains table has custom domain entries
 */
async function hasDomainsInTable(page: Page): Promise<boolean> {
  const table = page.locator('table');
  const tableVisible = await table.isVisible().catch(() => false);
  if (!tableVisible) {
    return false;
  }

  // Look for domain links in the table
  const domainLinks = page.locator('table a[class*="brandcomp"], table a[href*="/domains/"]');
  const count = await domainLinks.count();
  return count > 0;
}

/**
 * Extract org_id from API request URL or params
 */
function extractOrgIdFromRequest(request: Request): string | null {
  const url = request.url();

  // Check URL path pattern /org/{extid}
  const pathMatch = url.match(/\/org\/([^/]+)/);
  if (pathMatch) {
    return pathMatch[1];
  }

  // Check query parameter org_id=xxx
  const urlObj = new URL(url);
  const orgIdParam = urlObj.searchParams.get('org_id');
  if (orgIdParam) {
    return orgIdParam;
  }

  return null;
}

// -----------------------------------------------------------------------------
// Test Suite: DomainsStore Org Context Cache Fix
// -----------------------------------------------------------------------------

test.describe('DomainsStore Org Context Cache Fix', () => {
  test.skip(!hasTestCredentials, 'Skipping: TEST_USER_EMAIL and TEST_USER_PASSWORD required');

  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
    await loginUser(page);
  });

  // ---------------------------------------------------------------------------
  // TC-DSC-001: Domain switcher updates when navigating between orgs via URL
  // ---------------------------------------------------------------------------
  test.describe('TC-DSC-001: Domain Switcher Updates on URL Navigation', () => {
    test('Domain switcher shows correct domains when navigating between orgs', async ({ page }) => {
      // Get user organizations
      const orgs = await getUserOrganizations(page);
      test.skip(orgs.length < 2, 'Test requires user with at least 2 organizations');

      // Find Default Workspace (has domains) and A Second Organization (no domains)
      const defaultWorkspace = findOrgByName(orgs, 'Default Workspace');
      const secondOrg = findOrgByName(orgs, 'Second Organization');

      if (!defaultWorkspace || !secondOrg) {
        // Fall back to first two orgs if named orgs not found
        test.skip(
          true,
          'Test requires "Default Workspace" with domains and "A Second Organization" without domains'
        );
        return;
      }

      // Step 1: Navigate to Default Workspace dashboard
      await page.goto('/dashboard');
      await page.waitForLoadState('networkidle');

      // Wait for domain switcher to be ready
      const domainSwitcherTrigger = page.locator(
        '[data-testid="domain-context-switcher-trigger"], button[aria-label*="scope" i]'
      );
      await domainSwitcherTrigger.or(page.locator('body')).first().waitFor({ state: 'visible' });

      // Record domains visible in switcher for Default Workspace
      const defaultDomains = await getDomainSwitcherDomains(page);
      const hasCustomInDefault = defaultDomains.some((d) => d !== 'dev.onetime.dev');

      // Step 2: Navigate to A Second Organization's page via URL
      // Wait for domains API response to ensure store has re-fetched
      const domainsResponsePromise = page.waitForResponse(
        (resp) => resp.url().includes('/api/') && resp.url().includes('domains') && resp.status() === 200,
        { timeout: 10000 }
      ).catch(() => null); // Don't fail if no domains API call (empty org)

      await page.goto(`/org/${secondOrg.extid}`);
      await page.waitForLoadState('networkidle');
      await domainsResponsePromise;

      // Verify domain switcher now shows only canonical domain (no custom domains)
      const secondOrgDomains = await getDomainSwitcherDomains(page);

      // Second org should only show dev.onetime.dev (no custom domains)
      expect(
        secondOrgDomains.every((d) => d === 'dev.onetime.dev'),
        `A Second Organization should only show dev.onetime.dev, got: ${secondOrgDomains.join(', ')}`
      ).toBe(true);

      // Verify Default Workspace's custom domains are NOT showing
      if (hasCustomInDefault) {
        const customFromDefault = defaultDomains.filter((d) => d !== 'dev.onetime.dev');
        for (const domain of customFromDefault) {
          expect(
            secondOrgDomains,
            `Domain "${domain}" from Default Workspace should NOT appear in A Second Organization`
          ).not.toContain(domain);
        }
      }

      // Step 3: Navigate back to Default Workspace dashboard
      // Wait for domains API response on return navigation
      const returnDomainsPromise = page.waitForResponse(
        (resp) => resp.url().includes('/api/') && resp.url().includes('domains') && resp.status() === 200,
        { timeout: 10000 }
      ).catch(() => null);

      await page.goto('/dashboard');
      await page.waitForLoadState('networkidle');
      await returnDomainsPromise;

      // Verify domain switcher shows custom domains again
      const returnedDomains = await getDomainSwitcherDomains(page);

      if (hasCustomInDefault) {
        expect(
          returnedDomains.some((d) => d !== 'dev.onetime.dev'),
          'Default Workspace should show custom domains after returning'
        ).toBe(true);
      }
    });
  });

  // ---------------------------------------------------------------------------
  // TC-DSC-002: Manage Domains page shows correct domains per org
  // ---------------------------------------------------------------------------
  test.describe('TC-DSC-002: Manage Domains Page Per-Org Isolation', () => {
    test('Manage Domains page shows correct domains for each organization', async ({ page }) => {
      // Get user organizations
      const orgs = await getUserOrganizations(page);
      test.skip(orgs.length < 2, 'Test requires user with at least 2 organizations');

      // Find named orgs
      const defaultWorkspace = findOrgByName(orgs, 'Default Workspace');
      const secondOrg = findOrgByName(orgs, 'Second Organization');

      if (!defaultWorkspace || !secondOrg) {
        test.skip(
          true,
          'Test requires "Default Workspace" with domains and "A Second Organization" without domains'
        );
        return;
      }

      // Step 1: Navigate to Default Workspace's Manage Domains page
      await page.goto(`/org/${defaultWorkspace.extid}/domains`);
      await page.waitForLoadState('networkidle');

      // Verify custom domains are listed
      const hasDomainsInDefault = await hasDomainsInTable(page);
      expect(hasDomainsInDefault, 'Default Workspace should have custom domains listed').toBe(true);

      // Record the domains we see
      const domainLinksDefault = page.locator(
        'table a[class*="brandcomp"], table a[href*="/domains/"]'
      );
      const defaultDomainNames: string[] = [];
      const defaultCount = await domainLinksDefault.count();
      for (let i = 0; i < defaultCount; i++) {
        const text = await domainLinksDefault.nth(i).textContent();
        if (text) defaultDomainNames.push(text.trim());
      }

      // Step 2: Navigate directly to A Second Organization's domains page via URL
      await page.goto(`/org/${secondOrg.extid}/domains`);
      await page.waitForLoadState('networkidle');

      // Verify "No domains found" empty state is shown
      const isEmpty = await isEmptyDomainsState(page);
      expect(isEmpty, 'A Second Organization should show empty state (No domains found)').toBe(
        true
      );

      // Verify NO domains from Default Workspace appear
      for (const domainName of defaultDomainNames) {
        const domainOnPage = page.locator(`text=${domainName}`).first();
        await expect(
          domainOnPage,
          `Domain "${domainName}" from Default Workspace should NOT appear in A Second Organization's domains page`
        ).not.toBeVisible();
      }
    });
  });

  // ---------------------------------------------------------------------------
  // TC-DSC-003: API calls include correct org_id parameter
  // ---------------------------------------------------------------------------
  test.describe('TC-DSC-003: API Calls Include Correct org_id', () => {
    test('API calls to /api/domains include correct org_id and re-fetch on org change', async ({
      page,
    }) => {
      // Get user organizations
      const orgs = await getUserOrganizations(page);
      test.skip(orgs.length < 2, 'Test requires user with at least 2 organizations');

      // Find named orgs
      const defaultWorkspace = findOrgByName(orgs, 'Default Workspace');
      const secondOrg = findOrgByName(orgs, 'Second Organization');

      if (!defaultWorkspace || !secondOrg) {
        test.skip(
          true,
          'Test requires "Default Workspace" with domains and "A Second Organization" without domains'
        );
        return;
      }

      // Track API calls to /api/domains
      const apiCalls: ApiCallInfo[] = [];

      page.on('request', (request) => {
        const url = request.url();
        if (url.includes('/api/domains') || url.includes('/api/v2/domains')) {
          apiCalls.push({
            url,
            method: request.method(),
            orgId: extractOrgIdFromRequest(request),
            timestamp: Date.now(),
          });
        }
      });

      // Step 1: Navigate to Default Workspace dashboard
      apiCalls.length = 0; // Clear previous calls

      // Set up response listener before navigation
      const dashboardDomainsPromise = page.waitForResponse(
        (resp) => resp.url().includes('/api/') && resp.url().includes('domains'),
        { timeout: 10000 }
      ).catch(() => null);

      await page.goto('/dashboard');
      await page.waitForLoadState('networkidle');
      await dashboardDomainsPromise;

      // Log calls made for Default Workspace for debugging
      console.log(`API calls for Default Workspace: ${apiCalls.length}`);

      // Step 2: Navigate to A Second Organization
      apiCalls.length = 0; // Clear to track new calls

      // Set up response listener before navigation to second org
      const secondOrgDomainsPromise = page.waitForResponse(
        (resp) => resp.url().includes('/api/') && resp.url().includes('domains'),
        { timeout: 10000 }
      ).catch(() => null);

      await page.goto(`/org/${secondOrg.extid}`);
      await page.waitForLoadState('networkidle');
      await secondOrgDomainsPromise;

      // Verify a NEW API call was made (not returning cached data)
      const callsForSecond = [...apiCalls];

      // The fix ensures that when org changes, a new API call is made
      // Before the fix: no new call would be made because _initialized was true
      // After the fix: new call is made because _currentOrgId changed

      // Check that either:
      // 1. A new /api/domains call was made with org_id for second org, OR
      // 2. A domains endpoint was called (even without explicit org_id, the backend
      //    should use session context from the org page)

      const domainCallsForSecond = callsForSecond.filter(
        (call) => call.url.includes('/api/domains') && call.method === 'GET'
      );

      // Verify at least one domain API call was made for the second org
      // This is the key assertion: the store should NOT return cached data from first org
      expect(
        domainCallsForSecond.length,
        'A new API call to /api/domains should be made when navigating to a different org'
      ).toBeGreaterThanOrEqual(1);

      // If org_id is in the URL/params, verify it's the correct one
      const callsWithOrgId = domainCallsForSecond.filter((call) => call.orgId !== null);
      if (callsWithOrgId.length > 0) {
        for (const call of callsWithOrgId) {
          expect(
            call.orgId,
            `API call org_id should match A Second Organization's extid`
          ).toBe(secondOrg.extid);
        }
      }
    });
  });
});

// -----------------------------------------------------------------------------
// Additional Edge Case Tests
// -----------------------------------------------------------------------------

test.describe('DomainsStore Cache - Edge Cases', () => {
  test.skip(!hasTestCredentials, 'Skipping: TEST_USER_EMAIL and TEST_USER_PASSWORD required');

  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
    await loginUser(page);
  });

  test('TC-DSC-004: Browser back/forward maintains correct org domain context', async ({
    page,
  }) => {
    const orgs = await getUserOrganizations(page);
    test.skip(orgs.length < 2, 'Test requires user with at least 2 organizations');

    const defaultWorkspace = findOrgByName(orgs, 'Default Workspace');
    const secondOrg = findOrgByName(orgs, 'Second Organization');

    if (!defaultWorkspace || !secondOrg) {
      test.skip(true, 'Test requires specific organizations');
      return;
    }

    // Navigate to Default Workspace domains
    await page.goto(`/org/${defaultWorkspace.extid}/domains`);
    await page.waitForLoadState('networkidle');

    const hasDomainsInitially = await hasDomainsInTable(page);

    // Navigate to Second Org domains
    await page.goto(`/org/${secondOrg.extid}/domains`);
    await page.waitForLoadState('networkidle');

    const isEmptyAfterNav = await isEmptyDomainsState(page);
    expect(isEmptyAfterNav, 'Second org should show empty state').toBe(true);

    // Go back using browser back button
    await page.goBack();
    await page.waitForLoadState('networkidle');

    // Verify we're back on Default Workspace and domains are shown
    expect(page.url()).toContain(defaultWorkspace.extid);

    const hasDomainsAfterBack = await hasDomainsInTable(page);
    expect(
      hasDomainsAfterBack,
      'Default Workspace should still show domains after browser back'
    ).toBe(hasDomainsInitially);

    // Go forward
    await page.goForward();
    await page.waitForLoadState('networkidle');

    // Verify we're on Second Org and empty state is shown (not cached Default Workspace domains)
    expect(page.url()).toContain(secondOrg.extid);

    const isEmptyAfterForward = await isEmptyDomainsState(page);
    expect(
      isEmptyAfterForward,
      'Second org should still show empty state after browser forward (not cached data)'
    ).toBe(true);
  });

  test('TC-DSC-005: Page refresh maintains correct org domain context', async ({ page }) => {
    const orgs = await getUserOrganizations(page);
    test.skip(orgs.length < 2, 'Test requires user with at least 2 organizations');

    const secondOrg = findOrgByName(orgs, 'Second Organization');
    if (!secondOrg) {
      test.skip(true, 'Test requires "A Second Organization"');
      return;
    }

    // Navigate to Second Org domains (should be empty)
    await page.goto(`/org/${secondOrg.extid}/domains`);
    await page.waitForLoadState('networkidle');

    const isEmptyBefore = await isEmptyDomainsState(page);
    expect(isEmptyBefore, 'Second org should show empty state initially').toBe(true);

    // Refresh the page
    await page.reload();
    await page.waitForLoadState('networkidle');

    // Verify empty state is still shown (no stale cache from another org)
    const isEmptyAfterRefresh = await isEmptyDomainsState(page);
    expect(
      isEmptyAfterRefresh,
      'Second org should still show empty state after page refresh'
    ).toBe(true);
  });
});

/**
 * Qase Test Case Export Format
 *
 * Suite: DomainsStore Org Context Cache
 *
 * | ID         | Title                                                      | Priority | Automation |
 * |------------|------------------------------------------------------------|----------|------------|
 * | TC-DSC-001 | Domain switcher updates when navigating between orgs      | Critical | Automated  |
 * | TC-DSC-002 | Manage Domains page shows correct domains per org         | Critical | Automated  |
 * | TC-DSC-003 | API calls include correct org_id parameter                | Critical | Automated  |
 * | TC-DSC-004 | Browser back/forward maintains correct domain context     | High     | Automated  |
 * | TC-DSC-005 | Page refresh maintains correct org domain context         | Medium   | Automated  |
 */

/**
 * Bug Context:
 *
 * The domainsStore originally used a single `_initialized` boolean to track whether
 * domains had been loaded. This caused a bug where:
 *
 * 1. User visits Org A dashboard - domains loaded, _initialized = true
 * 2. User navigates to Org B page via URL
 * 3. refreshRecords() called but returns early because _initialized is true
 * 4. UI shows Org A's cached domains for Org B (cross-org data leakage)
 *
 * Fix in src/shared/stores/domainsStore.ts:
 * - Added `_currentOrgId` ref to track which org the cached data belongs to
 * - refreshRecords() now compares requested orgId with _currentOrgId
 * - If different, forces re-fetch regardless of _initialized state
 * - Reset also clears _currentOrgId
 *
 * Security implications:
 * - Without the fix, users could see domains belonging to other organizations
 * - This was a data isolation bug, not an authorization bug (user had access to both orgs)
 * - Still important for UX and preventing confusion/mistakes
 */
