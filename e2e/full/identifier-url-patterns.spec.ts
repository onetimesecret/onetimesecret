// e2e/full/identifier-url-patterns.spec.ts

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
//   - Authenticated via the project storageState (e2e/global.setup.ts consumes
//     TEST_USER_*). The account owns exactly one organization, its default
//     workspace, and the org tests wait for it (e2e/support/organizations.ts).
//   - The domain tests need a custom domain on the account and are gated on
//     E2E_CUSTOM_DOMAINS (e2e/support/env.ts); no CI lane sets it.
//   - Application running locally or PLAYWRIGHT_BASE_URL set
//
// Usage:
//   TEST_USER_EMAIL=test@example.com TEST_USER_PASSWORD=secret \
//     pnpm test:playwright e2e/full/identifier-url-patterns.spec.ts

import { expect, type Locator, type Page, test } from '@playwright/test';

import { waitForAppReady, waitForPathname } from '../support/auth-journey';
import { env, gateReason } from '../support/env';
import { getFirstOrganization } from '../support/organizations';

// Extend Window interface for test-specific properties
declare global {
  interface Window {
    captureHistoryEntry?: (url: string) => void;
  }
}

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
 * Check if a URL path contains a UUID (internal ID format)
 * This is a security concern - internal IDs should not be in URLs
 */
function containsUUID(url: string): boolean {
  return PATTERNS.uuid.test(url);
}

/**
 * Check if a URL path contains a hex string ID (internal ID format)
 * that is NOT part of a valid ExtId prefix.
 * @internal Reserved for future use in more comprehensive ID detection
 *
 * Implementation note: We scan for hex ID matches and verify each is not
 * preceded by a valid ExtId prefix, avoiding string mutation patterns
 * that trigger CodeQL's incomplete-sanitization warnings.
 */
function _containsHexId(url: string): boolean {
  // Find all potential hex ID matches (16-32 hex chars)
  const hexPattern = /[0-9a-f]{16,32}/gi;
  let match: RegExpExecArray | null;

  while ((match = hexPattern.exec(url)) !== null) {
    const matchIndex = match.index;
    // Check if this hex string is preceded by a valid ExtId prefix (e.g., "/on", "/cd")
    // Valid ExtId pattern: slash + prefix + alphanumeric continuation into our match
    const precedingChars = url.slice(Math.max(0, matchIndex - 3), matchIndex);
    const isPartOfExtId = /\/(on|cd|ur|se|md)$/i.test(precedingChars);

    if (!isPartOfExtId) {
      // Found a hex ID that's not part of a valid ExtId
      return true;
    }
  }

  return false;
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

/** The org settings tab bar, which renders once the organization loads. */
function orgTablist(page: Page): Locator {
  return page.getByRole('tablist', { name: 'Organization settings tabs' });
}

/**
 * Open /domains (a legacy redirect to the active org's Domains tab) and
 * return the first custom domain's link. Only valid when the account has a
 * custom domain (E2E_CUSTOM_DOMAINS).
 */
async function firstDomainLink(page: Page): Promise<Locator> {
  await page.goto('/domains');
  await waitForPathname(page, /^\/org\/on[a-zA-Z0-9]+\/domains$/);

  const domainLink = page.locator('a[href*="/domains/cd"]').first();
  await expect(domainLink, 'the account has a custom domain (E2E_CUSTOM_DOMAINS)').toBeVisible();
  return domainLink;
}

/** Every href on the page, read once the caller has waited for its content. */
async function allHrefs(page: Page): Promise<string[]> {
  return page
    .locator('a[href]')
    .evaluateAll((links) => links.map((link) => link.getAttribute('href') ?? ''));
}

// -----------------------------------------------------------------------------
// URL Pattern Validation Test Suite
// -----------------------------------------------------------------------------

test.describe('Opaque Identifier Pattern - URL Security', () => {
  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
  });

  // -------------------------------------------------------------------------
  // TC-ID-001: Organization URLs use ExtId format
  // -------------------------------------------------------------------------
  test.describe('Organization URL Patterns', () => {
    test('TC-ID-001: Organization settings URL uses ExtId (on prefix)', async ({ page }) => {
      const org = await getFirstOrganization(page);
      expect(org.extid).toMatch(/^on[a-zA-Z0-9]+$/);

      // The card's domain-count link opens the org settings page
      await page
        .getByTestId(`org-card-${org.extid}`)
        .locator(`a[href="/org/${org.extid}"]`)
        .click();
      await waitForPathname(page, `/org/${org.extid}`);
      await expect(orgTablist(page)).toBeVisible();

      let currentUrl = page.url();
      expect(
        containsExtIdWithPrefix(currentUrl, EXTID_PREFIXES.organization),
        `Organization URL should contain ExtId with 'on' prefix. URL: ${currentUrl}`
      ).toBe(true);
      expect(
        containsUUID(currentUrl),
        `Organization URL should NOT contain UUID. URL: ${currentUrl}, Found IDs: ${extractIdentifiers(currentUrl).join(', ')}`
      ).toBe(false);

      // Switching to the Settings tab rewrites the URL with the same ExtId
      await page.getByTestId('org-tab-settings').click();
      await expect(page).toHaveURL(new RegExp(`/org/${org.extid}/settings$`));
      currentUrl = page.url();
      expect(containsUUID(currentUrl)).toBe(false);
    });

    test('TC-ID-002: Organization members URL uses ExtId', async ({ page }) => {
      const org = await getFirstOrganization(page);

      // The card's member-count link opens the Members tab
      await page
        .getByTestId(`org-card-${org.extid}`)
        .locator(`a[href="/org/${org.extid}/members"]`)
        .click();
      await waitForPathname(page, `/org/${org.extid}/members`);
      await expect(page.getByTestId('org-section-members')).toBeVisible();

      const currentUrl = page.url();
      expect(
        containsExtIdWithPrefix(currentUrl, EXTID_PREFIXES.organization),
        `Members URL should contain org ExtId. URL: ${currentUrl}`
      ).toBe(true);
      expect(containsUUID(currentUrl)).toBe(false);
    });

    test('TC-ID-003: Clicking org card navigates to ExtId URL', async ({ page }) => {
      const org = await getFirstOrganization(page);

      // The org name on the card is a button that routes to the org settings
      await page.getByTestId(`org-link-${org.extid}`).click();
      await waitForPathname(page, `/org/${org.extid}`);
      await expect(orgTablist(page)).toBeVisible();

      const currentUrl = page.url();
      expect(
        PATTERNS.orgExtId.test(currentUrl),
        `After clicking the org card, URL should have /org/on... pattern. URL: ${currentUrl}`
      ).toBe(true);
      expect(containsUUID(currentUrl)).toBe(false);
    });
  });

  // -------------------------------------------------------------------------
  // TC-ID-010: Domain URLs use ExtId format
  // -------------------------------------------------------------------------
  test.describe('Domain URL Patterns', () => {
    test.skip(!env.hasCustomDomains, gateReason.customDomains);

    test('TC-ID-010: Domain detail URL uses ExtId (cd prefix)', async ({ page }) => {
      const domainLink = await firstDomainLink(page);
      await domainLink.click();
      await page.waitForURL(/\/domains\/cd/);

      const currentUrl = page.url();
      expect(
        containsExtIdWithPrefix(currentUrl, EXTID_PREFIXES.domain),
        `Domain URL should contain ExtId with 'cd' prefix. URL: ${currentUrl}`
      ).toBe(true);
      expect(
        containsUUID(currentUrl),
        `Domain URL should NOT contain UUID. URL: ${currentUrl}`
      ).toBe(false);
    });

    test('TC-ID-011: Domain verify URL uses ExtId', async ({ page }) => {
      const href = await (await firstDomainLink(page)).getAttribute('href');
      expect(href).toBeTruthy();

      await page.goto(`${href}/verify`);
      await waitForAppReady(page);

      const currentUrl = page.url();
      expect(containsExtIdWithPrefix(currentUrl, EXTID_PREFIXES.domain)).toBe(true);
      expect(currentUrl).toContain('/verify');
      expect(containsUUID(currentUrl)).toBe(false);
    });

    test('TC-ID-012: Domain branding URL uses ExtId', async ({ page }) => {
      const href = await (await firstDomainLink(page)).getAttribute('href');
      expect(href).toBeTruthy();

      await page.goto(`${href}/brand`);
      await waitForAppReady(page);

      const currentUrl = page.url();
      expect(containsExtIdWithPrefix(currentUrl, EXTID_PREFIXES.domain)).toBe(true);
      expect(currentUrl).toContain('/brand');
      expect(containsUUID(currentUrl)).toBe(false);
    });
  });

  // -------------------------------------------------------------------------
  // TC-ID-020: Secret URLs use ExtId format
  // -------------------------------------------------------------------------
  test.describe('Secret URL Patterns', () => {
    test('TC-ID-020: Created secret receipt URL uses proper format', async ({ page }) => {
      // A signed-in visitor to / lands on the dashboard's workspace form
      await page.goto('/dashboard');
      await waitForAppReady(page);

      const secretInput = page.getByRole('textbox', { name: 'Secret content' });
      await expect(secretInput).toBeVisible();
      await secretInput.fill('Test secret for identifier pattern validation');
      await page.getByTestId('split-button-submit').click();

      // Without "Stay on page" the form navigates to the new receipt
      await page.waitForURL(/\/receipt\/.+/);

      const currentUrl = page.url();
      expect(
        containsUUID(currentUrl),
        `Secret receipt URL should NOT contain UUID. URL: ${currentUrl}`
      ).toBe(false);
      expect(
        /\/receipt\/[a-zA-Z0-9]+$/.test(currentUrl),
        `Receipt URL should have opaque identifier format. URL: ${currentUrl}`
      ).toBe(true);
    });
  });

  // -------------------------------------------------------------------------
  // TC-ID-030: Navigation flows maintain ExtId pattern
  // -------------------------------------------------------------------------
  test.describe('Navigation Flow URL Validation', () => {
    test('TC-ID-030: Dashboard to org settings maintains ExtId', async ({ page }) => {
      await page.goto('/dashboard');
      await waitForAppReady(page);

      // Track all navigation URLs
      const visitedUrls: string[] = [];
      page.on('framenavigated', (frame) => {
        if (frame === page.mainFrame()) {
          visitedUrls.push(frame.url());
        }
      });

      // User menu > Domains goes through the legacy /domains redirect, which
      // resolves the active organization's ExtId
      await page.getByTestId('user-menu-trigger').click();
      await page.getByRole('menuitem', { name: 'Domains' }).click();
      await waitForPathname(page, /^\/org\/on[a-zA-Z0-9]+\/domains$/);
      await expect(orgTablist(page)).toBeVisible();

      expect(visitedUrls.length, 'navigation events were recorded').toBeGreaterThan(0);
      const urlsWithUUIDs = visitedUrls.filter(containsUUID);
      expect(
        urlsWithUUIDs.length,
        `Navigation should not expose UUIDs in URLs. Found: ${urlsWithUUIDs.join(', ')}`
      ).toBe(0);
    });

    test('TC-ID-031: Domains list to domain detail maintains ExtId', async ({ page }) => {
      test.skip(!env.hasCustomDomains, gateReason.customDomains);

      const domainLink = await firstDomainLink(page);

      const visitedUrls: string[] = [];
      page.on('framenavigated', (frame) => {
        if (frame === page.mainFrame()) {
          visitedUrls.push(frame.url());
        }
      });

      await domainLink.click();
      await page.waitForURL(/\/domains\/cd/);

      expect(visitedUrls.length, 'navigation events were recorded').toBeGreaterThan(0);
      const urlsWithUUIDs = visitedUrls.filter(containsUUID);
      expect(urlsWithUUIDs.length, `Found: ${urlsWithUUIDs.join(', ')}`).toBe(0);
    });
  });
});

// -----------------------------------------------------------------------------
// URL Security Validation Test Suite
// -----------------------------------------------------------------------------

test.describe('Opaque Identifier Pattern - Security Validation', () => {
  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
  });

  test('TC-ID-040: No internal IDs exposed in network requests', async ({ page }) => {
    const apiPaths: string[] = [];
    page.on('request', (request) => {
      const url = new URL(request.url());
      if (url.pathname.startsWith('/api/')) apiPaths.push(url.pathname);
    });

    // Navigate through several pages
    await page.goto('/dashboard');
    await waitForAppReady(page);

    const org = await getFirstOrganization(page);
    await page.getByTestId(`org-link-${org.extid}`).click();
    await waitForPathname(page, `/org/${org.extid}`);
    await expect(orgTablist(page)).toBeVisible();

    await page.goto('/domains');
    await waitForPathname(page, `/org/${org.extid}/domains`);
    await expect(orgTablist(page)).toBeVisible();

    // The org pages addressed the org by its ExtId, so the check saw
    // identifier-bearing requests
    expect(
      apiPaths.some((path) => path.includes(`/${org.extid}`)),
      `an API request addressed ${org.extid}. Seen: ${apiPaths.join(', ')}`
    ).toBe(true);

    const pathsWithInternalIds = apiPaths.filter(containsUUID);
    expect(
      pathsWithInternalIds.length,
      `API requests should use ExtIds, not internal IDs. Found: ${pathsWithInternalIds.join(', ')}`
    ).toBe(0);
  });

  test('TC-ID-041: Browser history entries use ExtId format', async ({ page }) => {
    const historyEntries: string[] = [];
    await page.exposeFunction('captureHistoryEntry', (url: string) => {
      historyEntries.push(url);
    });

    // Patch the History API in every document before the app's router runs,
    // so full page loads (page.goto) keep the capture in place
    await page.addInitScript(() => {
      const originalPushState = history.pushState;
      const originalReplaceState = history.replaceState;

      history.pushState = function (...args) {
        window.captureHistoryEntry?.(String(args[2] ?? ''));
        return originalPushState.apply(this, args);
      };
      history.replaceState = function (...args) {
        window.captureHistoryEntry?.(String(args[2] ?? ''));
        return originalReplaceState.apply(this, args);
      };
    });

    // Navigate through the app: the org card click is a router push
    const org = await getFirstOrganization(page);
    await page.getByTestId(`org-link-${org.extid}`).click();
    await waitForPathname(page, `/org/${org.extid}`);
    await expect(orgTablist(page)).toBeVisible();

    await expect
      .poll(() => historyEntries.some((entry) => entry.includes(`/org/${org.extid}`)), {
        message: `a history entry for /org/${org.extid}. Seen: ${historyEntries.join(', ')}`,
      })
      .toBe(true);

    const entriesWithInternalIds = historyEntries.filter((entry) => containsUUID(entry));
    expect(
      entriesWithInternalIds.length,
      `Browser history should not contain internal IDs. Found: ${entriesWithInternalIds.join(', ')}`
    ).toBe(0);
  });

  test('TC-ID-042: Link href attributes use ExtId format', async ({ page }) => {
    await page.goto('/dashboard');
    await waitForAppReady(page);
    const hrefs = await allHrefs(page);

    // The org list and the org settings page carry org-scoped links
    const org = await getFirstOrganization(page);
    hrefs.push(...(await allHrefs(page)));
    await page.goto(`/org/${org.extid}`);
    await expect(orgTablist(page)).toBeVisible();
    hrefs.push(...(await allHrefs(page)));

    expect(
      hrefs.some((href) => href.startsWith(`/org/${org.extid}`)),
      `links address the org by its ExtId. Seen: ${hrefs.join(', ')}`
    ).toBe(true);

    const linksWithInternalIds = hrefs.filter(containsUUID);
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
  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
  });

  test('TC-ID-050: Organization ExtIds consistently use "on" prefix', async ({ page }) => {
    // Waits for the org list, so its links are rendered
    const org = await getFirstOrganization(page);

    const identifiers = (await allHrefs(page))
      .map((href) => href.match(/\/org\/([^/]+)/)?.[1])
      .filter((identifier): identifier is string => !!identifier);

    expect(identifiers, 'the org card links to its org').toContain(org.extid);
    for (const identifier of identifiers) {
      expect(
        identifier.startsWith(EXTID_PREFIXES.organization),
        `Organization identifier "${identifier}" should start with "${EXTID_PREFIXES.organization}"`
      ).toBe(true);
    }
  });

  test('TC-ID-051: Domain ExtIds consistently use "cd" prefix', async ({ page }) => {
    test.skip(!env.hasCustomDomains, gateReason.customDomains);

    // Waits for the domain list, so its links are rendered
    await firstDomainLink(page);

    const nonIdentifierPaths = ['add', 'new', 'create'];
    const identifiers = (await allHrefs(page))
      .map((href) => href.match(/\/domains\/([^/]+)/)?.[1])
      .filter(
        (identifier): identifier is string =>
          !!identifier && !nonIdentifierPaths.includes(identifier)
      );

    expect(identifiers.length, 'the domain list links to its domains').toBeGreaterThan(0);
    for (const identifier of identifiers) {
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

    // Visit multiple pages and collect identifiers, each once its content
    // has rendered
    await page.goto('/dashboard');
    await waitForAppReady(page);
    (await allHrefs(page)).forEach(extractIdentifiersFromHref);

    const org = await getFirstOrganization(page);
    (await allHrefs(page)).forEach(extractIdentifiersFromHref);

    await page.goto('/domains');
    await waitForPathname(page, `/org/${org.extid}/domains`);
    await expect(orgTablist(page)).toBeVisible();
    (await allHrefs(page)).forEach(extractIdentifiersFromHref);

    await page.goto('/account');
    await waitForAppReady(page);
    (await allHrefs(page)).forEach(extractIdentifiersFromHref);

    expect(
      foundIdentifiers.some(({ identifier }) => identifier === org.extid),
      'the visited pages link to the org by its ExtId'
    ).toBe(true);

    // Verify all found identifiers use correct prefixes
    for (const { type, identifier, source } of foundIdentifiers) {
      const expectedPrefix = EXTID_PREFIXES[type as keyof typeof EXTID_PREFIXES];
      expect(
        identifier.startsWith(expectedPrefix),
        `${type} identifier "${identifier}" from ${source} should start with "${expectedPrefix}"`
      ).toBe(true);
    }
  });
});

// -----------------------------------------------------------------------------
// Regression Prevention Test Suite
// -----------------------------------------------------------------------------

test.describe('Opaque Identifier Pattern - Regression Prevention', () => {
  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
  });

  test('TC-ID-060: Bootstrap state separates internal IDs from ExtIds', async ({ page }) => {
    // window.__BOOTSTRAP_ME__ is replaced with `true` once the app consumes
    // it (src/services/bootstrap.service.ts). /bootstrap/me serves the same
    // payload from the same serializers.
    const response = await page.request.get('/bootstrap/me');
    expect(response.ok()).toBe(true);
    const state = await response.json();

    // The current organization carries both IDs, and they differ
    expect(state.organization?.objid).toMatch(PATTERNS.uuid);
    expect(state.organization?.extid).toMatch(/^on[a-zA-Z0-9]+$/);
    expect(state.organization.extid).not.toBe(state.organization.objid);

    // So does the customer
    expect(state.cust?.objid).toMatch(PATTERNS.uuid);
    expect(state.cust?.extid).toMatch(/^ur[a-zA-Z0-9]+$/);

    // Org URLs use the ExtId, not the objid
    const org = await getFirstOrganization(page);
    expect(org.extid).toBe(state.organization.extid);
  });

  test('TC-ID-061: Direct URL navigation with ExtId works', async ({ page }) => {
    const org = await getFirstOrganization(page);

    // Open the org settings URL directly (a bookmark or shared link)
    await page.goto(`/org/${org.extid}`);
    await expect(orgTablist(page)).toBeVisible();
    await expect(page).toHaveURL(new RegExp(`/org/${org.extid}$`));
  });

  test('TC-ID-062: Internal org ID in the URL does not open the org', async ({ page }) => {
    // The org's internal objid (a UUID) is not an address for it
    const response = await page.request.get('/bootstrap/me');
    const objid: string = (await response.json()).organization?.objid;
    expect(objid).toMatch(PATTERNS.uuid);

    const apiResponse = await page.request.get(`/api/organizations/${objid}`);
    expect(apiResponse.status()).toBe(404);

    // The org fetch 404s, the role guard fails closed and the app redirects
    // to /dashboard (src/router/guards.routes.ts, handleOrgRoleRequirement)
    await page.goto(`/org/${objid}`);
    await expect(page).toHaveURL(/\/dashboard$/);
    await expect(orgTablist(page)).toHaveCount(0);
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
 * | TC-ID-060  | Bootstrap state separates internal IDs from ExtIds | Medium   | Automated  |
 * | TC-ID-061  | Direct URL navigation with ExtId works             | High     | Automated  |
 * | TC-ID-062  | Internal org ID in the URL does not open the org   | Medium   | Automated  |
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
