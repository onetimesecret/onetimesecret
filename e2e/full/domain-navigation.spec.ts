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

import { hasCustomDomain, orgsSsoEnabled } from '../support/env';

// Environment gate (plan Phase 2.4): every test navigates per-domain config
// pages, which need a custom domain on the test account (DOMAINS_ENABLED=true
// on the target; off in CI). The SSO-page tests additionally need
// E2E_ORGS_SSO. With the gates set, preconditions are asserted, not probed.
test.skip(
  !hasCustomDomain,
  'Domain config pages require E2E_CUSTOM_DOMAINS>=1 (see e2e/support/env.ts)'
);

// -----------------------------------------------------------------------------
// Types
// -----------------------------------------------------------------------------

interface OrgInfo {
  extid: string;
  name: string;
}

interface DomainInfo {
  extid: string;
  displayDomain: string;
}

// -----------------------------------------------------------------------------
// Test Helpers
// -----------------------------------------------------------------------------

/**
 * Get the first organization the user has access to
 */
async function getFirstOrganization(page: Page): Promise<OrgInfo | null> {
  await page.goto('/orgs');
  await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

  const orgLink = page.locator('a[href*="/org/"]').first();
  if (!(await orgLink.isVisible().catch(() => false))) {
    return null;
  }

  const href = await orgLink.getAttribute('href');
  const match = href?.match(/\/org\/([^/]+)/);
  if (!match) return null;

  const extid = match[1];
  const nameElement = orgLink.locator('span.truncate, .font-medium, h3, h4').first();
  const name = (await nameElement.textContent())?.trim() || extid;

  return { extid, name };
}

/**
 * Get the first domain in the organization
 */
async function getFirstDomain(page: Page, orgExtid: string): Promise<DomainInfo | null> {
  await page.goto(`/org/${orgExtid}/domains`);
  await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

  const domainLink = page.locator('a[href*="/domains/"]').first();
  if (!(await domainLink.isVisible().catch(() => false))) {
    return null;
  }

  const href = await domainLink.getAttribute('href');
  const match = href?.match(/\/domains\/([^/]+)/);
  if (!match) return null;

  const domainText = await domainLink.locator('.font-medium, .truncate').first().textContent();

  return {
    extid: match[1],
    displayDomain: domainText?.trim() || match[1],
  };
}

/**
 * Find and click the back button on a domain sub-page
 */
async function clickBackButton(page: Page): Promise<void> {
  // Look for back button - typically has arrow-left icon or "back" text
  const backButton = page.locator('button:has([name="arrow-left"]), button:has-text("Back")').first();
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
    test.skip(
      !orgsSsoEnabled,
      'Domain SSO page requires E2E_ORGS_SSO=true (see e2e/support/env.ts)'
    );

    const org = await getFirstOrganization(page);
    expect(org, 'every customer has a default workspace (create_default_workspace.rb)').toBeTruthy();

    const domain = await getFirstDomain(page, org!.extid);
    expect(domain, 'E2E_CUSTOM_DOMAINS promises at least one domain').toBeTruthy();

    // Navigate to SSO config page
    const ssoUrl = `/org/${org!.extid}/domains/${domain!.extid}/sso`;
    await page.goto(ssoUrl);
    await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

    // Verify we're on the SSO page - E2E_ORGS_SSO promises access
    const ssoTitle = page.locator('[data-testid="sso-config-title"], h2:has-text("SSO")');
    await expect(ssoTitle).toBeVisible();

    // Click back button
    await clickBackButton(page);

    // Verify navigation to DomainDetail (not domains list)
    const expectedUrl = `/org/${org!.extid}/domains/${domain!.extid}`;
    await page.waitForURL(new RegExp(`${expectedUrl}$`), { timeout: 5000 });

    // Should NOT be on domains list (which would end with just /domains)
    expect(page.url()).not.toMatch(/\/domains$/);
    // Should be on domain detail page
    expect(page.url()).toMatch(new RegExp(`/domains/${domain!.extid}$`));
  });

  test('TC-DN-002: Incoming page back button navigates to DomainDetail', async ({ page }) => {
    const org = await getFirstOrganization(page);
    expect(org, 'every customer has a default workspace (create_default_workspace.rb)').toBeTruthy();

    const domain = await getFirstDomain(page, org!.extid);
    expect(domain, 'E2E_CUSTOM_DOMAINS promises at least one domain').toBeTruthy();

    // Navigate to Incoming config page
    const incomingUrl = `/org/${org!.extid}/domains/${domain!.extid}/incoming`;
    await page.goto(incomingUrl);
    await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

    // Verify we're on the Incoming page - the provisioned environment the
    // E2E_CUSTOM_DOMAINS gate documents grants incoming_secrets (automatic
    // on standalone targets)
    const incomingTitle = page.locator('h2:has-text("Incoming")');
    await expect(incomingTitle).toBeVisible();

    // Click back button
    await clickBackButton(page);

    // Verify navigation to DomainDetail
    const expectedUrl = `/org/${org!.extid}/domains/${domain!.extid}`;
    await page.waitForURL(new RegExp(`${expectedUrl}$`), { timeout: 5000 });

    expect(page.url()).not.toMatch(/\/domains$/);
    expect(page.url()).toMatch(new RegExp(`/domains/${domain!.extid}$`));
  });

  test('TC-DN-003: Verify page back button navigates to DomainDetail', async ({ page }) => {
    const org = await getFirstOrganization(page);
    expect(org, 'every customer has a default workspace (create_default_workspace.rb)').toBeTruthy();

    const domain = await getFirstDomain(page, org!.extid);
    expect(domain, 'E2E_CUSTOM_DOMAINS promises at least one domain').toBeTruthy();

    // Navigate to Verify page
    const verifyUrl = `/org/${org!.extid}/domains/${domain!.extid}/verify`;
    await page.goto(verifyUrl);
    await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

    // Verify we're on the Verify page
    const verifyTitle = page.locator('h2:has-text("Verify")');
    const onVerifyPage = await verifyTitle.isVisible().catch(() => false);

    // Click back button
    await clickBackButton(page);

    // Verify navigation to DomainDetail
    const expectedUrl = `/org/${org!.extid}/domains/${domain!.extid}`;
    await page.waitForURL(new RegExp(`${expectedUrl}$`), { timeout: 5000 });

    expect(page.url()).not.toMatch(/\/domains$/);
    expect(page.url()).toMatch(new RegExp(`/domains/${domain!.extid}$`));
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
    expect(org, 'every customer has a default workspace (create_default_workspace.rb)').toBeTruthy();

    const domain = await getFirstDomain(page, org!.extid);
    expect(domain, 'E2E_CUSTOM_DOMAINS promises at least one domain').toBeTruthy();

    // Navigate to Incoming config page
    const incomingUrl = `/org/${org!.extid}/domains/${domain!.extid}/incoming`;
    await page.goto(incomingUrl);
    await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

    // The provisioned environment grants incoming access - the header's
    // external link must render
    const externalLink = page.locator('a[target="_blank"][href*="https://"]').first();
    await expect(externalLink).toBeVisible();
    const href = await externalLink.getAttribute('href');

    // Should include /incoming path
    expect(href).toContain('/incoming');
    expect(href).toMatch(new RegExp(`https://${domain!.displayDomain}/incoming`));
  });

  test('TC-DN-005: DomainSso header link does not include path suffix', async ({ page }) => {
    test.skip(
      !orgsSsoEnabled,
      'Domain SSO page requires E2E_ORGS_SSO=true (see e2e/support/env.ts)'
    );

    const org = await getFirstOrganization(page);
    expect(org, 'every customer has a default workspace (create_default_workspace.rb)').toBeTruthy();

    const domain = await getFirstDomain(page, org!.extid);
    expect(domain, 'E2E_CUSTOM_DOMAINS promises at least one domain').toBeTruthy();

    // Navigate to SSO config page
    const ssoUrl = `/org/${org!.extid}/domains/${domain!.extid}/sso`;
    await page.goto(ssoUrl);
    await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

    // E2E_ORGS_SSO promises access - the header's external link must render
    const externalLink = page.locator('a[target="_blank"][href*="https://"]').first();
    await expect(externalLink).toBeVisible();
    const href = await externalLink.getAttribute('href');

    // Should NOT have any path suffix (just the domain)
    expect(href).toBe(`https://${domain!.displayDomain}`);
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
