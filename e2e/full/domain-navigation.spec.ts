// e2e/full/domain-navigation.spec.ts

/**
 * E2E Tests for Domain Sub-page Navigation
 *
 * Tests that back buttons on domain sub-pages navigate to the correct parent page:
 * - DomainSso -> DomainDetail
 * - DomainIncoming -> DomainDetail
 * - DomainVerify -> DomainDetail
 *
 * Prerequisites:
 * - Authenticated via the project storageState (e2e/global.setup.ts consumes TEST_USER_*)
 * - User must have access to an organization with at least one domain
 *
 * Usage:
 *   TEST_USER_EMAIL=test@example.com TEST_USER_PASSWORD=secret \
 *     pnpm playwright test domain-navigation.spec.ts
 */

import { expect, Page, test } from '@playwright/test';

import { env, gateReason } from '../support/env';
import { getFirstDomain } from '../support/domains';
import { getFirstOrganization } from '../support/organizations';

// HOLDING ACTION — not coverage (E2E remediation plan Phase 2.4 / PR 5).
// Every test needs a custom domain on the test account (optional deployment
// config), so it is env-gated rather than fixme'd (issue #3420): set
// E2E_CUSTOM_DOMAINS against a domains-enabled target to run it. No CI lane
// sets that yet, so this suite is DORMANT in CI — real coverage returns when
// PR 6 adds a domains-enabled lane + fixtures. Gating before the body runs
// keeps CI from timing out in the org/domain DOM helpers.
test.beforeEach(() => {
  test.skip(!env.hasCustomDomains, gateReason.customDomains);
});

// -----------------------------------------------------------------------------
// Test Helpers
// -----------------------------------------------------------------------------

/**
 * Find and click the back button on a domain sub-page
 */
async function clickBackButton(page: Page): Promise<void> {
  // Look for back button - typically has arrow-left icon or "back" text
  const backButton = page
    .locator('button:has([name="arrow-left"]), button:has-text("Back")')
    .first();
  await backButton.waitFor({ state: 'visible', timeout: 5000 });
  await backButton.click();
}

// -----------------------------------------------------------------------------
// Test Suite: Domain Sub-page Navigation
// -----------------------------------------------------------------------------

test.describe('Domain Sub-page Navigation', () => {
  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
  });

  test('TC-DN-001: SSO page back button navigates to DomainDetail', async ({ page }) => {
    test.fixme(
      !env.hasSsoUi,
      'Needs org SSO turned on for the custom domain (E2E_SSO_UI); no lane configures it. See #3420.'
    );
    const org = await getFirstOrganization(page);

    const domain = await getFirstDomain(page, org.extid);

    // Navigate to SSO config page
    const ssoUrl = `/org/${org.extid}/domains/${domain.extid}/sso`;
    await page.goto(ssoUrl);
    await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

    // Verify we're on the SSO page (not an access-denied block)
    const ssoTitle = page.locator('[data-testid="sso-config-title"], h2:has-text("SSO")');
    await expect(ssoTitle.first(), 'the SSO config page renders').toBeVisible();

    // Click back button
    await clickBackButton(page);

    // Verify navigation to DomainDetail (not domains list)
    const expectedUrl = `/org/${org.extid}/domains/${domain.extid}`;
    await page.waitForURL(new RegExp(`${expectedUrl}$`), { timeout: 5000 });

    // Should NOT be on domains list (which would end with just /domains)
    expect(page.url()).not.toMatch(/\/domains$/);
    // Should be on domain detail page
    expect(page.url()).toMatch(new RegExp(`/domains/${domain.extid}$`));
  });

  test('TC-DN-002: Incoming page back button navigates to DomainDetail', async ({ page }) => {
    const org = await getFirstOrganization(page);

    const domain = await getFirstDomain(page, org.extid);

    // Navigate to Incoming config page
    const incomingUrl = `/org/${org.extid}/domains/${domain.extid}/incoming`;
    await page.goto(incomingUrl);
    await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

    // Verify we're on the Incoming page (not an access-denied block)
    const incomingTitle = page.locator('h2:has-text("Incoming")');
    await expect(incomingTitle.first(), 'the Incoming config page renders').toBeVisible();

    // Click back button
    await clickBackButton(page);

    // Verify navigation to DomainDetail
    const expectedUrl = `/org/${org.extid}/domains/${domain.extid}`;
    await page.waitForURL(new RegExp(`${expectedUrl}$`), { timeout: 5000 });

    expect(page.url()).not.toMatch(/\/domains$/);
    expect(page.url()).toMatch(new RegExp(`/domains/${domain.extid}$`));
  });

  test('TC-DN-003: Verify page back button navigates to DomainDetail', async ({ page }) => {
    const org = await getFirstOrganization(page);

    const domain = await getFirstDomain(page, org.extid);

    // Navigate to Verify page
    const verifyUrl = `/org/${org.extid}/domains/${domain.extid}/verify`;
    await page.goto(verifyUrl);
    await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

    // Verify we're on the Verify page
    const verifyTitle = page.locator('h2:has-text("Verify")');
    await expect(verifyTitle.first(), 'the Verify page renders').toBeVisible();

    // Click back button
    await clickBackButton(page);

    // Verify navigation to DomainDetail
    const expectedUrl = `/org/${org.extid}/domains/${domain.extid}`;
    await page.waitForURL(new RegExp(`${expectedUrl}$`), { timeout: 5000 });

    expect(page.url()).not.toMatch(/\/domains$/);
    expect(page.url()).toMatch(new RegExp(`/domains/${domain.extid}$`));
  });
});

// -----------------------------------------------------------------------------
// Test Suite: DomainHeader External Link
// -----------------------------------------------------------------------------

test.describe('DomainHeader External Link', () => {
  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
  });

  test('TC-DN-004: DomainIncoming header link includes /incoming path', async ({ page }) => {
    const org = await getFirstOrganization(page);

    const domain = await getFirstDomain(page, org.extid);

    // Navigate to Incoming config page
    const incomingUrl = `/org/${org.extid}/domains/${domain.extid}/incoming`;
    await page.goto(incomingUrl);
    await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

    // The page must render, not an access-denied block
    await expect(page.locator('h2:has-text("Incoming")').first()).toBeVisible();

    // Find the external link in the header
    const externalLink = page.locator('a[target="_blank"][href*="https://"]').first();
    const href = await externalLink.getAttribute('href');

    // Should include /incoming path
    expect(href).toContain('/incoming');
    expect(href).toMatch(new RegExp(`https://${domain.displayDomain}/incoming`));
  });

  test('TC-DN-005: DomainSso header link does not include path suffix', async ({ page }) => {
    test.fixme(
      !env.hasSsoUi,
      'Needs org SSO turned on for the custom domain (E2E_SSO_UI); no lane configures it. See #3420.'
    );
    const org = await getFirstOrganization(page);

    const domain = await getFirstDomain(page, org.extid);

    // Navigate to SSO config page
    const ssoUrl = `/org/${org.extid}/domains/${domain.extid}/sso`;
    await page.goto(ssoUrl);
    await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

    // The page must render, not an access-denied block
    await expect(
      page.locator('[data-testid="sso-config-title"], h2:has-text("SSO")').first()
    ).toBeVisible();

    // Find the external link in the header
    const externalLink = page.locator('a[target="_blank"][href*="https://"]').first();
    const href = await externalLink.getAttribute('href');

    // Should NOT have any path suffix (just the domain)
    expect(href).toBe(`https://${domain.displayDomain}`);
  });
});

/**
 * Qase Test Case Export Format
 *
 * Suite: Domain Sub-page Navigation
 *
 * | ID        | Title                                                | Priority | Automation |
 * |-----------|------------------------------------------------------|----------|------------|
 * | TC-DN-001 | SSO page back button navigates to DomainDetail       | High     | Automated  |
 * | TC-DN-002 | Incoming page back button navigates to DomainDetail  | High     | Automated  |
 * | TC-DN-003 | Verify page back button navigates to DomainDetail    | High     | Automated  |
 * | TC-DN-004 | DomainIncoming header link includes /incoming path   | Medium   | Automated  |
 * | TC-DN-005 | DomainSso header link has no path suffix             | Medium   | Automated  |
 */
