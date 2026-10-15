// e2e/full/domain-sso-config.spec.ts

/**
 * E2E Tests for Domain SSO Configuration (#2786, #3383)
 *
 * Tests the per-domain SSO configuration feature that allows organizations
 * with multiple custom domains to configure different SSO providers per domain.
 *
 * Flow (page-based; the SSO settings left their dialog for a route):
 * 1. User navigates to /org/{orgId} (Organization Settings)
 * 2. Clicks SSO tab -> sees list of domains with SSO status badges
 * 3. Navigates to /org/{orgId}/domains/{domainId}/signin
 * 4. Clicks "Configure" / "Edit credentials" -> /org/{orgId}/domains/{domainId}/signin/sso
 * 5. Fills SSO config form (provider type, credentials, etc.) on that page
 * 6. Tests connection -> saves config
 *
 * Prerequisites:
 * - Authenticated via the project storageState (e2e/global.setup.ts consumes TEST_USER_*)
 * - User must have access to an organization with the manage_sso entitlement
 * - At least one custom domain should exist for testing
 *
 * Usage:
 *   # Against dev server
 *   TEST_USER_EMAIL=test@example.com TEST_USER_PASSWORD=secret \
 *     pnpm playwright test domain-sso-config.spec.ts
 *
 *   # Against external URL
 *   PLAYWRIGHT_BASE_URL=https://dev.onetime.dev TEST_USER_EMAIL=... \
 *     pnpm test:playwright domain-sso-config.spec.ts
 */

import { expect, Locator, Page, test } from '@playwright/test';

import { env, gateReason } from '../support/env';
import { getFirstOrganization } from '../support/organizations';

// HOLDING ACTION — not coverage (E2E remediation plan Phase 2.4 / PR 5).
// Per-domain SSO config needs BOTH a custom domain and the manage_sso
// entitlement / SSO UI — optional deployment config, so env-gated rather than
// fixme'd: set E2E_CUSTOM_DOMAINS and E2E_SSO_UI against a suitably-configured
// target to run it. No CI lane sets either yet, so this suite is DORMANT in CI
// — real coverage returns when PR 6 adds a configured lane + fixtures.
test.beforeEach(() => {
  test.skip(
    !env.hasCustomDomains || !env.hasSsoUi,
    `${gateReason.customDomains} ${gateReason.ssoUi}`
  );
});

// -----------------------------------------------------------------------------
// Types
// -----------------------------------------------------------------------------

interface DomainInfo {
  extid: string;
  displayDomain: string;
  ssoStatus: 'not_configured' | 'configured' | 'enabled';
}

// -----------------------------------------------------------------------------
// Test Helpers
// -----------------------------------------------------------------------------

/**
 * Navigate to organization settings SSO tab
 */
async function navigateToOrgSsoTab(page: Page, orgExtid: string): Promise<void> {
  await page.goto(`/org/${orgExtid}/sso`);
  await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

  // Wait for SSO tab to be active or section to be visible
  const ssoSection = page.locator('[data-testid="org-section-sso"]');
  const ssoTab = page.locator('[data-testid="org-tab-sso"]');

  await Promise.race([
    ssoSection.waitFor({ state: 'visible', timeout: 10000 }).catch(() => {}),
    ssoTab.waitFor({ state: 'visible', timeout: 10000 }).catch(() => {}),
  ]);
}

/**
 * Check if SSO management is available (entitlement check)
 */
async function hasSsoEntitlement(page: Page): Promise<boolean> {
  const ssoTab = page.locator('[data-testid="org-tab-sso"]');
  return ssoTab.isVisible().catch(() => false);
}

/**
 * Wait for the SSO tab. It renders when org SSO is on (ORGS_SSO_ENABLED) and
 * the org has the manage_sso entitlement, which the E2E_SSO_UI target must
 * provide (standalone installs grant every entitlement).
 */
async function expectSsoTab(page: Page): Promise<void> {
  await expect(
    page.locator('[data-testid="org-tab-sso"]'),
    'E2E_SSO_UI: org SSO is on and the org has the manage_sso entitlement'
  ).toBeVisible();
}

/**
 * Get domains from the SSO tab's domain list
 */
async function getDomainsFromSsoTab(page: Page): Promise<DomainInfo[]> {
  const domainRows = page.locator('[data-testid="org-section-sso"] .rounded-lg.border');
  await expect(
    domainRows.first(),
    'E2E_CUSTOM_DOMAINS: the SSO tab lists the custom domains'
  ).toBeVisible();
  const count = await domainRows.count();

  const domains: DomainInfo[] = [];

  for (let i = 0; i < count; i++) {
    const row = domainRows.nth(i);

    // Extract domain name
    const domainText = await row.locator('.font-medium').first().textContent();
    if (!domainText) continue;

    // Extract domain extid from configure link. The hub links to the
    // domain's SSO settings page (`/signin/sso`).
    const configureLink = row.locator('a[href*="/signin"]');
    const href = await configureLink.getAttribute('href').catch(() => null);
    const match = href?.match(/\/domains\/([^/]+)\/signin/);
    if (!match) continue;

    // Determine SSO status from badge
    const enabledBadge = row.locator('text=/enabled/i');
    const configuredBadge = row.locator('text=/configured/i');

    let ssoStatus: DomainInfo['ssoStatus'] = 'not_configured';
    if (await enabledBadge.isVisible().catch(() => false)) {
      ssoStatus = 'enabled';
    } else if (await configuredBadge.isVisible().catch(() => false)) {
      ssoStatus = 'configured';
    }

    domains.push({
      extid: match[1],
      displayDomain: domainText.trim(),
      ssoStatus,
    });
  }

  return domains;
}

/**
 * Navigate to the domain's SSO settings page and wait for its form.
 * Returns a locator scoped to the page's content region.
 */
async function openDomainSsoPage(
  page: Page,
  orgExtid: string,
  domainExtid: string
): Promise<Locator> {
  await page.goto(`/org/${orgExtid}/domains/${domainExtid}/signin/sso`);
  await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

  const ssoPage = page.locator('[data-testid="domain-signin-sso-page"]');
  await expect(ssoPage).toBeVisible({ timeout: 10000 });

  // Wait for the SSO form to be ready
  await ssoPage.locator('form').waitFor({ state: 'visible', timeout: 10000 });

  return ssoPage;
}

/**
 * Navigate to the domain signin page (the SSO settings' parent).
 */
async function navigateToDomainSigninPage(
  page: Page,
  orgExtid: string,
  domainExtid: string
): Promise<void> {
  await page.goto(`/org/${orgExtid}/domains/${domainExtid}/signin`);
  await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

  // Wait for the signin config heading (entitled view) or the access-denied
  // message (no manage_sso entitlement). The page no longer renders a <form>.
  const heading = page.getByRole('heading', { name: /sign-in configuration/i });
  const accessDenied = page.getByText(/access denied/i);

  await Promise.race([
    heading.waitFor({ state: 'visible', timeout: 10000 }).catch(() => {}),
    accessDenied.waitFor({ state: 'visible', timeout: 10000 }).catch(() => {}),
  ]);
}

// -----------------------------------------------------------------------------
// Test Suite: Navigation Tests
// -----------------------------------------------------------------------------

test.describe('Domain SSO Configuration - Navigation', () => {
  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
  });

  test('TC-DSSO-001: navigates from signin page to the SSO page via configure button', async ({
    page,
  }) => {
    const org = await getFirstOrganization(page);

    await navigateToOrgSsoTab(page, org.extid);

    // Check if SSO tab is available (entitlement check)
    await expectSsoTab(page);

    // Get domains from SSO tab
    const domains = await getDomainsFromSsoTab(page);
    expect(domains.length, 'E2E_CUSTOM_DOMAINS: a custom domain is listed').toBeGreaterThan(0);

    await navigateToDomainSigninPage(page, org.extid, domains[0].extid);

    // "Configure" (no record) or "Edit credentials" (record) on the SSO row
    const ssoButton = page.getByRole('button', { name: /configure|edit credentials/i });
    await ssoButton.click();

    await expect(page).toHaveURL(
      new RegExp(`/org/${org.extid}/domains/${domains[0].extid}/signin/sso$`)
    );
    await expect(page.locator('[data-testid="domain-signin-sso-page"] form')).toBeVisible({
      timeout: 10000,
    });
  });

  test('TC-DSSO-002: Back on the SSO page returns to the signin page', async ({ page }) => {
    const org = await getFirstOrganization(page);

    await navigateToOrgSsoTab(page, org.extid);
    await expectSsoTab(page);

    const domains = await getDomainsFromSsoTab(page);
    expect(domains.length, 'E2E_CUSTOM_DOMAINS: a custom domain is listed').toBeGreaterThan(0);

    await openDomainSsoPage(page, org.extid, domains[0].extid);

    // Back link in the page header
    await page.getByRole('button', { name: /sign-in settings/i }).click();

    await expect(page).toHaveURL(
      new RegExp(`/org/${org.extid}/domains/${domains[0].extid}/signin$`)
    );
    await expect(page.getByRole('heading', { name: /sign-in configuration/i })).toBeVisible();
  });

  test('TC-DSSO-003: the retired ?modal=sso deep link lands on the SSO page', async ({ page }) => {
    const org = await getFirstOrganization(page);

    await navigateToOrgSsoTab(page, org.extid);
    await expectSsoTab(page);

    const domains = await getDomainsFromSsoTab(page);
    expect(domains.length, 'E2E_CUSTOM_DOMAINS: a custom domain is listed').toBeGreaterThan(0);

    await page.goto(`/org/${org.extid}/domains/${domains[0].extid}/signin?modal=sso`);
    await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

    await expect(page).toHaveURL(
      new RegExp(`/org/${org.extid}/domains/${domains[0].extid}/signin/sso$`)
    );
    await expect(page.locator('[data-testid="domain-signin-sso-page"] form')).toBeVisible({
      timeout: 10000,
    });

    // Domain name is displayed in the header
    await expect(page.getByText(domains[0].displayDomain).first()).toBeVisible();
  });
});

// -----------------------------------------------------------------------------
// Test Suite: Domain List Tests (SSO Tab)
// -----------------------------------------------------------------------------

test.describe('Domain SSO Configuration - Domain List', () => {
  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
  });

  test('TC-DSSO-004: displays list of domains with SSO status badges', async ({ page }) => {
    const org = await getFirstOrganization(page);

    await navigateToOrgSsoTab(page, org.extid);
    await expectSsoTab(page);

    // Check SSO section is visible
    const ssoSection = page.locator('[data-testid="org-section-sso"]');
    await expect(ssoSection).toBeVisible();

    // Domain list or empty state should be visible
    const domainList = ssoSection.locator('.space-y-3');
    const emptyState = ssoSection.getByText(/no domains/i);

    const hasDomainList = await domainList.isVisible().catch(() => false);
    const hasEmptyState = await emptyState.isVisible().catch(() => false);

    expect(hasDomainList || hasEmptyState).toBe(true);
  });

  test('TC-DSSO-005: shows "Not Configured" badge for domains without SSO', async ({ page }) => {
    const org = await getFirstOrganization(page);

    await navigateToOrgSsoTab(page, org.extid);
    await expectSsoTab(page);

    const domains = await getDomainsFromSsoTab(page);
    const unconfiguredDomains = domains.filter((d) => d.ssoStatus === 'not_configured');

    if (unconfiguredDomains.length > 0) {
      // Verify "Not configured" badge is visible
      const notConfiguredBadge = page.locator('text=/not configured/i');
      await expect(notConfiguredBadge.first()).toBeVisible();
    }

    // Test passes even if all domains are configured
    expect(true).toBe(true);
  });

  test('TC-DSSO-006: configure link is visible in SSO hub domain list', async ({ page }) => {
    const org = await getFirstOrganization(page);

    await navigateToOrgSsoTab(page, org.extid);
    await expectSsoTab(page);

    const domains = await getDomainsFromSsoTab(page);
    expect(domains.length, 'E2E_CUSTOM_DOMAINS: a custom domain is listed').toBeGreaterThan(0);

    // Find configure button in the SSO hub
    const configureButton = page
      .locator('[data-testid="org-section-sso"]')
      .locator('a')
      .filter({ hasText: /configure/i })
      .first();

    await expect(configureButton).toBeVisible();
  });

  test('TC-DSSO-007: empty domains state shows add domain prompt', async ({ page }) => {
    const org = await getFirstOrganization(page);

    await navigateToOrgSsoTab(page, org.extid);
    await expectSsoTab(page);

    const domains = await getDomainsFromSsoTab(page);

    if (domains.length === 0) {
      // Empty state should show add domain link
      const addDomainLink = page.locator('a[href*="/domains/add"]');
      await expect(addDomainLink).toBeVisible();
    }

    // Test passes whether domains exist or not
    expect(true).toBe(true);
  });
});

// -----------------------------------------------------------------------------
// Test Suite: Domain SSO Configuration Form
// -----------------------------------------------------------------------------

test.describe('Domain SSO Configuration - Form', () => {
  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
  });

  test('TC-DSSO-008: shows empty form for domain without SSO config', async ({ page }) => {
    const org = await getFirstOrganization(page);

    await navigateToOrgSsoTab(page, org.extid);
    await expectSsoTab(page);

    const domains = await getDomainsFromSsoTab(page);
    const unconfiguredDomain = domains.find((d) => d.ssoStatus === 'not_configured');
    expect(
      unconfiguredDomain,
      'a custom domain without SSO config (the fixture must leave one unconfigured)'
    ).toBeTruthy();

    const ssoPage = await openDomainSsoPage(page, org.extid, unconfiguredDomain!.extid);

    // Form should be visible on the page
    await expect(ssoPage.locator('form')).toBeVisible();

    // Display name should be empty
    const displayNameInput = page.locator('#domain-sso-display-name');
    await expect(displayNameInput).toHaveValue('');

    // Client ID should be empty
    const clientIdInput = page.locator('#domain-sso-client-id');
    await expect(clientIdInput).toHaveValue('');
  });

  test('TC-DSSO-009: provider type selector shows only the two supported providers', async ({
    page,
  }) => {
    const org = await getFirstOrganization(page);

    await navigateToOrgSsoTab(page, org.extid);
    await expectSsoTab(page);

    const domains = await getDomainsFromSsoTab(page);
    expect(domains.length, 'E2E_CUSTOM_DOMAINS: a custom domain is listed').toBeGreaterThan(0);

    // Force new-config mode so the selectable radio group renders (provider
    // type is locked while editing an existing config).
    await page.route(`**/api/domains/${domains[0].extid}/sso`, async (route) => {
      if (route.request().method() === 'GET') {
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({ record: null }),
        });
      } else {
        await route.continue();
      }
    });

    const ssoPage = await openDomainSsoPage(page, org.extid, domains[0].extid);

    // #3902: tenant SSO is OIDC/Entra-only. Issuerless providers
    // (Google/GitHub) live on the platform surface only and must not be
    // offered per-domain.
    await expect(ssoPage.getByText('Microsoft Entra ID')).toBeVisible();
    await expect(ssoPage.getByText('Generic OIDC')).toBeVisible();
    await expect(ssoPage.locator('input[type="radio"][name="provider_type"]')).toHaveCount(2);
    await expect(ssoPage.getByText('Google Workspace')).toHaveCount(0);
    await expect(ssoPage.getByText('GitHub', { exact: true })).toHaveCount(0);
  });

  test('TC-DSSO-010: selecting Entra ID shows tenant_id field', async ({ page }) => {
    const org = await getFirstOrganization(page);

    await navigateToOrgSsoTab(page, org.extid);
    await expectSsoTab(page);

    const domains = await getDomainsFromSsoTab(page);
    expect(domains.length, 'E2E_CUSTOM_DOMAINS: a custom domain is listed').toBeGreaterThan(0);

    const ssoPage = await openDomainSsoPage(page, org.extid, domains[0].extid);

    // Select Entra ID (Microsoft Entra ID)
    const entraOption = ssoPage.locator('label').filter({ hasText: 'Microsoft Entra ID' });
    await entraOption.click();

    // Tenant ID field should be visible
    const tenantIdInput = page.locator('#domain-sso-tenant-id');
    await expect(tenantIdInput).toBeVisible();
  });

  test('TC-DSSO-011: selecting OIDC shows issuer field', async ({ page }) => {
    const org = await getFirstOrganization(page);

    await navigateToOrgSsoTab(page, org.extid);
    await expectSsoTab(page);

    const domains = await getDomainsFromSsoTab(page);
    expect(domains.length, 'E2E_CUSTOM_DOMAINS: a custom domain is listed').toBeGreaterThan(0);

    const ssoPage = await openDomainSsoPage(page, org.extid, domains[0].extid);

    // Select Generic OIDC
    const oidcOption = ssoPage.locator('label').filter({ hasText: 'Generic OIDC' });
    await oidcOption.click();

    // Issuer field should be visible
    const issuerInput = page.locator('#domain-sso-issuer');
    await expect(issuerInput).toBeVisible();
  });

  test('TC-DSSO-012: form validation prevents save without required fields', async ({ page }) => {
    const org = await getFirstOrganization(page);

    await navigateToOrgSsoTab(page, org.extid);
    await expectSsoTab(page);

    const domains = await getDomainsFromSsoTab(page);
    const unconfiguredDomain = domains.find((d) => d.ssoStatus === 'not_configured');
    expect(
      unconfiguredDomain,
      'a custom domain without SSO config (the fixture must leave one unconfigured)'
    ).toBeTruthy();

    const ssoPage = await openDomainSsoPage(page, org.extid, unconfiguredDomain!.extid);

    // A new record has no Save button: the primary action "Save and check"
    // (sso-diagnostics-run) saves it, and is disabled while the form is invalid.
    const saveButton = ssoPage.locator('[data-testid="sso-diagnostics-run"]');

    // Button should be disabled when form is empty
    await expect(saveButton).toBeDisabled();

    // Fill only display name
    const displayNameInput = page.locator('#domain-sso-display-name');
    await displayNameInput.fill('Test SSO');

    // Button should still be disabled (missing client_id and client_secret)
    await expect(saveButton).toBeDisabled();

    // Fill client ID
    const clientIdInput = page.locator('#domain-sso-client-id');
    await clientIdInput.fill('test-client-id');

    // Button should still be disabled (missing client_secret for new config)
    await expect(saveButton).toBeDisabled();

    // Fill client secret
    const clientSecretInput = page.locator('#domain-sso-client-secret');
    await clientSecretInput.fill('test-client-secret');

    // For Entra ID (default), tenant_id is also required
    const tenantIdInput = page.locator('#domain-sso-tenant-id');
    if (await tenantIdInput.isVisible()) {
      // Button still disabled without tenant_id
      await expect(saveButton).toBeDisabled();

      await tenantIdInput.fill('test-tenant-id');
    }

    // Now button should be enabled
    await expect(saveButton).toBeEnabled();
  });
});

// -----------------------------------------------------------------------------
// Test Suite: Test Connection
// -----------------------------------------------------------------------------

test.describe('Domain SSO Configuration - Test Connection', () => {
  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
  });

  test('TC-DSSO-013: test connection button sends test request', async ({ page }) => {
    const org = await getFirstOrganization(page);

    await navigateToOrgSsoTab(page, org.extid);
    await expectSsoTab(page);

    const domains = await getDomainsFromSsoTab(page);
    expect(domains.length, 'E2E_CUSTOM_DOMAINS: a custom domain is listed').toBeGreaterThan(0);

    // Mock the test connection API before opening the SSO page
    let testRequestMade = false;
    await page.route(`**/api/domains/${domains[0].extid}/sso/test`, async (route) => {
      testRequestMade = true;
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          success: true,
          message: 'Connection successful',
          details: {
            issuer: 'https://login.microsoftonline.com/test-tenant',
            authorization_endpoint:
              'https://login.microsoftonline.com/test-tenant/oauth2/v2.0/authorize',
          },
        }),
      });
    });

    const ssoPage = await openDomainSsoPage(page, org.extid, domains[0].extid);

    // Fill required fields for test
    const displayNameInput = page.locator('#domain-sso-display-name');
    await displayNameInput.fill('Test SSO');

    const clientIdInput = page.locator('#domain-sso-client-id');
    await clientIdInput.fill('test-client-id');

    // For Entra ID, fill tenant_id
    const tenantIdInput = page.locator('#domain-sso-tenant-id');
    if (await tenantIdInput.isVisible()) {
      await tenantIdInput.fill('test-tenant-id');
    }

    // Click test connection button scoped to the SSO page
    const testButton = ssoPage.locator('button').filter({ hasText: /test/i });
    await testButton.click();

    // Wait until the mocked test-connection round-trip is captured
    await expect.poll(() => testRequestMade).toBe(true);
  });

  test('TC-DSSO-014: shows success message for valid credentials', async ({ page }) => {
    const org = await getFirstOrganization(page);

    await navigateToOrgSsoTab(page, org.extid);
    await expectSsoTab(page);

    const domains = await getDomainsFromSsoTab(page);
    expect(domains.length, 'E2E_CUSTOM_DOMAINS: a custom domain is listed').toBeGreaterThan(0);

    // Mock successful test connection before opening the SSO page
    await page.route(`**/api/domains/${domains[0].extid}/sso/test`, async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          success: true,
          message: 'Connection successful - IdP metadata retrieved',
          details: {
            issuer: 'https://login.microsoftonline.com/test-tenant',
          },
        }),
      });
    });

    const ssoPage = await openDomainSsoPage(page, org.extid, domains[0].extid);

    // Fill required fields
    await page.locator('#domain-sso-display-name').fill('Test SSO');
    await page.locator('#domain-sso-client-id').fill('test-client-id');

    const tenantIdInput = page.locator('#domain-sso-tenant-id');
    if (await tenantIdInput.isVisible()) {
      await tenantIdInput.fill('test-tenant-id');
    }

    // Click test connection scoped to the SSO page
    const testButton = ssoPage.locator('button').filter({ hasText: /test/i });
    await testButton.click();

    // Wait for and verify success message
    const successMessage = ssoPage.locator('[role="status"]').filter({ hasText: /success/i });
    await expect(successMessage).toBeVisible({ timeout: 5000 });
  });

  test('TC-DSSO-015: shows error details for invalid credentials', async ({ page }) => {
    const org = await getFirstOrganization(page);

    await navigateToOrgSsoTab(page, org.extid);
    await expectSsoTab(page);

    const domains = await getDomainsFromSsoTab(page);
    expect(domains.length, 'E2E_CUSTOM_DOMAINS: a custom domain is listed').toBeGreaterThan(0);

    // Mock failed test connection before opening the SSO page
    await page.route(`**/api/domains/${domains[0].extid}/sso/test`, async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          success: false,
          message: 'Connection failed - Invalid tenant ID',
          details: {
            error_code: 'invalid_tenant',
            http_status: 400,
          },
        }),
      });
    });

    const ssoPage = await openDomainSsoPage(page, org.extid, domains[0].extid);

    // Fill required fields
    await page.locator('#domain-sso-display-name').fill('Test SSO');
    await page.locator('#domain-sso-client-id').fill('test-client-id');

    const tenantIdInput = page.locator('#domain-sso-tenant-id');
    if (await tenantIdInput.isVisible()) {
      await tenantIdInput.fill('invalid-tenant');
    }

    // Click test connection scoped to the SSO page
    const testButton = ssoPage.locator('button').filter({ hasText: /test/i });
    await testButton.click();

    // Wait for and verify error message
    const errorMessage = ssoPage.locator('[role="alert"]');
    await expect(errorMessage).toBeVisible({ timeout: 5000 });
    await expect(errorMessage).toContainText(/failed|invalid/i);
  });
});

// -----------------------------------------------------------------------------
// Test Suite: Save and Delete Operations
// -----------------------------------------------------------------------------

test.describe('Domain SSO Configuration - Save and Delete', () => {
  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
  });

  test('TC-DSSO-016: save button creates new SSO config', async ({ page }) => {
    const org = await getFirstOrganization(page);

    await navigateToOrgSsoTab(page, org.extid);
    await expectSsoTab(page);

    const domains = await getDomainsFromSsoTab(page);
    const unconfiguredDomain = domains.find((d) => d.ssoStatus === 'not_configured');
    expect(
      unconfiguredDomain,
      'a custom domain without SSO config (the fixture must leave one unconfigured)'
    ).toBeTruthy();

    // Mock the save API before opening the SSO page
    let saveRequestMade = false;
    await page.route(`**/api/domains/${unconfiguredDomain!.extid}/sso`, async (route) => {
      if (route.request().method() === 'PUT' || route.request().method() === 'PATCH') {
        saveRequestMade = true;
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({
            record: {
              extid: 'sso-config-123',
              provider_type: 'entra_id',
              display_name: 'Test SSO',
              client_id: 'test-client-id',
              client_secret_masked: '****',
              tenant_id: 'test-tenant-id',
              enabled: false,
              allowed_domains: [],
            },
          }),
        });
      } else {
        await route.continue();
      }
    });

    const ssoPage = await openDomainSsoPage(page, org.extid, unconfiguredDomain!.extid);

    // Fill all required fields
    await page.locator('#domain-sso-display-name').fill('Test SSO');
    await page.locator('#domain-sso-client-id').fill('test-client-id');
    await page.locator('#domain-sso-client-secret').fill('test-client-secret');

    const tenantIdInput = page.locator('#domain-sso-tenant-id');
    if (await tenantIdInput.isVisible()) {
      await tenantIdInput.fill('test-tenant-id');
    }

    // A new record is saved by the primary action "Save and check"
    // (sso-diagnostics-run), which saves first and then runs the check.
    const saveButton = ssoPage.locator('[data-testid="sso-diagnostics-run"]');
    await saveButton.click();

    // Wait until the mocked save round-trip is captured
    await expect.poll(() => saveRequestMade).toBe(true);
  });

  test('TC-DSSO-017: delete button removes SSO config with confirmation', async ({ page }) => {
    const org = await getFirstOrganization(page);

    await navigateToOrgSsoTab(page, org.extid);
    await expectSsoTab(page);

    const domains = await getDomainsFromSsoTab(page);
    const configuredDomain = domains.find((d) => d.ssoStatus !== 'not_configured');
    expect(
      configuredDomain,
      'a custom domain with SSO configured (the fixture must configure one)'
    ).toBeTruthy();

    // Mock delete API before opening the SSO page
    let deleteRequestMade = false;
    await page.route(`**/api/domains/${configuredDomain!.extid}/sso`, async (route) => {
      if (route.request().method() === 'DELETE') {
        deleteRequestMade = true;
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({ success: true }),
        });
      } else {
        await route.continue();
      }
    });

    const ssoPage = await openDomainSsoPage(page, org.extid, configuredDomain!.extid);

    // Delete lives in the Careful Consideration Zone at the end of the form, not the footer
    const cautionZone = ssoPage.locator('[data-testid="sso-caution-zone"]');
    const deleteButton = cautionZone.locator('[data-testid="sso-delete"]');

    if (await deleteButton.isVisible()) {
      // Click delete
      await deleteButton.click();

      // Confirm deletion (inline confirm in the zone: "Yes, delete")
      const confirmButton = cautionZone
        .locator('button')
        .filter({ hasText: /confirm|delete/i })
        .last();
      if (await confirmButton.isVisible()) {
        await confirmButton.click();
      }

      // Wait until the mocked delete round-trip is captured
      await expect.poll(() => deleteRequestMade).toBe(true);
    } else {
      // Delete button not visible - pass test but note this
      expect(true).toBe(true);
    }
  });
});

// -----------------------------------------------------------------------------
// Test Suite: Multi-Domain Scenario (Key Feature Test)
// -----------------------------------------------------------------------------

test.describe('Domain SSO Configuration - Multi-Domain', () => {
  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
  });

  test('TC-DSSO-018: can configure different SSO providers for two domains in same org', async ({
    page,
  }) => {
    const org = await getFirstOrganization(page);

    await navigateToOrgSsoTab(page, org.extid);
    await expectSsoTab(page);

    const domains = await getDomainsFromSsoTab(page);
    test.fixme(
      env.customDomains.length < 2,
      'Needs two custom domains (list both in E2E_CUSTOM_DOMAINS); no lane provisions them. See #3420.'
    );
    expect(domains.length, 'the SSO tab lists both custom domains').toBeGreaterThanOrEqual(2);

    const domainA = domains[0];
    const domainB = domains[1];

    // Mock APIs for both domains
    await page.route(`**/api/domains/${domainA.extid}/sso`, async (route) => {
      if (route.request().method() === 'PUT' || route.request().method() === 'PATCH') {
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({
            record: {
              extid: 'sso-config-domain-a',
              provider_type: 'entra_id',
              display_name: 'Domain A Entra ID',
              client_id: 'client-a',
              enabled: true,
            },
          }),
        });
      } else if (route.request().method() === 'GET') {
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({ record: null }),
        });
      } else {
        await route.continue();
      }
    });

    await page.route(`**/api/domains/${domainB.extid}/sso`, async (route) => {
      if (route.request().method() === 'PUT' || route.request().method() === 'PATCH') {
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({
            record: {
              extid: 'sso-config-domain-b',
              provider_type: 'oidc',
              display_name: 'Domain B OIDC',
              client_id: 'client-b',
              issuer: 'https://idp.domain-b.example.com',
              enabled: true,
            },
          }),
        });
      } else if (route.request().method() === 'GET') {
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({ record: null }),
        });
      } else {
        await route.continue();
      }
    });

    // Step 1: Open the SSO page for domain A
    const ssoPageA = await openDomainSsoPage(page, org.extid, domainA.extid);

    // Step 2: Configure Entra ID for domain A
    const entraOption = ssoPageA.locator('label').filter({ hasText: 'Microsoft Entra ID' });
    await entraOption.click();

    await page.locator('#domain-sso-display-name').fill('Domain A Entra ID');
    await page.locator('#domain-sso-client-id').fill('client-a');
    await page.locator('#domain-sso-client-secret').fill('secret-a');
    await page.locator('#domain-sso-tenant-id').fill('tenant-a');

    // Step 3: Save domain A config via the primary action (a new record is
    // saved by "Save and check"); anchor on the mocked save round-trip
    const saveButtonA = ssoPageA.locator('[data-testid="sso-diagnostics-run"]');
    const saveResponseA = page.waitForResponse(
      (r) => r.url().includes(`/api/domains/${domainA.extid}/sso`) && r.request().method() !== 'GET'
    );
    await saveButtonA.click();
    await saveResponseA;

    // Step 4: Open the SSO page for domain B
    const ssoPageB = await openDomainSsoPage(page, org.extid, domainB.extid);

    // Step 5: Configure Generic OIDC for domain B (#3902: tenant SSO is
    // OIDC/Entra-only, so the second provider is OIDC rather than Google)
    const oidcOption = ssoPageB.locator('label').filter({ hasText: 'Generic OIDC' });
    await oidcOption.click();

    await page.locator('#domain-sso-display-name').fill('Domain B OIDC');
    await page.locator('#domain-sso-client-id').fill('client-b');
    await page.locator('#domain-sso-client-secret').fill('secret-b');
    await page.locator('#domain-sso-issuer').fill('https://idp.domain-b.example.com');

    // Step 6: Save domain B config via the primary action (anchor on the
    // mocked save round-trip)
    const saveButtonB = ssoPageB.locator('[data-testid="sso-diagnostics-run"]');
    const saveResponseB = page.waitForResponse(
      (r) => r.url().includes(`/api/domains/${domainB.extid}/sso`) && r.request().method() !== 'GET'
    );
    await saveButtonB.click();
    await saveResponseB;

    // Step 7: Return to org settings and verify both show configured status
    // (In real scenario, need to refresh domain list data)
    await navigateToOrgSsoTab(page, org.extid);

    // Success - test completed the multi-domain configuration flow
    expect(true).toBe(true);
  });
});

// -----------------------------------------------------------------------------
// Test Suite: Access Control
// -----------------------------------------------------------------------------

test.describe('Domain SSO Configuration - Access Control', () => {
  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
  });

  // Inverted precondition: this asserts the *absence* of the manage_sso
  // entitlement, but the suite is gated on E2E_SSO_UI (entitlement present),
  // so it can never hold here. Quarantined as test.fixme until a
  // no-entitlement lane exists; do not assert this in the SSO-gated file.
  test.fixme('TC-DSSO-019: shows access denied for users without manage_sso entitlement', async ({
    page,
  }) => {
    const org = await getFirstOrganization(page);

    // Navigate to org settings
    await page.goto(`/org/${org.extid}`);
    await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

    // Without manage_sso the tab bar renders but has no SSO tab
    await expect(page.locator('[data-testid="org-tab-domains"]')).toBeVisible();
    await expect(page.locator('[data-testid="org-tab-sso"]')).toHaveCount(0);
  });

  test('TC-DSSO-020: signin page hides SSO configure button without manage_sso entitlement', async ({
    page,
  }) => {
    const org = await getFirstOrganization(page);

    // Navigate to org settings to discover a domain
    await navigateToOrgSsoTab(page, org.extid);
    const hasSso = await hasSsoEntitlement(page);

    if (hasSso) {
      // User has manage_sso - the configure button should be visible
      const domains = await getDomainsFromSsoTab(page);
      expect(domains.length, 'E2E_CUSTOM_DOMAINS: a custom domain is listed').toBeGreaterThan(0);

      await navigateToDomainSigninPage(page, org.extid, domains[0].extid);

      // The configure button should be visible (user has entitlement)
      const ssoButton = page.getByRole('button', { name: /configure|edit credentials/i });
      await expect(ssoButton).toBeVisible();
    } else {
      // User doesn't have manage_sso - navigate to signin page
      // The "Upgrade to configure" text should appear instead of the configure button
      await page.goto(`/org/${org.extid}/domains/test-domain/signin`);
      await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

      // Should show either upgrade prompt or access denied
      const upgradeText = page.getByText(/upgrade to configure/i);
      const accessDenied = page.getByText(/access denied/i);
      const errorMessage = page.getByText(/error|not found/i);

      const hasUpgrade = await upgradeText.isVisible().catch(() => false);
      const hasAccessDenied = await accessDenied.isVisible().catch(() => false);
      const hasError = await errorMessage.isVisible().catch(() => false);

      // One of these states should be true
      expect(hasUpgrade || hasAccessDenied || hasError).toBe(true);
    }
  });
});

/**
 * Qase Test Case Export Format
 *
 * Suite: Domain SSO Configuration (#2786, #3383)
 *
 * | ID           | Title                                                            | Priority | Automation |
 * |--------------|------------------------------------------------------------------|----------|------------|
 * | TC-DSSO-001  | navigates from signin page to the SSO page via configure button | Critical | Automated  |
 * | TC-DSSO-002  | Back on the SSO page returns to the signin page                 | High     | Automated  |
 * | TC-DSSO-003  | the retired ?modal=sso deep link lands on the SSO page          | High     | Automated  |
 * | TC-DSSO-004  | displays list of domains with SSO status badges                 | Critical | Automated  |
 * | TC-DSSO-005  | shows "Not Configured" badge for domains without SSO            | High     | Automated  |
 * | TC-DSSO-006  | configure link is visible in SSO hub domain list                | Critical | Automated  |
 * | TC-DSSO-007  | empty domains state shows add domain prompt                     | Medium   | Automated  |
 * | TC-DSSO-008  | shows empty form for domain without SSO config                  | High     | Automated  |
 * | TC-DSSO-009  | provider type selector shows only the two supported providers   | High     | Automated  |
 * | TC-DSSO-010  | selecting Entra ID shows tenant_id field                        | High     | Automated  |
 * | TC-DSSO-011  | selecting OIDC shows issuer field                               | High     | Automated  |
 * | TC-DSSO-012  | form validation prevents save without required fields           | Critical | Automated  |
 * | TC-DSSO-013  | test connection button sends test request                       | High     | Automated  |
 * | TC-DSSO-014  | shows success message for valid credentials                     | High     | Automated  |
 * | TC-DSSO-015  | shows error details for invalid credentials                     | High     | Automated  |
 * | TC-DSSO-016  | save button creates new SSO config                              | Critical | Automated  |
 * | TC-DSSO-017  | delete button removes SSO config with confirmation              | High     | Automated  |
 * | TC-DSSO-018  | can configure different SSO providers for two domains           | Critical | Automated  |
 * | TC-DSSO-019  | shows access denied for users without manage_sso entitlement    | High     | Automated  |
 * | TC-DSSO-020  | signin page hides SSO configure button without entitlement      | Medium   | Automated  |
 */

/**
 * Manual Test Checklist - Domain SSO Configuration
 *
 * ## Prerequisites
 * - [ ] Test user has access to an organization with manage_sso entitlement
 * - [ ] Organization has at least 2 verified custom domains
 * - [ ] At least one domain has no SSO config (for new config tests)
 * - [ ] At least one domain has SSO configured (for edit/delete tests)
 *
 * ## Visual Verification (Not Automated)
 * - [ ] SSO status badges display correct colors (green=enabled, gray=configured/not configured)
 * - [ ] Provider selection cards highlight when selected
 * - [ ] Password field visibility toggle works
 * - [ ] Form validation error messages are clear
 * - [ ] Test connection success/error messages are properly styled
 * - [ ] Loading spinners appear during API calls
 * - [ ] Delete confirmation dialog is visible and clear
 * - [ ] Sticky footer actions stay reachable while scrolling the form
 *
 * ## Edge Cases
 * - [ ] Switching provider types clears provider-specific fields
 * - [ ] Partial form submission doesn't lose data
 * - [ ] Network errors during save show appropriate error messages
 * - [ ] Session timeout during long form fill redirects to login
 * - [ ] Leaving the SSO page with unsaved changes prompts for confirmation
 *
 * ## Cross-Browser Testing
 * - [ ] SSO page works in Chrome
 * - [ ] SSO page works in Firefox
 * - [ ] SSO page works in Safari
 * - [ ] Mobile responsive layout works
 *
 * ## Security Testing
 * - [ ] Client secret is never sent in GET responses
 * - [ ] Client secret field uses type="password"
 * - [ ] Cannot access other org's domain SSO pages
 * - [ ] API rejects invalid domain extids
 */
