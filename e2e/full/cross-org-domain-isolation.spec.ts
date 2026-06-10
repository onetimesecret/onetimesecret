// e2e/full/cross-org-domain-isolation.spec.ts

/**
 * E2E Tests for Cross-Organization Domain Isolation
 *
 * Validates that domain lists are correctly scoped to their respective organizations.
 * This test suite addresses the bug where viewing one organization's domains page
 * incorrectly shows domains from the user's active/default organization instead
 * of the organization being viewed.
 *
 * Bug Description:
 * - User has multiple organizations (OrgA with domain-a.com, OrgB with domain-b.com)
 * - When navigating to OrgB's domains page, they see OrgA's domains instead
 * - The issue occurs because the domain list doesn't respect the org context from URL
 *
 * Prerequisites:
 * - Authenticated via the project storageState (e2e/global.setup.ts consumes TEST_USER_*)
 * - User must have access to at least 2 organizations
 * - At least one org should have custom domains, another can be empty
 * - Application running locally or PLAYWRIGHT_BASE_URL set
 *
 * Usage:
 *   # Against dev server
 *   TEST_USER_EMAIL=test@example.com TEST_USER_PASSWORD=secret \
 *     pnpm playwright test cross-org-domain-isolation.spec.ts
 *
 *   # Against external URL
 *   PLAYWRIGHT_BASE_URL=https://dev.onetime.dev TEST_USER_EMAIL=... \
 *     pnpm test:playwright cross-org-domain-isolation.spec.ts
 */

import { expect, Page, test } from '@playwright/test';

// -----------------------------------------------------------------------------
// Types
// -----------------------------------------------------------------------------

interface OrgInfo {
  extid: string;
  name: string;
  domainCount: number;
  domains: string[];
}

// -----------------------------------------------------------------------------
// Test Helpers
// -----------------------------------------------------------------------------

/**
 * Get list of organizations the user has access to
 * Returns array of org info with extid, name, and domain count
 */
async function getUserOrganizations(page: Page): Promise<OrgInfo[]> {
  // Navigate to orgs list
  await page.goto('/orgs');
  await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

  // Find all organization cards/links
  const orgLinks = page.locator('a[href*="/org/"]');
  const count = await orgLinks.count();

  const orgs: OrgInfo[] = [];

  for (let i = 0; i < count; i++) {
    const link = orgLinks.nth(i);
    const href = await link.getAttribute('href');
    const match = href?.match(/\/org\/([^/]+)/);

    if (match) {
      const extid = match[1];
      // Get org name from the link text or nearby element
      const nameElement = link.locator('span.truncate, .font-medium, h3, h4').first();
      const name = (await nameElement.textContent())?.trim() || extid;

      orgs.push({
        extid,
        name,
        domainCount: 0,
        domains: [],
      });
    }
  }

  return orgs;
}

/**
 * Get domains for a specific organization by navigating to its organization page
 * (domains tab is the default view)
 */
async function getOrgDomains(page: Page, orgExtid: string): Promise<string[]> {
  await page.goto(`/org/${orgExtid}`);
  await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

  // Wait for either domains table or empty state
  const domainsTable = page.locator('table');
  const emptyState = page.getByText(/no domains found|get started by adding/i);

  await Promise.race([
    domainsTable.waitFor({ state: 'visible', timeout: 10000 }).catch(() => {}),
    emptyState.waitFor({ state: 'visible', timeout: 10000 }).catch(() => {}),
  ]);

  // If empty state is visible, return empty array
  if (await emptyState.isVisible()) {
    return [];
  }

  // Otherwise, extract domain names from the table
  // Domain names are displayed in links within the table
  const domainLinks = page.locator('table a[class*="brandcomp"]');
  const domains: string[] = [];

  const linkCount = await domainLinks.count();
  for (let i = 0; i < linkCount; i++) {
    const text = await domainLinks.nth(i).textContent();
    if (text) {
      domains.push(text.trim());
    }
  }

  return domains;
}

/**
 * Get current page URL's org extid
 */
function getOrgExtidFromUrl(url: string): string | null {
  const match = url.match(/\/org\/([^/]+)/);
  return match ? match[1] : null;
}

/**
 * Verify the domain list on page matches expected domains
 */
async function verifyDisplayedDomains(
  page: Page,
  expectedDomains: string[],
  unexpectedDomains: string[] = []
): Promise<void> {
  // No settle wait needed: the visibility assertions below are web-first
  // and retry until the domain list has rendered.

  // Check for expected domains
  for (const domain of expectedDomains) {
    const domainElement = page.locator(`text=${domain}`).first();
    await expect(
      domainElement,
      `Expected domain "${domain}" to be visible on page`
    ).toBeVisible({ timeout: 5000 });
  }

  // Check that unexpected domains are NOT visible
  for (const domain of unexpectedDomains) {
    const domainElement = page.locator(`text=${domain}`).first();
    await expect(
      domainElement,
      `Domain "${domain}" should NOT be visible on this org's page`
    ).not.toBeVisible({ timeout: 2000 });
  }
}

/**
 * Verify empty domains state is shown
 */
async function verifyEmptyDomainsState(page: Page): Promise<void> {
  const emptyState = page.getByText(/no domains found/i);
  await expect(emptyState, 'Empty state message should be visible').toBeVisible({ timeout: 5000 });
}

// -----------------------------------------------------------------------------
// Test Suite: Cross-Organization Domain Isolation
// -----------------------------------------------------------------------------

// QUARANTINED — E2E remediation plan Phase 2.4 / PR 5 (issue #3420).
// Every test here needs ≥2 organizations (most with disjoint custom-domain
// sets) — seeded data relationships the CI account (one default workspace, no
// domains) does not have. These were among the hard failures aborting the
// #3412/#3416 runs: the file's getUserOrganizations() DOM scraper times out,
// tripping --max-failures and hiding the rest of the suite. Quarantined with
// test.describe.fixme (not test.skip, which hides them) until the second-org +
// per-org-domain fixtures land in PR 6. See e2e/QUARANTINE.md.
test.describe.fixme('Cross-Organization Domain Isolation', () => {
  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
  });

  // -------------------------------------------------------------------------
  // TC-DOI-001: Basic Isolation - Each org shows only its own domains
  // -------------------------------------------------------------------------
  test.describe('Basic Domain Isolation', () => {
    test('TC-DOI-001: Organization domains page shows only domains belonging to that organization', async ({
      page,
    }) => {
      // Get list of user's organizations
      const orgs = await getUserOrganizations(page);

      test.skip(orgs.length < 2, 'Test requires user with at least 2 organizations');

      // Gather domain info for each org
      for (const org of orgs) {
        org.domains = await getOrgDomains(page, org.extid);
        org.domainCount = org.domains.length;
      }

      // Find orgs with domains to test isolation
      const orgsWithDomains = orgs.filter((o) => o.domainCount > 0);

      expect(
        orgsWithDomains.length,
        'requires ≥1 org with domains — second-org + per-org-domain fixture (#3420)'
      ).toBeGreaterThanOrEqual(1);

      // Test each org's page (domains tab is default)
      for (const currentOrg of orgs) {
        await page.goto(`/org/${currentOrg.extid}`);
        await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

        // Verify URL contains correct org
        const currentUrl = page.url();
        expect(getOrgExtidFromUrl(currentUrl)).toBe(currentOrg.extid);

        // Collect domains from OTHER orgs (should NOT be visible)
        const otherOrgsDomains = orgs
          .filter((o) => o.extid !== currentOrg.extid)
          .flatMap((o) => o.domains);

        if (currentOrg.domains.length > 0) {
          // Verify current org's domains are shown
          await verifyDisplayedDomains(page, currentOrg.domains, otherOrgsDomains);
        } else {
          // Verify empty state is shown (not other org's domains)
          await verifyEmptyDomainsState(page);

          // Also verify other orgs' domains are NOT shown
          for (const domain of otherOrgsDomains) {
            const domainElement = page.locator(`text=${domain}`).first();
            await expect(
              domainElement,
              `Domain "${domain}" from another org should NOT appear in empty org's page`
            ).not.toBeVisible();
          }
        }
      }
    });
  });

  // -------------------------------------------------------------------------
  // TC-DOI-002: Empty org shows empty list, not active org's domains
  // -------------------------------------------------------------------------
  test.describe('Empty Organization Domain List', () => {
    test('TC-DOI-002: Organization without domains shows empty state, not active org domains', async ({
      page,
    }) => {
      const orgs = await getUserOrganizations(page);
      test.skip(orgs.length < 2, 'Test requires user with at least 2 organizations');

      // Gather domain info
      for (const org of orgs) {
        org.domains = await getOrgDomains(page, org.extid);
        org.domainCount = org.domains.length;
      }

      // Find an org with domains and one without
      const orgWithDomains = orgs.find((o) => o.domainCount > 0);
      const orgWithoutDomains = orgs.find((o) => o.domainCount === 0);

      if (!orgWithDomains || !orgWithoutDomains) {
        test.skip(
          true,
          'Test requires one org with domains and one without. Create test data accordingly.'
        );
        return;
      }

      // First visit org WITH domains to establish it as "active" context
      await page.goto(`/org/${orgWithDomains.extid}`);
      await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

      // Verify we see domains
      await expect(page.locator('table')).toBeVisible();
      await verifyDisplayedDomains(page, orgWithDomains.domains);

      // Now navigate to org WITHOUT domains (domains tab is default)
      await page.goto(`/org/${orgWithoutDomains.extid}`);
      await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

      // Should see empty state, NOT the previous org's domains
      await verifyEmptyDomainsState(page);

      // Verify the domains from orgWithDomains are NOT visible
      for (const domain of orgWithDomains.domains) {
        const domainElement = page.locator(`text=${domain}`).first();
        await expect(
          domainElement,
          `Domain "${domain}" from active org should NOT leak to empty org's page`
        ).not.toBeVisible();
      }
    });
  });

  // -------------------------------------------------------------------------
  // TC-DOI-003: Direct URL navigation respects org context
  // -------------------------------------------------------------------------
  test.describe('Direct URL Navigation', () => {
    test('TC-DOI-003: Directly navigating to org domains URL shows that org\'s domains', async ({
      page,
    }) => {
      const orgs = await getUserOrganizations(page);
      test.skip(orgs.length < 2, 'Test requires user with at least 2 organizations');

      // Gather domain info
      for (const org of orgs) {
        org.domains = await getOrgDomains(page, org.extid);
        org.domainCount = org.domains.length;
      }

      // Find two orgs with different domain sets
      const orgA = orgs[0];
      const orgB = orgs[1];

      // Navigate to dashboard first (sets some "active" context)
      await page.goto('/dashboard');
      await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

      // Directly navigate to orgB's page (domains tab is default)
      await page.goto(`/org/${orgB.extid}`);
      await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

      // Verify URL is correct
      expect(page.url()).toContain(`/org/${orgB.extid}`);

      // Verify correct domains are shown
      if (orgB.domains.length > 0) {
        await verifyDisplayedDomains(page, orgB.domains, orgA.domains);
      } else {
        await verifyEmptyDomainsState(page);
        // Verify orgA's domains don't leak
        for (const domain of orgA.domains) {
          await expect(page.locator(`text=${domain}`).first()).not.toBeVisible();
        }
      }

      // Now directly navigate to orgA's page (domains tab is default)
      await page.goto(`/org/${orgA.extid}`);
      await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

      // Verify URL is correct
      expect(page.url()).toContain(`/org/${orgA.extid}`);

      // Verify correct domains are shown
      if (orgA.domains.length > 0) {
        await verifyDisplayedDomains(page, orgA.domains, orgB.domains);
      } else {
        await verifyEmptyDomainsState(page);
      }
    });
  });

  // -------------------------------------------------------------------------
  // TC-DOI-004: Sequential navigation updates domain list correctly
  // -------------------------------------------------------------------------
  test.describe('Sequential Navigation', () => {
    test('TC-DOI-004: Navigating between org domains pages correctly updates domain list', async ({
      page,
    }) => {
      const orgs = await getUserOrganizations(page);
      test.skip(orgs.length < 2, 'Test requires user with at least 2 organizations');

      // Gather domain info
      for (const org of orgs) {
        org.domains = await getOrgDomains(page, org.extid);
        org.domainCount = org.domains.length;
      }

      const orgA = orgs[0];
      const orgB = orgs[1];

      // Step 1: Navigate to OrgA (domains tab is default)
      await page.goto(`/org/${orgA.extid}`);
      await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

      if (orgA.domains.length > 0) {
        await verifyDisplayedDomains(page, orgA.domains);
      } else {
        await verifyEmptyDomainsState(page);
      }

      // Step 2: Navigate to OrgB via URL (domains tab is default)
      await page.goto(`/org/${orgB.extid}`);
      await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

      // Verify domain list updated to OrgB
      if (orgB.domains.length > 0) {
        await verifyDisplayedDomains(page, orgB.domains, orgA.domains);
      } else {
        await verifyEmptyDomainsState(page);
        // Verify orgA domains don't persist
        for (const domain of orgA.domains) {
          await expect(
            page.locator(`text=${domain}`).first(),
            `OrgA domain "${domain}" should not persist after navigating to OrgB`
          ).not.toBeVisible();
        }
      }

      // Step 3: Navigate back to OrgA (domains tab is default)
      await page.goto(`/org/${orgA.extid}`);
      await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

      // Verify domain list shows OrgA domains again
      if (orgA.domains.length > 0) {
        await verifyDisplayedDomains(page, orgA.domains, orgB.domains);
      } else {
        await verifyEmptyDomainsState(page);
      }
    });

    test('TC-DOI-005: Using org switcher updates domain list correctly', async ({ page }) => {
      const orgs = await getUserOrganizations(page);
      test.skip(orgs.length < 2, 'Test requires user with at least 2 organizations');

      // Gather domain info
      for (const org of orgs) {
        org.domains = await getOrgDomains(page, org.extid);
        org.domainCount = org.domains.length;
      }

      const orgA = orgs[0];
      const orgB = orgs[1];

      // Start on OrgA page (domains tab is default)
      await page.goto(`/org/${orgA.extid}`);
      await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

      // Try to use org switcher if visible
      const orgSwitcherTrigger = page.locator(
        '[data-testid="org-scope-switcher-trigger"], button[aria-label*="organization" i]'
      );

      const switcherVisible = await orgSwitcherTrigger.isVisible().catch(() => false);

      if (switcherVisible) {
        await orgSwitcherTrigger.click();

        // Find and click on OrgB in dropdown
        const dropdown = page.locator('[role="menu"]');
        await expect(dropdown).toBeVisible();

        // Look for OrgB in the menu items
        const orgBItem = dropdown.locator('[role="menuitem"]').filter({ hasText: orgB.name });
        const hasOrgBItem = await orgBItem.isVisible().catch(() => false);

        if (hasOrgBItem) {
          await orgBItem.click();

          // Verify URL changed to OrgB (web-first assertion waits for the
          // switcher navigation and reactive updates to settle)
          await expect(page).toHaveURL(new RegExp(`/org/${orgB.extid}`));

          // Verify domain list updated
          if (orgB.domains.length > 0) {
            await verifyDisplayedDomains(page, orgB.domains, orgA.domains);
          } else {
            await verifyEmptyDomainsState(page);
          }
        } else {
          throw new Error('OrgB not found in org switcher — needs second-org fixture (#3420)');
        }
      } else {
        throw new Error('Org switcher not visible on domains page — needs second-org fixture (#3420)');
      }
    });
  });

  // -------------------------------------------------------------------------
  // TC-DOI-006: Browser back/forward maintains correct domain context
  // -------------------------------------------------------------------------
  test.describe('Browser Navigation History', () => {
    test('TC-DOI-006: Browser back/forward buttons maintain correct domain isolation', async ({
      page,
    }) => {
      const orgs = await getUserOrganizations(page);
      test.skip(orgs.length < 2, 'Test requires user with at least 2 organizations');

      // Gather domain info
      for (const org of orgs) {
        org.domains = await getOrgDomains(page, org.extid);
        org.domainCount = org.domains.length;
      }

      const orgA = orgs[0];
      const orgB = orgs[1];

      // Navigate to OrgA (domains tab is default)
      await page.goto(`/org/${orgA.extid}`);
      await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

      // Verify OrgA domains
      const initialOrgADomains = orgA.domains.slice();

      // Navigate to OrgB (domains tab is default)
      await page.goto(`/org/${orgB.extid}`);
      await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

      // Go back using browser back button; the web-first URL assertion
      // waits for the history navigation to settle
      await page.goBack();
      await expect(page).toHaveURL(new RegExp(`/org/${orgA.extid}`));

      if (initialOrgADomains.length > 0) {
        await verifyDisplayedDomains(page, initialOrgADomains, orgB.domains);
      } else {
        await verifyEmptyDomainsState(page);
      }

      // Go forward; the web-first URL assertion waits for the history
      // navigation to settle
      await page.goForward();
      await expect(page).toHaveURL(new RegExp(`/org/${orgB.extid}`));

      if (orgB.domains.length > 0) {
        await verifyDisplayedDomains(page, orgB.domains, orgA.domains);
      } else {
        await verifyEmptyDomainsState(page);
      }
    });
  });

  // -------------------------------------------------------------------------
  // TC-DOI-007: Page refresh maintains correct domain context
  // -------------------------------------------------------------------------
  test.describe('Page Refresh', () => {
    test('TC-DOI-007: Refreshing page maintains correct org domain context', async ({ page }) => {
      const orgs = await getUserOrganizations(page);
      test.skip(orgs.length < 1, 'Test requires at least 1 organization');

      const org = orgs[0];
      org.domains = await getOrgDomains(page, org.extid);

      // Navigate to org page (domains tab is default)
      await page.goto(`/org/${org.extid}`);
      await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

      // Record current state
      const urlBeforeRefresh = page.url();

      // Refresh the page
      await page.reload();
      await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

      // Verify URL is still correct
      expect(page.url()).toBe(urlBeforeRefresh);

      // Verify domains are still correctly displayed
      if (org.domains.length > 0) {
        await verifyDisplayedDomains(page, org.domains);
      } else {
        await verifyEmptyDomainsState(page);
      }
    });
  });
});

// -----------------------------------------------------------------------------
// Test Suite: API-Level Domain Isolation (Network Interception)
// -----------------------------------------------------------------------------

// QUARANTINED with the suite above — needs ≥2 orgs (issue #3420).
test.describe.fixme('API-Level Domain Isolation', () => {
  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
  });

  test('TC-DOI-008: API requests include correct org context parameter', async ({ page }) => {
    const orgs = await getUserOrganizations(page);
    test.skip(orgs.length < 2, 'Test requires user with at least 2 organizations');

    const orgA = orgs[0];
    const orgB = orgs[1];

    // Track API calls
    const apiCalls: { url: string; orgInUrl: string | null }[] = [];

    page.on('request', (request) => {
      const url = request.url();
      if (url.includes('/api/') && url.includes('domain')) {
        const orgMatch = url.match(/org[=/]([^/&?]+)/);
        apiCalls.push({
          url,
          orgInUrl: orgMatch ? orgMatch[1] : null,
        });
      }
    });

    // Navigate to OrgA (domains tab is default)
    await page.goto(`/org/${orgA.extid}`);
    await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();
    // Wait for the domains tab UI (table or empty state) - its appearance
    // implies the org-scoped domains API call has completed.
    await expect(
      page.locator('table').or(page.getByText(/no domains found|get started by adding/i)).first()
    ).toBeVisible();

    // Check API calls included OrgA context
    const orgACalls = apiCalls.filter((call) => call.orgInUrl === orgA.extid);

    // Clear tracking for next org
    apiCalls.length = 0;

    // Navigate to OrgB (domains tab is default)
    await page.goto(`/org/${orgB.extid}`);
    await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();
    // Wait for the domains tab UI (table or empty state) - its appearance
    // implies the org-scoped domains API call has completed.
    await expect(
      page.locator('table').or(page.getByText(/no domains found|get started by adding/i)).first()
    ).toBeVisible();

    // Check API calls included OrgB context
    const orgBCalls = apiCalls.filter((call) => call.orgInUrl === orgB.extid);

    // Verify API calls used correct org context
    // Note: This test verifies the pattern, actual API structure may vary
    if (orgACalls.length > 0 || orgBCalls.length > 0) {
      // If there were org-specific API calls, they should match the page context
      expect(
        orgACalls.every((call) => call.orgInUrl === orgA.extid) &&
          orgBCalls.every((call) => call.orgInUrl === orgB.extid)
      ).toBe(true);
    }
  });
});

/**
 * Qase Test Case Export Format
 *
 * Suite: Cross-Organization Domain Isolation
 *
 * | ID         | Title                                                    | Priority | Automation |
 * |------------|----------------------------------------------------------|----------|------------|
 * | TC-DOI-001 | Org domains page shows only domains for that org        | Critical | Automated  |
 * | TC-DOI-002 | Empty org shows empty state, not active org domains     | Critical | Automated  |
 * | TC-DOI-003 | Direct URL navigation respects org domain context       | Critical | Automated  |
 * | TC-DOI-004 | Sequential navigation updates domain list correctly     | High     | Automated  |
 * | TC-DOI-005 | Org switcher updates domain list correctly              | High     | Automated  |
 * | TC-DOI-006 | Browser back/forward maintains domain isolation         | Medium   | Automated  |
 * | TC-DOI-007 | Page refresh maintains correct org domain context       | Medium   | Automated  |
 * | TC-DOI-008 | API requests include correct org context parameter      | High     | Automated  |
 */

/**
 * Manual Test Checklist - Cross-Org Domain Isolation
 *
 * ## Prerequisites
 * - [ ] Test user has access to at least 2 organizations
 * - [ ] At least one org has verified custom domains
 * - [ ] At least one org has no custom domains (for empty state tests)
 *
 * ## Visual Verification (Not Automated)
 * - [ ] Domain table styling consistent across orgs
 * - [ ] Empty state message is clear and not confusing
 * - [ ] Loading states don't flash wrong org's data
 * - [ ] No "flicker" of wrong domains during navigation
 *
 * ## Edge Cases
 * - [ ] User with only 1 org sees their domains correctly
 * - [ ] User switching active org via global switcher
 * - [ ] Deep linking from email/bookmark works correctly
 * - [ ] Multiple browser tabs with different orgs work independently
 *
 * ## Performance
 * - [ ] Navigation between orgs doesn't cause excessive API calls
 * - [ ] Large domain lists render correctly per org
 */
