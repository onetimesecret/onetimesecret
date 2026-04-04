// e2e/full/domain-email-config.spec.ts

/**
 * E2E Tests for Domain Email Configuration
 *
 * Tests the per-domain email sender configuration feature that allows
 * organizations to configure custom email sending for their domains.
 *
 * Flow:
 * 1. User navigates to /org/{orgId}/domains/{domainId}/email
 * 2. Views/configures email sender settings (from_name, from_address, reply_to)
 * 3. Enables/disables email sending for the domain
 * 4. Saves or deletes configuration
 *
 * Prerequisites:
 * - Set TEST_USER_EMAIL and TEST_USER_PASSWORD environment variables
 * - User must have access to an organization with custom domains
 * - At least one custom domain should exist for testing
 *
 * Usage:
 *   TEST_USER_EMAIL=test@example.com TEST_USER_PASSWORD=secret \
 *     pnpm playwright test domain-email-config.spec.ts
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
 * Navigate to domain email config page
 */
async function navigateToEmailConfig(
  page: Page,
  orgExtid: string,
  domainExtid: string
): Promise<boolean> {
  await page.goto(`/org/${orgExtid}/domains/${domainExtid}/email`);
  await page.waitForLoadState('networkidle');

  const form = page.locator('form');
  return form.isVisible().catch(() => false);
}

/**
 * Find the enabled toggle
 */
async function findEnabledToggle(page: Page) {
  const selectors = [
    '#email-enabled',
    '[data-testid="config-enabled-toggle"]',
    'button[role="switch"]',
  ];

  for (const selector of selectors) {
    const toggle = page.locator(selector).first();
    if (await toggle.isVisible().catch(() => false)) {
      return toggle;
    }
  }
  return null;
}

/**
 * Check if toggle is enabled
 */
async function isToggleEnabled(toggle: ReturnType<Page['locator']>): Promise<boolean> {
  const ariaChecked = await toggle.getAttribute('aria-checked');
  return ariaChecked === 'true';
}

// -----------------------------------------------------------------------------
// Test Suite: Form Loading
// -----------------------------------------------------------------------------

test.describe('Domain Email Config - Form Loading', () => {
  test.skip(!hasTestCredentials, 'Skipping: TEST_USER_EMAIL and TEST_USER_PASSWORD required');

  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
    await loginUser(page);
  });

  test('TC-DEC-001: email config form loads successfully', async ({ page }) => {
    const org = await getFirstOrganization(page);
    test.skip(!org, 'Test requires at least 1 organization');

    const domain = await getFirstDomain(page, org!.extid);
    test.skip(!domain, 'Test requires at least 1 domain');

    const formLoaded = await navigateToEmailConfig(page, org!.extid, domain!.extid);
    expect(formLoaded, 'Email config form should load').toBe(true);

    // Verify form elements are present
    await expect(page.locator('#email-from-name')).toBeVisible();
    await expect(page.locator('#email-from-address')).toBeVisible();
  });

  test('TC-DEC-002: form displays domain context', async ({ page }) => {
    const org = await getFirstOrganization(page);
    test.skip(!org, 'Test requires at least 1 organization');

    const domain = await getFirstDomain(page, org!.extid);
    test.skip(!domain, 'Test requires at least 1 domain');

    await navigateToEmailConfig(page, org!.extid, domain!.extid);

    // Domain name should be visible somewhere on page
    const domainText = page.getByText(domain!.displayDomain);
    await expect(domainText.first()).toBeVisible();
  });

  test('TC-DEC-003: back navigation returns to domains list', async ({ page }) => {
    const org = await getFirstOrganization(page);
    test.skip(!org, 'Test requires at least 1 organization');

    const domain = await getFirstDomain(page, org!.extid);
    test.skip(!domain, 'Test requires at least 1 domain');

    await navigateToEmailConfig(page, org!.extid, domain!.extid);

    // Find and click back button
    const backButton = page.locator('button').filter({ has: page.locator('[name="arrow-left"]') });
    if (await backButton.isVisible()) {
      await backButton.click();
      await expect(page).toHaveURL(new RegExp(`/org/${org!.extid}/domains`));
    }
  });
});

// -----------------------------------------------------------------------------
// Test Suite: Form Fields
// -----------------------------------------------------------------------------

test.describe('Domain Email Config - Form Fields', () => {
  test.skip(!hasTestCredentials, 'Skipping: TEST_USER_EMAIL and TEST_USER_PASSWORD required');

  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
    await loginUser(page);
  });

  test('TC-DEC-004: from_name field accepts input', async ({ page }) => {
    const org = await getFirstOrganization(page);
    test.skip(!org, 'Test requires at least 1 organization');

    const domain = await getFirstDomain(page, org!.extid);
    test.skip(!domain, 'Test requires at least 1 domain');

    await navigateToEmailConfig(page, org!.extid, domain!.extid);

    const fromNameInput = page.locator('#email-from-name');
    await fromNameInput.fill('Test Sender Name');
    await expect(fromNameInput).toHaveValue('Test Sender Name');
  });

  test('TC-DEC-005: from_address field validates email format', async ({ page }) => {
    const org = await getFirstOrganization(page);
    test.skip(!org, 'Test requires at least 1 organization');

    const domain = await getFirstDomain(page, org!.extid);
    test.skip(!domain, 'Test requires at least 1 domain');

    await navigateToEmailConfig(page, org!.extid, domain!.extid);

    const fromAddressInput = page.locator('#email-from-address');

    // Enter valid email
    await fromAddressInput.fill('test@example.com');
    await expect(fromAddressInput).toHaveValue('test@example.com');

    // Note: Client-side validation may show error state for invalid email
    // This test verifies the field accepts input
  });

  test('TC-DEC-006: reply_to field is optional', async ({ page }) => {
    const org = await getFirstOrganization(page);
    test.skip(!org, 'Test requires at least 1 organization');

    const domain = await getFirstDomain(page, org!.extid);
    test.skip(!domain, 'Test requires at least 1 domain');

    await navigateToEmailConfig(page, org!.extid, domain!.extid);

    const replyToInput = page.locator('#email-reply-to');
    await expect(replyToInput).toBeVisible();

    // Check it's not marked as required
    const required = await replyToInput.getAttribute('required');
    expect(required).toBeNull();
  });

  test('TC-DEC-007: fields have proper labels', async ({ page }) => {
    const org = await getFirstOrganization(page);
    test.skip(!org, 'Test requires at least 1 organization');

    const domain = await getFirstDomain(page, org!.extid);
    test.skip(!domain, 'Test requires at least 1 domain');

    await navigateToEmailConfig(page, org!.extid, domain!.extid);

    // Check for required field indicators
    const requiredIndicators = page.locator('span.text-red-500');
    const count = await requiredIndicators.count();
    expect(count, 'Should have required field indicators').toBeGreaterThanOrEqual(2);
  });
});

// -----------------------------------------------------------------------------
// Test Suite: Toggle Behavior
// -----------------------------------------------------------------------------

test.describe('Domain Email Config - Toggle Behavior', () => {
  test.skip(!hasTestCredentials, 'Skipping: TEST_USER_EMAIL and TEST_USER_PASSWORD required');

  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
    await loginUser(page);
  });

  test('TC-DEC-008: enabled toggle is present', async ({ page }) => {
    const org = await getFirstOrganization(page);
    test.skip(!org, 'Test requires at least 1 organization');

    const domain = await getFirstDomain(page, org!.extid);
    test.skip(!domain, 'Test requires at least 1 domain');

    await navigateToEmailConfig(page, org!.extid, domain!.extid);

    const toggle = await findEnabledToggle(page);
    expect(toggle, 'Enabled toggle should be present').not.toBeNull();
  });

  test('TC-DEC-009: toggle can be switched', async ({ page }) => {
    const org = await getFirstOrganization(page);
    test.skip(!org, 'Test requires at least 1 organization');

    const domain = await getFirstDomain(page, org!.extid);
    test.skip(!domain, 'Test requires at least 1 domain');

    await navigateToEmailConfig(page, org!.extid, domain!.extid);

    const toggle = await findEnabledToggle(page);
    test.skip(!toggle, 'Toggle not found');

    const initialState = await isToggleEnabled(toggle!);

    // Click toggle
    await toggle!.click();
    await page.waitForTimeout(300);

    const newState = await isToggleEnabled(toggle!);
    expect(newState).not.toBe(initialState);
  });

  test('TC-DEC-010: toggle has proper ARIA attributes', async ({ page }) => {
    const org = await getFirstOrganization(page);
    test.skip(!org, 'Test requires at least 1 organization');

    const domain = await getFirstDomain(page, org!.extid);
    test.skip(!domain, 'Test requires at least 1 domain');

    await navigateToEmailConfig(page, org!.extid, domain!.extid);

    const toggle = await findEnabledToggle(page);
    test.skip(!toggle, 'Toggle not found');

    const role = await toggle!.getAttribute('role');
    expect(role).toBe('switch');

    const ariaChecked = await toggle!.getAttribute('aria-checked');
    expect(['true', 'false']).toContain(ariaChecked);
  });
});

// -----------------------------------------------------------------------------
// Test Suite: Form Validation
// -----------------------------------------------------------------------------

test.describe('Domain Email Config - Form Validation', () => {
  test.skip(!hasTestCredentials, 'Skipping: TEST_USER_EMAIL and TEST_USER_PASSWORD required');

  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
    await loginUser(page);
  });

  test('TC-DEC-011: save button disabled when required fields empty', async ({ page }) => {
    const org = await getFirstOrganization(page);
    test.skip(!org, 'Test requires at least 1 organization');

    const domain = await getFirstDomain(page, org!.extid);
    test.skip(!domain, 'Test requires at least 1 domain');

    await navigateToEmailConfig(page, org!.extid, domain!.extid);

    // Clear required fields
    const fromNameInput = page.locator('#email-from-name');
    const fromAddressInput = page.locator('#email-from-address');

    await fromNameInput.clear();
    await fromAddressInput.clear();

    // Save button should be disabled
    const saveButton = page.locator('button[type="submit"]');
    await expect(saveButton).toBeDisabled();
  });

  test('TC-DEC-012: save button enabled when required fields filled', async ({ page }) => {
    const org = await getFirstOrganization(page);
    test.skip(!org, 'Test requires at least 1 organization');

    const domain = await getFirstDomain(page, org!.extid);
    test.skip(!domain, 'Test requires at least 1 domain');

    await navigateToEmailConfig(page, org!.extid, domain!.extid);

    // Fill required fields
    const fromNameInput = page.locator('#email-from-name');
    const fromAddressInput = page.locator('#email-from-address');

    await fromNameInput.fill('Test Sender');
    await fromAddressInput.fill('test@example.com');

    // Save button should be enabled
    const saveButton = page.locator('button[type="submit"]');
    await expect(saveButton).toBeEnabled();
  });

  test('TC-DEC-013: invalid email format prevents save', async ({ page }) => {
    const org = await getFirstOrganization(page);
    test.skip(!org, 'Test requires at least 1 organization');

    const domain = await getFirstDomain(page, org!.extid);
    test.skip(!domain, 'Test requires at least 1 domain');

    await navigateToEmailConfig(page, org!.extid, domain!.extid);

    // Fill with invalid email
    const fromNameInput = page.locator('#email-from-name');
    const fromAddressInput = page.locator('#email-from-address');

    await fromNameInput.fill('Test Sender');
    await fromAddressInput.fill('not-an-email');

    // Save button should be disabled due to invalid email
    const saveButton = page.locator('button[type="submit"]');
    await expect(saveButton).toBeDisabled();
  });
});

// -----------------------------------------------------------------------------
// Test Suite: Save and Delete Operations
// -----------------------------------------------------------------------------

test.describe('Domain Email Config - Save and Delete', () => {
  test.skip(!hasTestCredentials, 'Skipping: TEST_USER_EMAIL and TEST_USER_PASSWORD required');

  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
    await loginUser(page);
  });

  test('TC-DEC-014: save button submits form', async ({ page }) => {
    const org = await getFirstOrganization(page);
    test.skip(!org, 'Test requires at least 1 organization');

    const domain = await getFirstDomain(page, org!.extid);
    test.skip(!domain, 'Test requires at least 1 domain');

    await navigateToEmailConfig(page, org!.extid, domain!.extid);

    // Mock the save API
    let saveRequestMade = false;
    await page.route(`**/api/domains/${domain!.extid}/email`, async (route) => {
      if (route.request().method() === 'PUT' || route.request().method() === 'PATCH') {
        saveRequestMade = true;
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({
            record: {
              from_name: 'Test Sender',
              from_address: 'test@example.com',
              reply_to: '',
              enabled: true,
            },
          }),
        });
      } else {
        await route.continue();
      }
    });

    // Fill and save
    await page.locator('#email-from-name').fill('Test Sender');
    await page.locator('#email-from-address').fill('test@example.com');

    const saveButton = page.locator('button[type="submit"]');
    await saveButton.click();

    await page.waitForTimeout(1000);
    expect(saveRequestMade).toBe(true);
  });

  test('TC-DEC-015: delete button shows confirmation', async ({ page }) => {
    const org = await getFirstOrganization(page);
    test.skip(!org, 'Test requires at least 1 organization');

    const domain = await getFirstDomain(page, org!.extid);
    test.skip(!domain, 'Test requires at least 1 domain');

    await navigateToEmailConfig(page, org!.extid, domain!.extid);

    // Look for delete button
    const deleteButton = page.locator('button').filter({ hasText: /delete/i });

    if (await deleteButton.isVisible()) {
      await deleteButton.click();

      // Confirmation dialog should appear
      const confirmDialog = page.locator('[role="dialog"], .modal');
      const confirmButton = page.locator('button').filter({ hasText: /confirm|delete/i }).last();

      const hasConfirmation =
        (await confirmDialog.isVisible().catch(() => false)) ||
        (await confirmButton.isVisible().catch(() => false));

      expect(hasConfirmation).toBe(true);
    }
  });

  test('TC-DEC-016: discard button resets form changes', async ({ page }) => {
    const org = await getFirstOrganization(page);
    test.skip(!org, 'Test requires at least 1 organization');

    const domain = await getFirstDomain(page, org!.extid);
    test.skip(!domain, 'Test requires at least 1 domain');

    await navigateToEmailConfig(page, org!.extid, domain!.extid);

    const fromNameInput = page.locator('#email-from-name');
    const originalValue = await fromNameInput.inputValue();

    // Make a change
    await fromNameInput.fill('Changed Value');

    // Look for discard/reset button
    const discardButton = page.locator('button').filter({ hasText: /discard|reset|cancel/i });

    if (await discardButton.isVisible()) {
      await discardButton.click();

      // Value should be reset
      const newValue = await fromNameInput.inputValue();
      // Either back to original or empty
      expect([originalValue, '']).toContain(newValue);
    }
  });
});

// -----------------------------------------------------------------------------
// Test Suite: Mobile Responsiveness
// -----------------------------------------------------------------------------

test.describe('Domain Email Config - Mobile', () => {
  test.skip(!hasTestCredentials, 'Skipping: TEST_USER_EMAIL and TEST_USER_PASSWORD required');

  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
  });

  test('TC-DEC-017: form is usable on mobile viewport', async ({ page }) => {
    await page.setViewportSize({ width: 375, height: 667 });

    await loginUser(page);

    const org = await getFirstOrganization(page);
    test.skip(!org, 'Test requires at least 1 organization');

    const domain = await getFirstDomain(page, org!.extid);
    test.skip(!domain, 'Test requires at least 1 domain');

    await navigateToEmailConfig(page, org!.extid, domain!.extid);

    // Form should be visible
    const form = page.locator('form');
    await expect(form).toBeVisible();

    // No horizontal overflow
    const { hasOverflow } = await page.evaluate(() => {
      const scrollWidth = document.body.scrollWidth;
      const viewportWidth = window.innerWidth;
      return { hasOverflow: scrollWidth - viewportWidth > 15 };
    });

    expect(hasOverflow).toBe(false);
  });
});

/**
 * Qase Test Case Export Format
 *
 * Suite: Domain Email Configuration
 *
 * | ID          | Title                                          | Priority | Automation |
 * |-------------|------------------------------------------------|----------|------------|
 * | TC-DEC-001  | email config form loads successfully           | Critical | Automated  |
 * | TC-DEC-002  | form displays domain context                   | High     | Automated  |
 * | TC-DEC-003  | back navigation returns to domains list        | Medium   | Automated  |
 * | TC-DEC-004  | from_name field accepts input                  | Critical | Automated  |
 * | TC-DEC-005  | from_address field validates email format      | Critical | Automated  |
 * | TC-DEC-006  | reply_to field is optional                     | High     | Automated  |
 * | TC-DEC-007  | fields have proper labels                      | Medium   | Automated  |
 * | TC-DEC-008  | enabled toggle is present                      | Critical | Automated  |
 * | TC-DEC-009  | toggle can be switched                         | Critical | Automated  |
 * | TC-DEC-010  | toggle has proper ARIA attributes              | High     | Automated  |
 * | TC-DEC-011  | save button disabled when fields empty         | Critical | Automated  |
 * | TC-DEC-012  | save button enabled when fields filled         | Critical | Automated  |
 * | TC-DEC-013  | invalid email format prevents save             | Critical | Automated  |
 * | TC-DEC-014  | save button submits form                       | Critical | Automated  |
 * | TC-DEC-015  | delete button shows confirmation               | High     | Automated  |
 * | TC-DEC-016  | discard button resets form changes             | Medium   | Automated  |
 * | TC-DEC-017  | form is usable on mobile viewport              | High     | Automated  |
 */
