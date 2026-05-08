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
 * - Set TEST_USER_EMAIL and TEST_USER_PASSWORD environment variables
 * - User must have access to an organization with at least one domain
 *
 * Usage:
 *   TEST_USER_EMAIL=test@example.com TEST_USER_PASSWORD=secret \
 *     pnpm playwright test domain-navigation.spec.ts
 */

import { expect, Page, test } from '@playwright/test';

const hasTestCredentials = !!(process.env.TEST_USER_EMAIL && process.env.TEST_USER_PASSWORD);

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
 * Authenticate user via login form
 */
async function loginUser(page: Page): Promise<void> {
  await page.goto('/signin');

  const passwordTab = page.getByRole('tab', { name: /password/i });
  await passwordTab.waitFor({ state: 'visible', timeout: 5000 });
  await passwordTab.click();

  const passwordInput = page.locator('input[type="password"]');
  await passwordInput.waitFor({ state: 'visible', timeout: 5000 });

  const emailInput = page.locator('#signin-email-password');
  await emailInput.fill(process.env.TEST_USER_EMAIL || '');
  await passwordInput.fill(process.env.TEST_USER_PASSWORD || '');

  const submitButton = page.locator('button[type="submit"]');
  await submitButton.click();

  await page.waitForURL(/\/(account|dashboard|org)/, { timeout: 30000 });
}

/**
 * Get the first organization the user has access to
 */
async function getFirstOrganization(page: Page): Promise<OrgInfo | null> {
  await page.goto('/orgs');
  await page.waitForLoadState('networkidle');

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
  await page.waitForLoadState('networkidle');

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
  test.skip(!hasTestCredentials, 'Skipping: TEST_USER_EMAIL and TEST_USER_PASSWORD required');

  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
    await loginUser(page);
  });

  test('TC-DN-001: SSO page back button navigates to DomainDetail', async ({ page }) => {
    const org = await getFirstOrganization(page);
    test.skip(!org, 'Test requires at least 1 organization');

    const domain = await getFirstDomain(page, org!.extid);
    test.skip(!domain, 'Test requires at least 1 domain');

    // Navigate to SSO config page
    const ssoUrl = `/org/${org!.extid}/domains/${domain!.extid}/sso`;
    await page.goto(ssoUrl);
    await page.waitForLoadState('networkidle');

    // Verify we're on the SSO page
    const ssoTitle = page.locator('[data-testid="sso-config-title"], h2:has-text("SSO")');
    const onSsoPage = await ssoTitle.isVisible().catch(() => false);

    // SSO might require entitlement - skip if access denied
    if (!onSsoPage) {
      const accessDenied = await page.locator('text=access denied').first().isVisible().catch(() => false);
      test.skip(accessDenied, 'SSO access denied - requires entitlement');
    }

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
    test.skip(!org, 'Test requires at least 1 organization');

    const domain = await getFirstDomain(page, org!.extid);
    test.skip(!domain, 'Test requires at least 1 domain');

    // Navigate to Incoming config page
    const incomingUrl = `/org/${org!.extid}/domains/${domain!.extid}/incoming`;
    await page.goto(incomingUrl);
    await page.waitForLoadState('networkidle');

    // Verify we're on the Incoming page or check for access denied
    const incomingTitle = page.locator('h2:has-text("Incoming")');
    const onIncomingPage = await incomingTitle.isVisible().catch(() => false);

    if (!onIncomingPage) {
      const accessDenied = await page.locator('text=access denied').first().isVisible().catch(() => false);
      test.skip(accessDenied, 'Incoming access denied - requires entitlement');
    }

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
    test.skip(!org, 'Test requires at least 1 organization');

    const domain = await getFirstDomain(page, org!.extid);
    test.skip(!domain, 'Test requires at least 1 domain');

    // Navigate to Verify page
    const verifyUrl = `/org/${org!.extid}/domains/${domain!.extid}/verify`;
    await page.goto(verifyUrl);
    await page.waitForLoadState('networkidle');

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
  test.skip(!hasTestCredentials, 'Skipping: TEST_USER_EMAIL and TEST_USER_PASSWORD required');

  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
    await loginUser(page);
  });

  test('TC-DN-004: DomainIncoming header link includes /incoming path', async ({ page }) => {
    const org = await getFirstOrganization(page);
    test.skip(!org, 'Test requires at least 1 organization');

    const domain = await getFirstDomain(page, org!.extid);
    test.skip(!domain, 'Test requires at least 1 domain');

    // Navigate to Incoming config page
    const incomingUrl = `/org/${org!.extid}/domains/${domain!.extid}/incoming`;
    await page.goto(incomingUrl);
    await page.waitForLoadState('networkidle');

    // Check for access denied
    const accessDenied = await page.locator('text=access denied').first().isVisible().catch(() => false);
    test.skip(accessDenied, 'Incoming access denied - requires entitlement');

    // Find the external link in the header
    const externalLink = page.locator('a[target="_blank"][href*="https://"]').first();
    const href = await externalLink.getAttribute('href');

    // Should include /incoming path
    expect(href).toContain('/incoming');
    expect(href).toMatch(new RegExp(`https://${domain!.displayDomain}/incoming`));
  });

  test('TC-DN-005: DomainSso header link does not include path suffix', async ({ page }) => {
    const org = await getFirstOrganization(page);
    test.skip(!org, 'Test requires at least 1 organization');

    const domain = await getFirstDomain(page, org!.extid);
    test.skip(!domain, 'Test requires at least 1 domain');

    // Navigate to SSO config page
    const ssoUrl = `/org/${org!.extid}/domains/${domain!.extid}/sso`;
    await page.goto(ssoUrl);
    await page.waitForLoadState('networkidle');

    // Check for access denied
    const accessDenied = await page.locator('text=access denied').first().isVisible().catch(() => false);
    test.skip(accessDenied, 'SSO access denied - requires entitlement');

    // Find the external link in the header
    const externalLink = page.locator('a[target="_blank"][href*="https://"]').first();
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
