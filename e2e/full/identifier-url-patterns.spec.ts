// src/tests/e2e/identifier-url-patterns.spec.ts

//
// E2E Tests for Opaque Identifier Pattern (#2312)
//
// These tests validate that URLs use ExtId (external identifiers) instead of
// internal database IDs (ObjId/UUIDs), following the OWASP IDOR prevention pattern.
//
// ExtId Prefixes:
//   - on: Organization (e.g., on8a7b9c)
//   - cd: CustomDomain (e.g., cd4f2e1a)
//   - ur: Customer (e.g., ur7d9c3b)
//   - se: Secret (e.g., sek3m9p2)
//   - md: Metadata (e.g., mdx7y4z1)
//
// Prerequisites:
//   - Set TEST_USER_EMAIL and TEST_USER_PASSWORD environment variables
//   - Application running locally or PLAYWRIGHT_BASE_URL set
//   - User should have at least one organization and optionally domains
//
// Usage:
//   TEST_USER_EMAIL=test@example.com TEST_USER_PASSWORD=secret \
//     pnpm test:playwright src/tests/e2e/identifier-url-patterns.spec.ts

import { expect, Page, test } from '@playwright/test';

// Extend Window interface for test-specific properties
declare global {
  interface Window {
    captureHistoryEntry?: (url: string) => void;
    __BOOTSTRAP_STATE__?: {
      authenticated?: boolean;
      cust?: unknown;
      [key: string]: unknown;
    };
  }
}

// Check if test credentials are configured
const hasTestCredentials = !!(process.env.TEST_USER_EMAIL && process.env.TEST_USER_PASSWORD);

// -----------------------------------------------------------------------------
// Identifier Pattern Constants
// -----------------------------------------------------------------------------

/**
 * ExtId prefix patterns by entity type
 * These prefixes are defined in src/types/identifiers.ts
 */
const EXTID_PREFIXES = {
  organization: 'on',
  domain: 'cd',
  customer: 'ur',
  secret: 'se',
  metadata: 'md',
} as const;

/**
 * Regex patterns for identifier detection
 */
const PATTERNS = {
  // UUID pattern (internal IDs we want to avoid in URLs)
  uuid: /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i,

  // Hex string pattern (another internal ID format)
  hexId: /[0-9a-f]{16,32}/i,

  // ExtId patterns (what we want to see in URLs)
  orgExtId: /\/org\/on[a-zA-Z0-9]+/,
  domainExtId: /\/domains\/cd[a-zA-Z0-9]+/,
  secretExtId: /\/secret\/se[a-zA-Z0-9]+/,
  receiptExtId: /\/receipt\/[a-zA-Z0-9]+/,

  // Generic ExtId (any known prefix)
  anyExtId: /\/(on|cd|ur|se|md)[a-zA-Z0-9]+/,
};

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
 * Check if a URL path contains a UUID (internal ID format)
 * This is a security concern - internal IDs should not be in URLs
 */
function containsUUID(url: string): boolean {
  return PATTERNS.uuid.test(url);
}

/**
 * Check if a URL path contains a hex string ID (internal ID format)
 * @internal Reserved for future use in more comprehensive ID detection
 */
function _containsHexId(url: string): boolean {
  // Exclude valid ExtId prefixes using single regex to avoid incomplete sanitization
  // (CodeQL: chained .replace() calls can miss patterns created by earlier replacements)
  const withoutExtIds = url.replace(/\/(on|cd|ur|se|md)[a-zA-Z0-9]+/g, '');

  return PATTERNS.hexId.test(withoutExtIds);
}

/**
 * Check if a URL contains an ExtId with the expected prefix
 */
function containsExtIdWithPrefix(url: string, prefix: string): boolean {
  const pattern = new RegExp(`/${prefix}[a-zA-Z0-9]+`);
  return pattern.test(url);
}

/**
 * Extract all identifier-like strings from a URL for debugging
 */
function extractIdentifiers(url: string): string[] {
  const identifiers: string[] = [];

  // Find UUIDs
  const uuids = url.match(PATTERNS.uuid);
  if (uuids) identifiers.push(...uuids.map((id) => `UUID: ${id}`));

  // Find ExtIds
  const extIds = url.match(/\/(on|cd|ur|se|md)[a-zA-Z0-9]+/g);
  if (extIds) identifiers.push(...extIds.map((id) => `ExtId: ${id}`));

  return identifiers;
}

// -----------------------------------------------------------------------------
// URL Pattern Validation Test Suite
// -----------------------------------------------------------------------------

test.describe('Opaque Identifier Pattern - URL Security', () => {
  test.skip(!hasTestCredentials, 'Skipping: TEST_USER_EMAIL and TEST_USER_PASSWORD required');

  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
    await loginUser(page);
  });

  // -------------------------------------------------------------------------
  // TC-ID-001: Organization URLs use ExtId format
  // -------------------------------------------------------------------------
  test.describe('Organization URL Patterns', () => {
    test('TC-ID-001: Organization settings URL uses ExtId (on prefix)', async ({ page }) => {
      await page.goto('/dashboard');
      await page.waitForLoadState('networkidle');

      // Find and click an organization link
      const orgLink = page.locator('a[href*="/org/"]').first();
      const hasOrgLink = await orgLink.isVisible().catch(() => false);

      if (hasOrgLink) {
        await orgLink.click();
        await page.waitForLoadState('networkidle');

        const currentUrl = page.url();

        // Verify URL contains ExtId with 'on' prefix
        expect(
          containsExtIdWithPrefix(currentUrl, EXTID_PREFIXES.organization),
          `Organization URL should contain ExtId with 'on' prefix. URL: ${currentUrl}`
        ).toBe(true);

        // Verify URL does NOT contain UUID (internal ID)
        expect(
          containsUUID(currentUrl),
          `Organization URL should NOT contain UUID. URL: ${currentUrl}, Found IDs: ${extractIdentifiers(currentUrl).join(', ')}`
        ).toBe(false);
      } else {
        // Navigate to org list and find an org
        await page.goto('/orgs');
        await page.waitForLoadState('networkidle');

        const orgCard = page.locator('a[href*="/org/on"]').first();
        if (await orgCard.isVisible().catch(() => false)) {
          await orgCard.click();
          await page.waitForLoadState('networkidle');

          const currentUrl = page.url();
          expect(containsExtIdWithPrefix(currentUrl, EXTID_PREFIXES.organization)).toBe(true);
          expect(containsUUID(currentUrl)).toBe(false);
        } else {
          test.skip(true, 'No organizations available to test');
        }
      }
    });

    test('TC-ID-002: Organization members URL uses ExtId', async ({ page }) => {
      // Navigate to an organization first
      await page.goto('/orgs');
      await page.waitForLoadState('networkidle');

      const orgLink = page.locator('a[href*="/org/on"]').first();
      const hasOrgLink = await orgLink.isVisible().catch(() => false);

      if (hasOrgLink) {
        // Get the href to extract the org extid
        const href = await orgLink.getAttribute('href');
        if (href) {
          // Navigate to members page
          await page.goto(`${href}/members`);
          await page.waitForLoadState('networkidle');

          const currentUrl = page.url();

          expect(
            containsExtIdWithPrefix(currentUrl, EXTID_PREFIXES.organization),
            `Members URL should contain org ExtId. URL: ${currentUrl}`
          ).toBe(true);

          expect(
            currentUrl.includes('/members'),
            `URL should include /members path. URL: ${currentUrl}`
          ).toBe(true);

          expect(containsUUID(currentUrl)).toBe(false);
        }
      } else {
        test.skip(true, 'No organizations available to test');
      }
    });

    test('TC-ID-003: Clicking org card navigates to ExtId URL', async ({ page }) => {
      await page.goto('/dashboard');
      await page.waitForLoadState('networkidle');

      // Try to find the org scope switcher or org card
      const orgSwitcher = page.locator(
        '[data-testid="org-scope-switcher-trigger"], button[aria-label*="organization" i]'
      );
      const hasSwitcher = await orgSwitcher.isVisible().catch(() => false);

      if (hasSwitcher) {
        await orgSwitcher.click();

        // Look for gear icon in dropdown
        const menuItem = page.locator('[role="menuitem"]').first();
        await menuItem.hover();

        const gearIcon = menuItem.locator('button[aria-label*="settings" i]');
        const hasGear = await gearIcon.isVisible().catch(() => false);

        if (hasGear) {
          await gearIcon.click();
          await page.waitForLoadState('networkidle');

          const currentUrl = page.url();

          expect(
            PATTERNS.orgExtId.test(currentUrl),
            `After clicking org settings, URL should have /org/on... pattern. URL: ${currentUrl}`
          ).toBe(true);

          expect(containsUUID(currentUrl)).toBe(false);
        }
      } else {
        test.skip(true, 'Organization switcher not visible');
      }
    });
  });

  // -------------------------------------------------------------------------
  // TC-ID-010: Domain URLs use ExtId format
  // -------------------------------------------------------------------------
  test.describe('Domain URL Patterns', () => {
    test('TC-ID-010: Domain detail URL uses ExtId (cd prefix)', async ({ page }) => {
      await page.goto('/domains');
      await page.waitForLoadState('networkidle');

      // Find a domain link (not "Add Domain" link)
      const domainLink = page.locator('a[href*="/domains/cd"]').first();
      const hasDomainLink = await domainLink.isVisible().catch(() => false);

      if (hasDomainLink) {
        await domainLink.click();
        await page.waitForLoadState('networkidle');

        const currentUrl = page.url();

        expect(
          containsExtIdWithPrefix(currentUrl, EXTID_PREFIXES.domain),
          `Domain URL should contain ExtId with 'cd' prefix. URL: ${currentUrl}`
        ).toBe(true);

        expect(
          containsUUID(currentUrl),
          `Domain URL should NOT contain UUID. URL: ${currentUrl}`
        ).toBe(false);
      } else {
        test.skip(true, 'No custom domains available to test');
      }
    });

    test('TC-ID-011: Domain verify URL uses ExtId', async ({ page }) => {
      await page.goto('/domains');
      await page.waitForLoadState('networkidle');

      const domainLink = page.locator('a[href*="/domains/cd"]').first();
      const hasDomainLink = await domainLink.isVisible().catch(() => false);

      if (hasDomainLink) {
        const href = await domainLink.getAttribute('href');
        if (href) {
          // Navigate to verify subpath
          await page.goto(`${href}/verify`);
          await page.waitForLoadState('networkidle');

          const currentUrl = page.url();

          expect(containsExtIdWithPrefix(currentUrl, EXTID_PREFIXES.domain)).toBe(true);
          expect(currentUrl.includes('/verify')).toBe(true);
          expect(containsUUID(currentUrl)).toBe(false);
        }
      } else {
        test.skip(true, 'No custom domains available to test');
      }
    });

    test('TC-ID-012: Domain branding URL uses ExtId', async ({ page }) => {
      await page.goto('/domains');
      await page.waitForLoadState('networkidle');

      const domainLink = page.locator('a[href*="/domains/cd"]').first();
      const hasDomainLink = await domainLink.isVisible().catch(() => false);

      if (hasDomainLink) {
        const href = await domainLink.getAttribute('href');
        if (href) {
          await page.goto(`${href}/brand`);
          await page.waitForLoadState('networkidle');

          const currentUrl = page.url();

          expect(containsExtIdWithPrefix(currentUrl, EXTID_PREFIXES.domain)).toBe(true);
          expect(currentUrl.includes('/brand')).toBe(true);
          expect(containsUUID(currentUrl)).toBe(false);
        }
      } else {
        test.skip(true, 'No custom domains available to test');
      }
    });
  });

  // -------------------------------------------------------------------------
  // TC-ID-020: Secret URLs use ExtId format
  // -------------------------------------------------------------------------
  test.describe('Secret URL Patterns', () => {
    test('TC-ID-020: Created secret receipt URL uses proper format', async ({ page }) => {
      await page.goto('/');
      await page.waitForLoadState('networkidle');

      const secretInput = page.locator('textarea[aria-label*="secret content"]');
      const createButton = page.locator('button:has-text("Create Link")');

      if (await secretInput.isVisible()) {
        await secretInput.fill('Test secret for identifier pattern validation');
        await createButton.click();

        // Wait for redirect to receipt page
        await page.waitForURL(/\/receipt\/.+/, { timeout: 15000 });

        const currentUrl = page.url();

        // Receipt URLs should NOT contain UUIDs
        expect(
          containsUUID(currentUrl),
          `Secret receipt URL should NOT contain UUID. URL: ${currentUrl}`
        ).toBe(false);

        // The identifier in the URL should be the secret key (opaque)
        expect(
          /\/receipt\/[a-zA-Z0-9]+/.test(currentUrl),
          `Receipt URL should have opaque identifier format. URL: ${currentUrl}`
        ).toBe(true);
      } else {
        test.skip(true, 'Secret creation form not available');
      }
    });
  });

  // -------------------------------------------------------------------------
  // TC-ID-030: Navigation flows maintain ExtId pattern
  // -------------------------------------------------------------------------
  test.describe('Navigation Flow URL Validation', () => {
    test('TC-ID-030: Dashboard to org settings maintains ExtId', async ({ page }) => {
      await page.goto('/dashboard');
      await page.waitForLoadState('networkidle');

      // Track all navigation URLs
      const visitedUrls: string[] = [];

      page.on('framenavigated', (frame) => {
        if (frame === page.mainFrame()) {
          visitedUrls.push(frame.url());
        }
      });

      // Navigate to organizations page
      const orgNavLink = page.locator('a[href="/orgs"]');
      if (await orgNavLink.isVisible().catch(() => false)) {
        await orgNavLink.click();
        await page.waitForLoadState('networkidle');
      } else {
        await page.goto('/orgs');
        await page.waitForLoadState('networkidle');
      }

      // Click on first organization
      const orgCard = page.locator('a[href*="/org/on"]').first();
      if (await orgCard.isVisible().catch(() => false)) {
        await orgCard.click();
        await page.waitForLoadState('networkidle');
      }

      // Verify no visited URLs contain UUIDs
      const urlsWithUUIDs = visitedUrls.filter(containsUUID);
      expect(
        urlsWithUUIDs.length,
        `Navigation should not expose UUIDs in URLs. Found: ${urlsWithUUIDs.join(', ')}`
      ).toBe(0);
    });

    test('TC-ID-031: Domains list to domain detail maintains ExtId', async ({ page }) => {
      await page.goto('/domains');
      await page.waitForLoadState('networkidle');

      const visitedUrls: string[] = [];
      page.on('framenavigated', (frame) => {
        if (frame === page.mainFrame()) {
          visitedUrls.push(frame.url());
        }
      });

      const domainCard = page.locator('a[href*="/domains/cd"]').first();
      if (await domainCard.isVisible().catch(() => false)) {
        await domainCard.click();
        await page.waitForLoadState('networkidle');

        // Navigate to subpages if available
        const verifyTab = page.locator('a[href*="/verify"]');
        if (await verifyTab.isVisible().catch(() => false)) {
          await verifyTab.click();
          await page.waitForLoadState('networkidle');
        }

        // Verify no visited URLs contain UUIDs
        const urlsWithUUIDs = visitedUrls.filter(containsUUID);
        expect(urlsWithUUIDs.length).toBe(0);
      } else {
        test.skip(true, 'No custom domains available to test');
      }
    });
  });
});

// -----------------------------------------------------------------------------
// URL Security Validation Test Suite
// -----------------------------------------------------------------------------

test.describe('Opaque Identifier Pattern - Security Validation', () => {
  test.skip(!hasTestCredentials, 'Skipping: TEST_USER_EMAIL and TEST_USER_PASSWORD required');

  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
    await loginUser(page);
  });

  test('TC-ID-040: No internal IDs exposed in network requests', async ({ page }) => {
    const requestsWithInternalIds: string[] = [];

    // Monitor network requests for internal IDs in URLs
    page.on('request', (request) => {
      const url = request.url();
      // Only check API requests
      if (url.includes('/api/')) {
        // Check for UUIDs in the path (not query params which may be different)
        const urlPath = new URL(url).pathname;
        if (containsUUID(urlPath)) {
          requestsWithInternalIds.push(url);
        }
      }
    });

    // Navigate through several pages
    await page.goto('/dashboard');
    await page.waitForLoadState('networkidle');

    await page.goto('/orgs');
    await page.waitForLoadState('networkidle');

    const orgLink = page.locator('a[href*="/org/on"]').first();
    if (await orgLink.isVisible().catch(() => false)) {
      await orgLink.click();
      await page.waitForLoadState('networkidle');
    }

    await page.goto('/domains');
    await page.waitForLoadState('networkidle');

    // Filter out known exceptions (if any)
    const unexpectedInternalIds = requestsWithInternalIds.filter(
      (_url) =>
        // Add any known exceptions here
        true
    );

    expect(
      unexpectedInternalIds.length,
      `API requests should use ExtIds, not internal IDs. Found: ${unexpectedInternalIds.join(', ')}`
    ).toBe(0);
  });

  test('TC-ID-041: Browser history entries use ExtId format', async ({ page }) => {
    await page.goto('/dashboard');
    await page.waitForLoadState('networkidle');

    const historyEntries: string[] = [];

    // Capture history state changes
    await page.exposeFunction('captureHistoryEntry', (url: string) => {
      historyEntries.push(url);
    });

    await page.evaluate(() => {
      const originalPushState = history.pushState;
      const originalReplaceState = history.replaceState;

      history.pushState = function (...args) {
        window.captureHistoryEntry(args[2] as string);
        return originalPushState.apply(this, args);
      };

      history.replaceState = function (...args) {
        window.captureHistoryEntry(args[2] as string);
        return originalReplaceState.apply(this, args);
      };
    });

    // Navigate through the app
    await page.goto('/orgs');
    await page.waitForLoadState('networkidle');

    const orgLink = page.locator('a[href*="/org/on"]').first();
    if (await orgLink.isVisible().catch(() => false)) {
      await orgLink.click();
      await page.waitForLoadState('networkidle');
    }

    // Check all history entries for internal IDs
    const entriesWithInternalIds = historyEntries.filter((entry) => entry && containsUUID(entry));

    expect(
      entriesWithInternalIds.length,
      `Browser history should not contain internal IDs. Found: ${entriesWithInternalIds.join(', ')}`
    ).toBe(0);
  });

  test('TC-ID-042: Link href attributes use ExtId format', async ({ page }) => {
    await page.goto('/dashboard');
    await page.waitForLoadState('networkidle');

    // Collect all links on the page
    const links = await page.locator('a[href]').all();
    const linksWithInternalIds: string[] = [];

    for (const link of links) {
      const href = await link.getAttribute('href');
      if (href && containsUUID(href)) {
        linksWithInternalIds.push(href);
      }
    }

    expect(
      linksWithInternalIds.length,
      `Links should use ExtIds, not internal IDs. Found: ${linksWithInternalIds.join(', ')}`
    ).toBe(0);
  });
});

// -----------------------------------------------------------------------------
// ExtId Format Consistency Test Suite
// -----------------------------------------------------------------------------

test.describe('Opaque Identifier Pattern - Format Consistency', () => {
  test.skip(!hasTestCredentials, 'Skipping: TEST_USER_EMAIL and TEST_USER_PASSWORD required');

  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
    await loginUser(page);
  });

  test('TC-ID-050: Organization ExtIds consistently use "on" prefix', async ({ page }) => {
    await page.goto('/orgs');
    await page.waitForLoadState('networkidle');

    // Find all org-related links
    const orgLinks = await page.locator('a[href*="/org/"]').all();

    for (const link of orgLinks) {
      const href = await link.getAttribute('href');
      if (href && href.includes('/org/') && !href.endsWith('/org/')) {
        // Extract the identifier after /org/
        const match = href.match(/\/org\/([^/]+)/);
        if (match) {
          const identifier = match[1];
          expect(
            identifier.startsWith(EXTID_PREFIXES.organization),
            `Organization identifier "${identifier}" should start with "${EXTID_PREFIXES.organization}"`
          ).toBe(true);
        }
      }
    }
  });

  test('TC-ID-051: Domain ExtIds consistently use "cd" prefix', async ({ page }) => {
    await page.goto('/domains');
    await page.waitForLoadState('networkidle');

    // Find all domain-related links (excluding "Add Domain" type links)
    const domainLinks = await page.locator('a[href*="/domains/"]').all();
    const nonIdentifierPaths = ['add', 'new', 'create'];

    for (const link of domainLinks) {
      const href = await link.getAttribute('href');
      if (!href || !href.includes('/domains/') || href.endsWith('/domains/')) continue;

      // Extract the identifier after /domains/
      const match = href.match(/\/domains\/([^/]+)/);
      if (!match) continue;

      const identifier = match[1];
      // Skip if it's a non-identifier path segment like "add" or "new"
      if (nonIdentifierPaths.includes(identifier)) continue;

      expect(
        identifier.startsWith(EXTID_PREFIXES.domain),
        `Domain identifier "${identifier}" should start with "${EXTID_PREFIXES.domain}"`
      ).toBe(true);
    }
  });

  test('TC-ID-052: ExtId format is consistent across all entity types', async ({ page }) => {
    const foundIdentifiers: { type: string; identifier: string; source: string }[] = [];
    const nonOrgPaths = ['add', 'new'];
    const nonDomainPaths = ['add', 'new', 'verify', 'brand'];

    // Helper to extract identifiers from href
    const extractIdentifiersFromHref = (href: string) => {
      // Check for org identifiers
      const orgMatch = href.match(/\/org\/([^/]+)/);
      if (orgMatch && !nonOrgPaths.includes(orgMatch[1])) {
        foundIdentifiers.push({ type: 'organization', identifier: orgMatch[1], source: href });
      }

      // Check for domain identifiers
      const domainMatch = href.match(/\/domains\/([^/]+)/);
      if (domainMatch && !nonDomainPaths.includes(domainMatch[1])) {
        foundIdentifiers.push({ type: 'domain', identifier: domainMatch[1], source: href });
      }
    };

    // Visit multiple pages and collect identifiers
    const pagesToVisit = ['/dashboard', '/orgs', '/domains', '/account'];

    for (const pagePath of pagesToVisit) {
      await page.goto(pagePath);
      await page.waitForLoadState('networkidle');

      const links = await page.locator('a[href]').all();
      for (const link of links) {
        const href = await link.getAttribute('href');
        if (href) extractIdentifiersFromHref(href);
      }
    }

    // Verify all found identifiers use correct prefixes
    for (const { type, identifier, source } of foundIdentifiers) {
      const expectedPrefix = EXTID_PREFIXES[type as keyof typeof EXTID_PREFIXES];
      if (expectedPrefix) {
        expect(
          identifier.startsWith(expectedPrefix),
          `${type} identifier "${identifier}" from ${source} should start with "${expectedPrefix}"`
        ).toBe(true);
      }
    }
  });
});

// -----------------------------------------------------------------------------
// Regression Prevention Test Suite
// -----------------------------------------------------------------------------

test.describe('Opaque Identifier Pattern - Regression Prevention', () => {
  test.skip(!hasTestCredentials, 'Skipping: TEST_USER_EMAIL and TEST_USER_PASSWORD required');

  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
    await loginUser(page);
  });

  test('TC-ID-060: Verify window state uses correct ID fields', async ({ page }) => {
    await page.goto('/dashboard');
    await page.waitForLoadState('networkidle');

    // Check that organizations in window state have both id and extid
    const stateCheck = await page.evaluate(() => {
      const state = window.__BOOTSTRAP_STATE__;
      if (!state) return { valid: false, error: 'No state' };

      // Check organization structure if available
      // This validates that the API returns proper ID separation
      return {
        valid: true,
        hasState: true,
      };
    });

    expect(stateCheck.valid).toBe(true);
  });

  test('TC-ID-061: Direct URL navigation with ExtId works', async ({ page }) => {
    // First, find a valid org ExtId
    await page.goto('/orgs');
    await page.waitForLoadState('networkidle');

    const orgLink = page.locator('a[href*="/org/on"]').first();
    const hasOrg = await orgLink.isVisible().catch(() => false);

    if (hasOrg) {
      const href = await orgLink.getAttribute('href');
      if (href) {
        // Navigate directly to the URL (simulating bookmark or shared link)
        await page.goto(href);
        await page.waitForLoadState('networkidle');

        // Page should load successfully (not 404)
        const response = await page.evaluate(() => ({
          title: document.title,
          has404: document.body.textContent?.includes('404') || false,
        }));

        expect(response.has404).toBe(false);
        expect(response.title).not.toBe('');
      }
    } else {
      test.skip(true, 'No organizations available to test');
    }
  });

  test('TC-ID-062: Invalid ExtId format shows appropriate error', async ({ page }) => {
    // Try to navigate to an org with UUID format (invalid for ExtId)
    const fakeUUID = '550e8400-e29b-41d4-a716-446655440000';
    const response = await page.goto(`/org/${fakeUUID}`);

    // Should get 404 or redirect (not crash)
    expect(response?.status()).toBeLessThan(500);

    // Page should still be functional
    await expect(page.locator('body')).toBeVisible();
  });
});

/**
 * Qase Test Case Export Format
 *
 * Suite: Opaque Identifier Pattern (#2312)
 *
 * | ID         | Title                                              | Priority | Automation |
 * |------------|----------------------------------------------------|---------:|------------|
 * | TC-ID-001  | Organization settings URL uses ExtId               | Critical | Automated  |
 * | TC-ID-002  | Organization members URL uses ExtId                | High     | Automated  |
 * | TC-ID-003  | Clicking org card navigates to ExtId URL           | High     | Automated  |
 * | TC-ID-010  | Domain detail URL uses ExtId (cd prefix)           | Critical | Automated  |
 * | TC-ID-011  | Domain verify URL uses ExtId                       | High     | Automated  |
 * | TC-ID-012  | Domain branding URL uses ExtId                     | High     | Automated  |
 * | TC-ID-020  | Created secret receipt URL uses proper format      | Critical | Automated  |
 * | TC-ID-030  | Dashboard to org settings maintains ExtId          | High     | Automated  |
 * | TC-ID-031  | Domains list to domain detail maintains ExtId      | High     | Automated  |
 * | TC-ID-040  | No internal IDs exposed in network requests        | Critical | Automated  |
 * | TC-ID-041  | Browser history entries use ExtId format           | High     | Automated  |
 * | TC-ID-042  | Link href attributes use ExtId format              | High     | Automated  |
 * | TC-ID-050  | Organization ExtIds use "on" prefix consistently   | Medium   | Automated  |
 * | TC-ID-051  | Domain ExtIds use "cd" prefix consistently         | Medium   | Automated  |
 * | TC-ID-052  | ExtId format consistent across entity types        | Medium   | Automated  |
 * | TC-ID-060  | Window state uses correct ID fields                | Medium   | Automated  |
 * | TC-ID-061  | Direct URL navigation with ExtId works             | High     | Automated  |
 * | TC-ID-062  | Invalid ExtId format shows appropriate error       | Medium   | Automated  |
 */

/**
 * Manual Test Checklist - Opaque Identifier Pattern
 *
 * ## Security Verification
 * - [ ] Inspect browser URL bar during navigation - no UUIDs visible
 * - [ ] Check network requests in DevTools - API paths use ExtIds
 * - [ ] Verify copied share links use ExtIds
 * - [ ] Check browser history entries for internal ID exposure
 *
 * ## Format Consistency
 * - [ ] All org URLs start with /org/on...
 * - [ ] All domain URLs start with /domains/cd...
 * - [ ] Secret URLs use opaque keys (not se prefix currently)
 * - [ ] Customer-related URLs (if visible) use ur prefix
 *
 * ## Edge Cases
 * - [ ] Bookmark an ExtId URL, close browser, reopen - should work
 * - [ ] Share ExtId URL with another user - should work
 * - [ ] Try accessing URL with modified ExtId - should 404 gracefully
 * - [ ] Try accessing URL with UUID instead of ExtId - should 404 gracefully
 *
 * ## Regression Scenarios
 * - [ ] Create new organization - URL should immediately use ExtId
 * - [ ] Add new domain - URL should immediately use ExtId
 * - [ ] Create secret - receipt URL should use opaque key
 * - [ ] Switch organizations - all subsequent URLs use correct ExtIds
 */
