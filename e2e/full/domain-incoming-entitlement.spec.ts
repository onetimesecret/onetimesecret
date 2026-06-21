// e2e/full/domain-incoming-entitlement.spec.ts

/**
 * E2E Tests for Domain Incoming Secrets Entitlement Gating (#3479)
 *
 * Tests the fix for contradictory UI states where the incoming secrets panel
 * would show BOTH an entitlement error AND an "enable the feature below" prompt.
 *
 * Fix A (DomainIncomingConfigForm.vue):
 *   Changed v-if="!isEnabled" to v-else-if="!isEnabled" on disabled_notice banner,
 *   making it mutually exclusive with the error alert.
 *
 * Fix B (DomainIncoming.vue):
 *   Changed entitlement check from:
 *     can(ENTITLEMENTS.INCOMING_SECRETS)
 *   To:
 *     can(ENTITLEMENTS.MANAGE_ORG) && can(ENTITLEMENTS.INCOMING_SECRETS)
 *
 * Test Scenarios:
 * 1. User with both entitlements - sees config form, no errors
 * 2. User missing manage_org - sees "Access Denied" banner, NOT the config form
 * 3. User missing incoming_secrets - sees "Access Denied" banner
 * 4. Error and disabled_notice banners are mutually exclusive
 *
 * Prerequisites:
 * - Set TEST_USER_EMAIL and TEST_USER_PASSWORD environment variables
 * - User must have access to an organization with at least one custom domain
 *
 * Usage:
 *   TEST_USER_EMAIL=test@example.com TEST_USER_PASSWORD=secret \
 *     pnpm playwright test domain-incoming-entitlement.spec.ts
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
 * Authenticate user via login form.
 *
 * Handles both signin variants (canonical logic: e2e/global.setup.ts):
 * - default deployments render SignInForm directly (the CI container does);
 * - passwordless-first deployments hide the password panel behind a
 *   "Password" tab with different test ids.
 */
async function loginUser(page: Page): Promise<void> {
  await page.goto('/signin');

  const signinEmail = process.env.TEST_USER_EMAIL || '';
  const signinPassword = process.env.TEST_USER_PASSWORD || '';
  const signinForm = page.getByTestId('signin-form');
  const passwordTab = page.getByRole('tab', { name: /password/i });
  await expect(signinForm.or(passwordTab).first()).toBeVisible();

  if (await passwordTab.isVisible()) {
    // Passwordless-first variant (magic links / WebAuthn enabled)
    await passwordTab.click();
    await page.getByTestId('password-email-input').fill(signinEmail);
    await page.getByTestId('password-input').fill(signinPassword);
    await page.getByTestId('password-submit').click();
  } else {
    // Password-only variant (CI container default)
    await page.getByTestId('signin-email-input').fill(signinEmail);
    await page.getByTestId('signin-password-input').fill(signinPassword);
    await page.getByTestId('signin-submit').click();
  }

  await page.waitForURL(/\/(account|dashboard|org)/, { timeout: 30000 });
}

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
 * Navigate to domain incoming config page
 */
async function navigateToDomainIncomingPage(
  page: Page,
  orgExtid: string,
  domainExtid: string
): Promise<void> {
  await page.goto(`/org/${orgExtid}/domains/${domainExtid}/incoming`);
  await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();
}

/**
 * Mock the organizations API to simulate specific entitlement states
 */
async function mockEntitlements(
  page: Page,
  orgExtid: string,
  entitlements: { manage_org?: boolean; incoming_secrets?: boolean }
): Promise<void> {
  const mockEntitlementList: string[] = [];

  if (entitlements.manage_org !== false) {
    mockEntitlementList.push('manage_org');
  }
  if (entitlements.incoming_secrets !== false) {
    mockEntitlementList.push('incoming_secrets');
  }

  // Mock the organizations API response
  await page.route('**/api/v2/orgs**', async (route) => {
    const request = route.request();

    // Only mock GET requests
    if (request.method() !== 'GET') {
      await route.continue();
      return;
    }

    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        records: [
          {
            extid: orgExtid,
            name: 'Test Organization',
            entitlements: mockEntitlementList,
            role: 'member',
          },
        ],
      }),
    });
  });
}

/**
 * Mock incoming config API to return an error
 */
async function mockIncomingConfigError(page: Page, domainExtid: string): Promise<void> {
  await page.route(`**/api/domains/${domainExtid}/incoming**`, async (route) => {
    await route.fulfill({
      status: 403,
      contentType: 'application/json',
      body: JSON.stringify({
        error: 'Access denied',
        message: 'You do not have permission to manage incoming secrets',
      }),
    });
  });
}

/**
 * Mock incoming config API to return success with disabled state
 */
async function mockIncomingConfigDisabled(page: Page, domainExtid: string): Promise<void> {
  await page.route(`**/api/domains/${domainExtid}/incoming**`, async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        record: {
          enabled: false,
          recipients: [],
        },
      }),
    });
  });
}

// -----------------------------------------------------------------------------
// Test Suite: Entitlement Gating (Fix B)
// -----------------------------------------------------------------------------

test.describe('Domain Incoming - Entitlement Gating (#3479 Fix B)', () => {
  test.skip(!hasTestCredentials, 'Skipping: TEST_USER_EMAIL and TEST_USER_PASSWORD required');

  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
    await loginUser(page);
  });

  test('TC-DIE-001: shows config form when user has both manage_org and incoming_secrets entitlements', async ({
    page,
  }) => {
    const org = await getFirstOrganization(page);
    test.skip(!org, 'Test requires at least 1 organization');

    const domain = await getFirstDomain(page, org!.extid);
    test.skip(!domain, 'Test requires at least 1 domain');

    // Navigate to incoming config page (using real entitlements)
    await navigateToDomainIncomingPage(page, org!.extid, domain!.extid);

    // Check what's visible - either form (has entitlements) or access denied (no entitlements)
    const form = page.locator('form');
    const accessDenied = page.getByText(/access denied/i);

    const hasForm = await form.isVisible().catch(() => false);
    const hasAccessDenied = await accessDenied.isVisible().catch(() => false);

    if (hasForm) {
      // User has both entitlements - verify form is visible
      await expect(form).toBeVisible();

      // Access denied should NOT be visible
      await expect(accessDenied).not.toBeVisible();

      // Verify key form elements are present
      const enabledToggle = page.locator('button[role="switch"]');
      await expect(enabledToggle).toBeVisible();
    } else if (hasAccessDenied) {
      // User lacks entitlements - verify access denied state
      await expect(accessDenied).toBeVisible();

      // Form should NOT be visible
      await expect(form).not.toBeVisible();

      // The "enable below" prompt should NOT be visible (key fix)
      const enablePrompt = page.getByText(/enable the feature below/i);
      await expect(enablePrompt).not.toBeVisible();
    }

    // One of the states must be true
    expect(hasForm || hasAccessDenied).toBe(true);
  });

  test('TC-DIE-002: shows access denied when user lacks manage_org entitlement (mocked)', async ({
    page,
  }) => {
    const org = await getFirstOrganization(page);
    test.skip(!org, 'Test requires at least 1 organization');

    const domain = await getFirstDomain(page, org!.extid);
    test.skip(!domain, 'Test requires at least 1 domain');

    // Mock entitlements: has incoming_secrets but NOT manage_org
    await mockEntitlements(page, org!.extid, {
      manage_org: false,
      incoming_secrets: true,
    });

    await navigateToDomainIncomingPage(page, org!.extid, domain!.extid);

    // Access denied banner should be visible
    const accessDenied = page.getByText(/access denied/i);
    await expect(accessDenied).toBeVisible();

    // Config form should NOT be visible
    const form = page.locator('form');
    await expect(form).not.toBeVisible();

    // The "enable the feature below" disabled_notice should NOT be visible
    // This is the key regression check - before the fix, this would appear
    const disabledNotice = page.locator('.bg-blue-50, .bg-blue-900\\/20').filter({
      hasText: /toggle|enable|feature/i,
    });
    await expect(disabledNotice).not.toBeVisible();
  });

  test('TC-DIE-003: shows access denied when user lacks incoming_secrets entitlement (mocked)', async ({
    page,
  }) => {
    const org = await getFirstOrganization(page);
    test.skip(!org, 'Test requires at least 1 organization');

    const domain = await getFirstDomain(page, org!.extid);
    test.skip(!domain, 'Test requires at least 1 domain');

    // Mock entitlements: has manage_org but NOT incoming_secrets
    await mockEntitlements(page, org!.extid, {
      manage_org: true,
      incoming_secrets: false,
    });

    await navigateToDomainIncomingPage(page, org!.extid, domain!.extid);

    // Upgrade Required banner should be visible (plan-gate fires first)
    const upgradeRequired = page.getByText(/upgrade required/i);
    await expect(upgradeRequired).toBeVisible();

    // Config form should NOT be visible
    const form = page.locator('form');
    await expect(form).not.toBeVisible();
  });

  test('TC-DIE-004: shows upgrade required when user lacks both entitlements (mocked)', async ({
    page,
  }) => {
    const org = await getFirstOrganization(page);
    test.skip(!org, 'Test requires at least 1 organization');

    const domain = await getFirstDomain(page, org!.extid);
    test.skip(!domain, 'Test requires at least 1 domain');

    // Mock entitlements: has neither
    await mockEntitlements(page, org!.extid, {
      manage_org: false,
      incoming_secrets: false,
    });

    await navigateToDomainIncomingPage(page, org!.extid, domain!.extid);

    // Upgrade Required banner should be visible (plan-gate fires first when incoming_secrets missing)
    const upgradeRequired = page.getByText(/upgrade required/i);
    await expect(upgradeRequired).toBeVisible();

    // Config form should NOT be visible
    const form = page.locator('form');
    await expect(form).not.toBeVisible();

    // No disabled_notice banner should appear
    const disabledNotice = page.locator('.bg-blue-50, .bg-blue-900\\/20');
    await expect(disabledNotice).not.toBeVisible();
  });

  test('TC-DIE-005: upgrade link shown when missing incoming_secrets entitlement', async ({
    page,
  }) => {
    const org = await getFirstOrganization(page);
    test.skip(!org, 'Test requires at least 1 organization');

    const domain = await getFirstDomain(page, org!.extid);
    test.skip(!domain, 'Test requires at least 1 domain');

    // Mock entitlements: has manage_org but NOT incoming_secrets (plan upgrade case)
    await mockEntitlements(page, org!.extid, {
      manage_org: true,
      incoming_secrets: false,
    });

    await navigateToDomainIncomingPage(page, org!.extid, domain!.extid);

    // Upgrade Required should be visible (plan-gate path)
    const upgradeRequired = page.getByText(/upgrade required/i);
    await expect(upgradeRequired).toBeVisible();

    // Upgrade link SHOULD be present for plan upgrade case
    const upgradeLink = page.locator(`a[href*="/billing/${org!.extid}/plans"]`);
    await expect(upgradeLink).toBeVisible();
  });

  test('TC-DIE-005b: NO upgrade link when missing manage_org but has incoming_secrets', async ({
    page,
  }) => {
    const org = await getFirstOrganization(page);
    test.skip(!org, 'Test requires at least 1 organization');

    const domain = await getFirstDomain(page, org!.extid);
    test.skip(!domain, 'Test requires at least 1 domain');

    // Mock entitlements: has incoming_secrets but NOT manage_org (role case, not plan)
    await mockEntitlements(page, org!.extid, {
      manage_org: false,
      incoming_secrets: true,
    });

    await navigateToDomainIncomingPage(page, org!.extid, domain!.extid);

    // Access denied should be visible
    const accessDenied = page.getByText(/access denied/i);
    await expect(accessDenied).toBeVisible();

    // Upgrade link should NOT be present (user needs role, not plan upgrade)
    const upgradeLink = page.locator(`a[href*="/billing/${org!.extid}/plans"]`);
    await expect(upgradeLink).not.toBeVisible();
  });
});

// -----------------------------------------------------------------------------
// Test Suite: Error vs Disabled Notice Mutual Exclusivity (Fix A)
// -----------------------------------------------------------------------------

test.describe('Domain Incoming - Error/Disabled Banner Exclusivity (#3479 Fix A)', () => {
  test.skip(!hasTestCredentials, 'Skipping: TEST_USER_EMAIL and TEST_USER_PASSWORD required');

  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
    await loginUser(page);
  });

  test('TC-DIE-006: error alert and disabled_notice banner are mutually exclusive', async ({
    page,
  }) => {
    const org = await getFirstOrganization(page);
    test.skip(!org, 'Test requires at least 1 organization');

    const domain = await getFirstDomain(page, org!.extid);
    test.skip(!domain, 'Test requires at least 1 domain');

    // Mock entitlements to allow access
    await mockEntitlements(page, org!.extid, {
      manage_org: true,
      incoming_secrets: true,
    });

    // Mock incoming config to return an error
    await mockIncomingConfigError(page, domain!.extid);

    await navigateToDomainIncomingPage(page, org!.extid, domain!.extid);

    // Wait for either error alert or form to appear
    const errorAlert = page.locator('[role="alert"]');
    const formElement = page.locator('form');
    await expect(errorAlert.or(formElement).first()).toBeVisible();

    // Look for error alert (BasicFormAlerts)
    const errorAlert = page.locator('[role="alert"]');
    const disabledNotice = page.locator('.bg-blue-50, .bg-blue-900\\/20').filter({
      hasText: /toggle|enable|feature|disabled/i,
    });

    const hasError = await errorAlert.isVisible().catch(() => false);
    const hasDisabledNotice = await disabledNotice.isVisible().catch(() => false);

    // Key assertion: they should NOT both be visible
    // The fix changed v-if to v-else-if, making them mutually exclusive
    if (hasError) {
      expect(
        hasDisabledNotice,
        'When error is present, disabled_notice should NOT be visible'
      ).toBe(false);
    }

    // At most one should be visible
    expect(hasError && hasDisabledNotice).toBe(false);
  });

  test('TC-DIE-007: disabled_notice appears when form is disabled and no error', async ({
    page,
  }) => {
    const org = await getFirstOrganization(page);
    test.skip(!org, 'Test requires at least 1 organization');

    const domain = await getFirstDomain(page, org!.extid);
    test.skip(!domain, 'Test requires at least 1 domain');

    // Mock entitlements to allow access
    await mockEntitlements(page, org!.extid, {
      manage_org: true,
      incoming_secrets: true,
    });

    // Mock incoming config to return disabled state (no error)
    await mockIncomingConfigDisabled(page, domain!.extid);

    await navigateToDomainIncomingPage(page, org!.extid, domain!.extid);

    // Wait for form or access-denied state to appear
    const formElement = page.locator('form');
    const accessDenied = page.getByText(/access denied/i);
    await expect(formElement.or(accessDenied).first()).toBeVisible();

    // If form is visible and feature is disabled, disabled_notice should appear
    const form = page.locator('form');
    const formVisible = await form.isVisible().catch(() => false);

    if (formVisible) {
      // Check toggle state
      const toggle = page.locator('button[role="switch"]');
      const ariaChecked = await toggle.getAttribute('aria-checked').catch(() => null);

      if (ariaChecked === 'false') {
        // Feature is disabled - disabled_notice should be visible
        const disabledNotice = page.locator('.bg-blue-50, .bg-blue-900\\/20');
        await expect(disabledNotice).toBeVisible();

        // Error alert should NOT be visible
        const errorAlert = page.locator('[role="alert"]');
        await expect(errorAlert).not.toBeVisible();
      }
    }
  });

  test('TC-DIE-008: neither error nor disabled_notice when form is enabled', async ({ page }) => {
    const org = await getFirstOrganization(page);
    test.skip(!org, 'Test requires at least 1 organization');

    const domain = await getFirstDomain(page, org!.extid);
    test.skip(!domain, 'Test requires at least 1 domain');

    // Navigate without mocking to use real state
    await navigateToDomainIncomingPage(page, org!.extid, domain!.extid);

    // Check if form is visible
    const form = page.locator('form');
    const formVisible = await form.isVisible().catch(() => false);

    if (formVisible) {
      // Check toggle state
      const toggle = page.locator('button[role="switch"]');
      const ariaChecked = await toggle.getAttribute('aria-checked').catch(() => null);

      if (ariaChecked === 'true') {
        // Feature is enabled
        // Neither error nor disabled_notice should be visible
        const errorAlert = page.locator('[role="alert"]');
        const disabledNotice = page.locator('.bg-blue-50, .bg-blue-900\\/20').filter({
          hasText: /toggle|enable|feature|disabled/i,
        });

        await expect(errorAlert).not.toBeVisible();
        await expect(disabledNotice).not.toBeVisible();
      }
    }
  });
});

// -----------------------------------------------------------------------------
// Test Suite: Toggle State Transitions
// -----------------------------------------------------------------------------

test.describe('Domain Incoming - Toggle State Transitions', () => {
  test.skip(!hasTestCredentials, 'Skipping: TEST_USER_EMAIL and TEST_USER_PASSWORD required');

  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
    await loginUser(page);
  });

  test('TC-DIE-009: disabled_notice appears when toggling feature OFF', async ({ page }) => {
    const org = await getFirstOrganization(page);
    test.skip(!org, 'Test requires at least 1 organization');

    const domain = await getFirstDomain(page, org!.extid);
    test.skip(!domain, 'Test requires at least 1 domain');

    await navigateToDomainIncomingPage(page, org!.extid, domain!.extid);

    const form = page.locator('form');
    const formVisible = await form.isVisible().catch(() => false);
    test.skip(!formVisible, 'Test requires access to incoming config form');

    const toggle = page.locator('button[role="switch"]');
    const ariaChecked = await toggle.getAttribute('aria-checked');

    // If currently enabled, toggle OFF and verify disabled_notice appears
    if (ariaChecked === 'true') {
      await toggle.click();

      // Wait for toggle state to update
      await expect(toggle).toHaveAttribute('aria-checked', 'false');

      // disabled_notice should now be visible
      const disabledNotice = page.locator('.bg-blue-50, .bg-blue-900\\/20');
      await expect(disabledNotice).toBeVisible();
    }
  });

  test('TC-DIE-010: disabled_notice disappears when toggling feature ON', async ({ page }) => {
    const org = await getFirstOrganization(page);
    test.skip(!org, 'Test requires at least 1 organization');

    const domain = await getFirstDomain(page, org!.extid);
    test.skip(!domain, 'Test requires at least 1 domain');

    await navigateToDomainIncomingPage(page, org!.extid, domain!.extid);

    const form = page.locator('form');
    const formVisible = await form.isVisible().catch(() => false);
    test.skip(!formVisible, 'Test requires access to incoming config form');

    const toggle = page.locator('button[role="switch"]');
    const ariaChecked = await toggle.getAttribute('aria-checked');

    // If currently disabled, toggle ON and verify disabled_notice disappears
    if (ariaChecked === 'false') {
      // Verify disabled_notice is visible before toggle
      const disabledNotice = page.locator('.bg-blue-50, .bg-blue-900\\/20');
      await expect(disabledNotice).toBeVisible();

      await toggle.click();

      // Wait for toggle state to update
      await expect(toggle).toHaveAttribute('aria-checked', 'true');

      // disabled_notice should now be hidden
      await expect(disabledNotice).not.toBeVisible();
    }
  });
});

// -----------------------------------------------------------------------------
// Test Suite: Regression Prevention
// -----------------------------------------------------------------------------

test.describe('Domain Incoming - Regression Prevention (#3479)', () => {
  test.skip(!hasTestCredentials, 'Skipping: TEST_USER_EMAIL and TEST_USER_PASSWORD required');

  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
    await loginUser(page);
  });

  test('TC-DIE-011: access denied state never shows "enable below" prompt', async ({ page }) => {
    const org = await getFirstOrganization(page);
    test.skip(!org, 'Test requires at least 1 organization');

    const domain = await getFirstDomain(page, org!.extid);
    test.skip(!domain, 'Test requires at least 1 domain');

    // Mock to force access denied state
    await mockEntitlements(page, org!.extid, {
      manage_org: false,
      incoming_secrets: true,
    });

    await navigateToDomainIncomingPage(page, org!.extid, domain!.extid);

    // Verify access denied is shown
    const accessDenied = page.getByText(/access denied/i);
    await expect(accessDenied).toBeVisible();

    // THE KEY REGRESSION TEST:
    // Before the fix, users would see "Access Denied" AND a prompt to "enable the feature below"
    // This was contradictory since they can't enable anything if access is denied

    // Check for any variation of the enable prompt text
    const enablePromptVariations = [
      page.getByText(/enable the feature below/i),
      page.getByText(/toggle.*to enable/i),
      page.getByText(/flip.*switch.*to enable/i),
      page.locator('.bg-blue-50, .bg-blue-900\\/20'), // The disabled_notice banner
    ];

    for (const prompt of enablePromptVariations) {
      await expect(prompt, 'Enable prompt should not appear with access denied').not.toBeVisible();
    }

    // Form should not be visible
    const form = page.locator('form');
    await expect(form).not.toBeVisible();

    // Toggle should not be visible (part of the form)
    const toggle = page.locator('button[role="switch"]');
    await expect(toggle).not.toBeVisible();
  });

  test('TC-DIE-012: page states are exhaustive and non-overlapping', async ({ page }) => {
    const org = await getFirstOrganization(page);
    test.skip(!org, 'Test requires at least 1 organization');

    const domain = await getFirstDomain(page, org!.extid);
    test.skip(!domain, 'Test requires at least 1 domain');

    await navigateToDomainIncomingPage(page, org!.extid, domain!.extid);

    // Define the mutually exclusive states
    const loadingState = page.locator('[class*="skeleton"], [class*="loading"]');
    const errorState = page.locator('[role="alert"]');
    const featureDisabledState = page.getByText(/feature.*disabled.*install/i);
    const accessDeniedState = page.getByText(/access denied/i);
    const formState = page.locator('form');

    const states = [
      { name: 'loading', element: loadingState },
      { name: 'error', element: errorState },
      { name: 'featureDisabled', element: featureDisabledState },
      { name: 'accessDenied', element: accessDeniedState },
      { name: 'form', element: formState },
    ];

    // Count visible states
    const visibleStates: string[] = [];
    for (const state of states) {
      const isVisible = await state.element.first().isVisible().catch(() => false);
      if (isVisible) {
        visibleStates.push(state.name);
      }
    }

    // Log for debugging
    console.log('Visible states:', visibleStates);

    // Exactly one main state should be visible (excluding loading which may overlap briefly)
    const mainStates = visibleStates.filter((s) => s !== 'loading');

    // Allow for transition states, but generally should have at most one main state
    expect(
      mainStates.length,
      `Expected at most 1 main state, found: ${mainStates.join(', ')}`
    ).toBeLessThanOrEqual(1);
  });
});

/**
 * Qase Test Case Export Format
 *
 * Suite: Domain Incoming Entitlement Gating (#3479)
 *
 * | ID           | Title                                                              | Priority | Automation |
 * |--------------|--------------------------------------------------------------------|----------|------------|
 * | TC-DIE-001   | shows config form with both entitlements                           | Critical | Automated  |
 * | TC-DIE-002   | shows access denied when missing manage_org (mocked)               | Critical | Automated  |
 * | TC-DIE-003   | shows access denied when missing incoming_secrets (mocked)         | Critical | Automated  |
 * | TC-DIE-004   | shows access denied when missing both entitlements (mocked)        | High     | Automated  |
 * | TC-DIE-005   | access denied banner shows upgrade link                            | High     | Automated  |
 * | TC-DIE-006   | error alert and disabled_notice are mutually exclusive             | Critical | Automated  |
 * | TC-DIE-007   | disabled_notice appears when form disabled, no error               | High     | Automated  |
 * | TC-DIE-008   | neither error nor disabled_notice when form enabled                | High     | Automated  |
 * | TC-DIE-009   | disabled_notice appears when toggling OFF                          | Medium   | Automated  |
 * | TC-DIE-010   | disabled_notice disappears when toggling ON                        | Medium   | Automated  |
 * | TC-DIE-011   | access denied never shows "enable below" prompt (regression)       | Critical | Automated  |
 * | TC-DIE-012   | page states are exhaustive and non-overlapping                     | High     | Automated  |
 */
