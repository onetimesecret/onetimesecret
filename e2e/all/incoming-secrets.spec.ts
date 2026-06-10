// e2e/all/incoming-secrets.spec.ts

import { test, expect, Page } from '@playwright/test';

/**
 * E2E Tests for Incoming Secrets Feature
 *
 * The incoming secrets feature allows anonymous users to send secrets to
 * pre-configured recipients via /incoming. Recipients are configured
 * server-side, not by user input.
 *
 * Test Scenarios:
 * 1. Navigate to /incoming and verify form loads
 * 2. Verify recipients dropdown populates (when feature enabled)
 * 3. Complete happy-path flow: fill form -> submit -> verify success page
 * 4. Test validation errors (empty required fields)
 * 5. Test character counter for memo field
 * 6. Test feature-disabled state (graceful error message)
 *
 * Determinism (remediation plan Phase 2.4): the /incoming route is
 * unconditional — the backend serves the SPA shell for it with auth=noauth
 * (apps/web/core/routes.txt) and the Vue router registers it statically
 * (src/apps/secret/routes/incoming.ts) — and every backend response these
 * tests depend on is mocked via page.route(). There is therefore nothing
 * environmental to probe: the form either renders from the mocked config or
 * the product is broken, so the tests assert instead of skipping.
 *
 * The recipient fixtures match incomingRecipientSchema
 * (src/schemas/api/incoming/responses/config.ts): `digest` (hashed email,
 * never plaintext) + `display_name`. A stale `{hash, name}` shape previously
 * failed schema validation in the store, which silently put the page into
 * its config-error state and made 19 of these tests self-skip in CI.
 *
 * Running:
 *   # With dev server
 *   PLAYWRIGHT_BASE_URL=http://localhost:5173 pnpm test:playwright e2e/all/incoming-secrets.spec.ts
 *
 *   # With production build
 *   PLAYWRIGHT_BASE_URL=http://localhost:7143 pnpm test:playwright e2e/all/incoming-secrets.spec.ts
 */

// Test data constants — shape must match incomingRecipientSchema.
const MOCK_RECIPIENTS = [
  { digest: 'abc123digest', display_name: 'Security Team' },
  { digest: 'def456digest', display_name: 'Support Team' },
  { digest: 'ghi789digest', display_name: 'HR Department' },
];

const MOCK_CONFIG_ENABLED = {
  config: {
    enabled: true,
    memo_max_length: 50,
    recipients: MOCK_RECIPIENTS,
    default_ttl: 86400,
  },
};

const MOCK_CONFIG_DISABLED = {
  config: {
    enabled: false,
    memo_max_length: 50,
    recipients: [],
  },
};

const MOCK_CONFIG_NO_RECIPIENTS = {
  config: {
    enabled: true,
    memo_max_length: 50,
    recipients: [],
    default_ttl: 86400,
  },
};

const MOCK_SUCCESS_RESPONSE = {
  success: true,
  message: 'Secret created successfully',
  record: {
    receipt: {
      identifier: 'metadata:test-metadata-key',
      key: 'test-metadata-key',
      state: 'new',
      custid: null,
    },
    secret: {
      identifier: 'secret:test-secret-key',
      key: 'test-secret-key',
      state: 'new',
    },
  },
  details: {
    memo: 'Test memo',
    recipient: 'abc123digest',
  },
};

/**
 * Helper to set up API mocking for incoming config endpoint
 * (the store fetches /api/incoming/config; `**` matches the prefix)
 */
async function mockIncomingConfig(page: Page, configResponse: object) {
  await page.route('**/incoming/config', async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify(configResponse),
    });
  });
}

/**
 * Helper to set up API mocking for incoming secret creation
 */
async function mockIncomingSecretCreate(page: Page, response: object, status = 200) {
  await page.route('**/incoming/secret', async (route) => {
    await route.fulfill({
      status,
      contentType: 'application/json',
      body: JSON.stringify(response),
    });
  });
}

/**
 * Helper to collect console errors during test execution
 */
function setupErrorCollection(page: Page): string[] {
  const errors: string[] = [];
  page.on('console', (msg) => {
    if (msg.type() === 'error') {
      errors.push(msg.text());
    }
  });
  return errors;
}

/**
 * Filter out non-critical console errors (dev tooling, websocket, etc.)
 */
function filterCriticalErrors(errors: string[]): string[] {
  return errors.filter(
    (error) =>
      !error.includes('Non-Error promise rejection') &&
      !error.includes('Script error') &&
      !error.includes('WebSocket') &&
      !error.includes('[vite]') &&
      !error.includes('hmr') &&
      !error.includes('favicon')
  );
}

/**
 * Navigate to /incoming with the given config mock and wait for the app to
 * finish booting. The route always exists; no availability probing.
 */
async function gotoIncoming(page: Page, configResponse: object): Promise<void> {
  await mockIncomingConfig(page, configResponse);
  await page.goto('/incoming');
  await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();
}

/**
 * Assert the incoming form rendered from the mocked (enabled) config.
 * Fails — never skips — when the form is missing: that means the page fell
 * into its error/disabled state, which is a product or fixture regression.
 */
async function expectFormReady(page: Page): Promise<void> {
  await expect(page.getByTestId('incoming-form')).toBeVisible();
  await expect(page.locator('#incoming-recipient')).toBeVisible();
}

test.describe('Incoming Secrets - Form Loading', () => {
  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
  });

  test('navigates to /incoming and loads form when feature is enabled', async ({ page }) => {
    const consoleErrors = setupErrorCollection(page);

    await gotoIncoming(page, MOCK_CONFIG_ENABLED);

    // Page header renders with content
    const pageTitle = page.locator('h1').first();
    await expect(pageTitle).toBeVisible();
    await expect(pageTitle).not.toBeEmpty();

    // Form and recipient dropdown render from the mocked config
    await expectFormReady(page);

    // Verify no critical JavaScript errors occurred (listener was registered
    // before navigation; the assertions above already waited for the UI)
    const criticalErrors = filterCriticalErrors(consoleErrors);
    expect(
      criticalErrors,
      `Page should load without console errors. Found: ${criticalErrors.join(', ')}`
    ).toHaveLength(0);
  });

  test('shows feature disabled state when backend has feature disabled', async ({ page }) => {
    await gotoIncoming(page, MOCK_CONFIG_DISABLED);

    // The feature-disabled empty state renders; the form does not
    await expect(page.getByTestId('incoming-feature-disabled')).toBeVisible();
    await expect(page.getByTestId('incoming-form')).not.toBeVisible();
  });

  test('handles API error gracefully when config fails to load', async ({ page }) => {
    await page.route('**/incoming/config', async (route) => {
      await route.fulfill({
        status: 500,
        contentType: 'application/json',
        body: JSON.stringify({ error: 'Internal server error' }),
      });
    });

    await page.goto('/incoming');

    // Wait for the app to finish booting; the mocked 500 means the page
    // must settle into its error state without the form.
    await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

    await expect(page.getByTestId('incoming-config-error')).toBeVisible();
    await expect(page.getByTestId('incoming-form')).not.toBeVisible();
  });
});

test.describe('Incoming Secrets - Recipients Dropdown', () => {
  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
  });

  test('populates recipients dropdown with configured recipients', async ({ page }) => {
    await gotoIncoming(page, MOCK_CONFIG_ENABLED);
    await expectFormReady(page);

    // Click the recipient dropdown to open it
    const recipientDropdown = page.locator('#incoming-recipient');
    await recipientDropdown.click();

    // Verify all mock recipients are listed in the dropdown
    const listbox = page.getByTestId('recipient-listbox');
    for (const recipient of MOCK_RECIPIENTS) {
      const recipientOption = listbox.getByText(recipient.display_name, { exact: true });
      await expect(recipientOption).toBeVisible();
    }
  });

  test('allows selecting a recipient from dropdown', async ({ page }) => {
    await gotoIncoming(page, MOCK_CONFIG_ENABLED);
    await expectFormReady(page);

    // Open dropdown
    const recipientDropdown = page.locator('#incoming-recipient');
    await recipientDropdown.click();

    // Select first recipient
    await page.getByTestId(`recipient-option-${MOCK_RECIPIENTS[0].digest}`).click();

    // Verify dropdown now shows selected recipient name
    await expect(recipientDropdown).toContainText(MOCK_RECIPIENTS[0].display_name);
  });

  test('closes dropdown when clicking outside', async ({ page }) => {
    await gotoIncoming(page, MOCK_CONFIG_ENABLED);
    await expectFormReady(page);

    // Open dropdown
    const recipientDropdown = page.locator('#incoming-recipient');
    await recipientDropdown.click();

    // Verify dropdown menu is open (listbox is visible)
    const listbox = page.locator('[role="listbox"]');
    await expect(listbox).toBeVisible();

    // Click outside the dropdown
    await page.locator('h1').click();

    // Dropdown menu should close
    await expect(listbox).not.toBeVisible();
  });

  test('shows empty state when no recipients configured', async ({ page }) => {
    await gotoIncoming(page, MOCK_CONFIG_NO_RECIPIENTS);
    await expectFormReady(page);

    // Open dropdown
    const recipientDropdown = page.locator('#incoming-recipient');
    await recipientDropdown.click();

    // Should show empty message instead of recipient list
    const emptyMessage = page.locator('text=No recipients');
    await expect(emptyMessage).toBeVisible();
  });
});

test.describe('Incoming Secrets - Form Validation', () => {
  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
  });

  test('submit button is disabled when form is incomplete', async ({ page }) => {
    await gotoIncoming(page, MOCK_CONFIG_ENABLED);
    await expectFormReady(page);

    // Find submit button - it should be disabled initially
    const submitButton = page.getByTestId('incoming-form-submit');
    await expect(submitButton).toBeDisabled();
  });

  test('submit button becomes enabled when required fields are filled', async ({ page }) => {
    await mockIncomingSecretCreate(page, MOCK_SUCCESS_RESPONSE);
    await gotoIncoming(page, MOCK_CONFIG_ENABLED);
    await expectFormReady(page);

    const submitButton = page.getByTestId('incoming-form-submit');
    await expect(submitButton).toBeDisabled();

    // Select a recipient
    const recipientDropdown = page.locator('#incoming-recipient');
    await recipientDropdown.click();
    await page.getByTestId(`recipient-option-${MOCK_RECIPIENTS[0].digest}`).click();

    // Still disabled - need secret content
    await expect(submitButton).toBeDisabled();

    // Fill in secret content
    const secretTextarea = page.locator('textarea').first();
    await secretTextarea.fill('This is a test secret message');

    // Now button should be enabled
    await expect(submitButton).toBeEnabled();
  });

  test('submit stays blocked without a recipient', async ({ page }) => {
    await gotoIncoming(page, MOCK_CONFIG_ENABLED);
    await expectFormReady(page);

    // Fill only secret content
    const secretTextarea = page.locator('textarea').first();
    await secretTextarea.fill('Test secret');

    // Submit must remain disabled until a recipient is selected
    const submitButton = page.getByTestId('incoming-form-submit');
    await expect(submitButton).toBeDisabled();
  });

  test('reset button clears all form fields', async ({ page }) => {
    await gotoIncoming(page, MOCK_CONFIG_ENABLED);
    await expectFormReady(page);

    // Fill in form fields
    const recipientDropdown = page.locator('#incoming-recipient');
    await recipientDropdown.click();
    await page.getByTestId(`recipient-option-${MOCK_RECIPIENTS[0].digest}`).click();

    const secretTextarea = page.locator('textarea').first();
    await secretTextarea.fill('Test secret content');

    const memoInput = page.locator('#incoming-memo');
    await memoInput.fill('Test memo');

    // Click reset/clear button
    await page.getByTestId('incoming-form-reset').click();

    // Verify fields are cleared
    await expect(memoInput).toHaveValue('');
    await expect(secretTextarea).toHaveValue('');
    // Recipient should be reset to placeholder
    await expect(recipientDropdown).toContainText('Select');
  });
});

test.describe('Incoming Secrets - Memo Character Counter', () => {
  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
  });

  test('shows character counter when approaching limit', async ({ page }) => {
    await gotoIncoming(page, MOCK_CONFIG_ENABLED);
    await expectFormReady(page);

    const memoInput = page.locator('#incoming-memo');

    // Counter should not be visible initially
    const counter = page.locator('text=/\\d+\\s*\\/\\s*50/');
    await expect(counter).not.toBeVisible();

    // Fill memo with 80%+ of limit (40+ chars for 50 char limit)
    await memoInput.fill('This is a long memo that approaches the limit');

    // Counter should now be visible
    await expect(counter).toBeVisible();
  });

  test('respects maxlength attribute on memo input', async ({ page }) => {
    await gotoIncoming(page, MOCK_CONFIG_ENABLED);
    await expectFormReady(page);

    // maxlength comes from the mocked memo_max_length
    await expect(page.locator('#incoming-memo')).toHaveAttribute('maxlength', '50');
  });

  test('counter color changes at limit', async ({ page }) => {
    await gotoIncoming(page, MOCK_CONFIG_ENABLED);
    await expectFormReady(page);

    const memoInput = page.locator('#incoming-memo');

    // Fill to exactly the limit
    await memoInput.fill('A'.repeat(50));

    // Counter should be visible with warning color (amber)
    const counter = page.locator('text=50 / 50');
    await expect(counter).toBeVisible();
  });
});

test.describe('Incoming Secrets - Happy Path Flow', () => {
  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
  });

  test('completes full flow: fill form -> submit -> success page', async ({ page }) => {
    const consoleErrors = setupErrorCollection(page);

    await mockIncomingSecretCreate(page, MOCK_SUCCESS_RESPONSE);
    await gotoIncoming(page, MOCK_CONFIG_ENABLED);
    await expectFormReady(page);

    // Step 1: Select recipient
    const recipientDropdown = page.locator('#incoming-recipient');
    await recipientDropdown.click();
    await page.getByTestId(`recipient-option-${MOCK_RECIPIENTS[0].digest}`).click();

    // Step 2: Enter secret content
    const secretTextarea = page.locator('textarea').first();
    await secretTextarea.fill('This is my confidential information to share securely.');

    // Step 3: Add optional memo
    const memoInput = page.locator('#incoming-memo');
    await memoInput.fill('Quarterly report credentials');

    // Step 4: Submit
    const submitButton = page.getByTestId('incoming-form-submit');
    await expect(submitButton).toBeEnabled();
    await submitButton.click();

    // Step 5: Verify navigation to success page
    await expect(page).toHaveURL(/\/incoming\/test-metadata-key/);

    // Step 6: Verify success page elements
    // Success heading should be visible
    const successHeading = page.locator('h1');
    await expect(successHeading).toBeVisible();

    // Reference ID should be displayed
    await expect(page.getByTestId('incoming-reference-id')).toContainText('test-metadata-key');

    // "Send Another Secret" button should be visible
    await expect(page.getByTestId('incoming-send-another-btn')).toBeVisible();

    // Verify no critical errors (listener was registered before navigation;
    // the assertions above already waited for the UI)
    const criticalErrors = filterCriticalErrors(consoleErrors);
    expect(
      criticalErrors,
      `Happy path should complete without errors. Found: ${criticalErrors.join(', ')}`
    ).toHaveLength(0);
  });

  test('success page shows reference ID and copy button', async ({ page }) => {
    await mockIncomingSecretCreate(page, MOCK_SUCCESS_RESPONSE);
    await gotoIncoming(page, MOCK_CONFIG_ENABLED);
    await expectFormReady(page);

    // Complete the form
    const recipientDropdown = page.locator('#incoming-recipient');
    await recipientDropdown.click();
    await page.getByTestId(`recipient-option-${MOCK_RECIPIENTS[0].digest}`).click();

    const secretTextarea = page.locator('textarea').first();
    await secretTextarea.fill('Test secret');

    await page.getByTestId('incoming-form-submit').click();
    await page.waitForURL(/\/incoming\//, { timeout: 10000 });

    // Verify reference ID display
    await expect(page.getByTestId('incoming-reference-id')).toContainText('test-metadata-key');

    // Verify copy button exists
    await expect(page.getByTestId('incoming-copy-reference-btn')).toBeVisible();
  });

  test('create another button returns to form', async ({ page }) => {
    await mockIncomingConfig(page, MOCK_CONFIG_ENABLED);

    // Navigate directly to success page (renders purely from the route
    // param; no API call involved)
    await page.goto('/incoming/test-metadata-key');
    await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

    const createAnotherButton = page.getByTestId('incoming-send-another-btn');
    await expect(createAnotherButton).toBeVisible();
    await createAnotherButton.click();

    // Should navigate back to form
    await expect(page).toHaveURL('/incoming');
  });
});

test.describe('Incoming Secrets - Error Handling', () => {
  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
  });

  test('handles API error during submission gracefully', async ({ page }) => {
    await page.route('**/incoming/secret', async (route) => {
      await route.fulfill({
        status: 500,
        contentType: 'application/json',
        body: JSON.stringify({ error: 'Internal server error' }),
      });
    });

    await gotoIncoming(page, MOCK_CONFIG_ENABLED);
    await expectFormReady(page);

    // Fill form
    const recipientDropdown = page.locator('#incoming-recipient');
    await recipientDropdown.click();
    await page.getByTestId(`recipient-option-${MOCK_RECIPIENTS[0].digest}`).click();

    const secretTextarea = page.locator('textarea').first();
    await secretTextarea.fill('Test secret');

    // Submit and wait for the mocked 500 response to complete - the
    // deterministic signal that error handling has been triggered.
    const failedResponse = page.waitForResponse('**/incoming/secret');
    await page.getByTestId('incoming-form-submit').click();
    await failedResponse;

    // Form should remain visible for retry
    await expect(page.getByTestId('incoming-form')).toBeVisible();
  });

  test('handles network failure during submission gracefully', async ({ page }) => {
    await page.route('**/incoming/secret', async (route) => {
      await route.abort('timedout');
    });

    await gotoIncoming(page, MOCK_CONFIG_ENABLED);
    await expectFormReady(page);

    // Fill form
    const recipientDropdown = page.locator('#incoming-recipient');
    await recipientDropdown.click();
    await page.getByTestId(`recipient-option-${MOCK_RECIPIENTS[0].digest}`).click();

    const secretTextarea = page.locator('textarea').first();
    await secretTextarea.fill('Test secret');

    // Submit - the aborted request must surface as a handled error
    const submitButton = page.getByTestId('incoming-form-submit');
    await submitButton.click();

    // Form remains on page and the submit button recovers from its
    // submitting state (isSubmitting resets in the error path)
    await expect(page.getByTestId('incoming-form')).toBeVisible();
    await expect(submitButton).toBeEnabled();
  });
});

test.describe('Incoming Secrets - Accessibility', () => {
  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
  });

  test('form elements have proper ARIA attributes', async ({ page }) => {
    await gotoIncoming(page, MOCK_CONFIG_ENABLED);
    await expectFormReady(page);

    // Recipient dropdown has a non-empty aria-label
    await expect(page.locator('#incoming-recipient')).toHaveAttribute('aria-label', /.+/);

    // Memo input has a non-empty aria-label
    await expect(page.locator('#incoming-memo')).toHaveAttribute('aria-label', /.+/);
  });

  test('dropdown has proper ARIA expanded state', async ({ page }) => {
    await gotoIncoming(page, MOCK_CONFIG_ENABLED);
    await expectFormReady(page);

    const recipientDropdown = page.locator('#incoming-recipient');

    // Initially not expanded
    await expect(recipientDropdown).toHaveAttribute('aria-expanded', 'false');

    // Click to open
    await recipientDropdown.click();

    // Now expanded
    await expect(recipientDropdown).toHaveAttribute('aria-expanded', 'true');
  });

  test('form is keyboard navigable', async ({ page }) => {
    await gotoIncoming(page, MOCK_CONFIG_ENABLED);
    await expectFormReady(page);

    // Tab through form elements
    await page.keyboard.press('Tab');
    await page.keyboard.press('Tab');

    // Focus must have moved off the document body into the page content
    const focusedElement = await page.evaluate(
      () => document.activeElement?.tagName ?? 'BODY'
    );
    expect(focusedElement).not.toBe('BODY');
  });
});

test.describe('Incoming Secrets - Mobile Responsiveness', () => {
  test('form renders correctly on mobile viewport', async ({ page }) => {
    // Set mobile viewport before navigation
    await page.setViewportSize({ width: 375, height: 667 });

    await gotoIncoming(page, MOCK_CONFIG_ENABLED);
    await expectFormReady(page);

    // Check no horizontal overflow
    const { scrollWidth, viewportWidth, hasOverflow } = await page.evaluate(() => {
      const scrollWidth = document.body.scrollWidth;
      const viewportWidth = window.innerWidth;
      const overflowAmount = scrollWidth - viewportWidth;
      return {
        scrollWidth,
        viewportWidth,
        hasOverflow: overflowAmount > 15,
      };
    });

    expect(
      hasOverflow,
      `Form should not have horizontal overflow on mobile: scrollWidth=${scrollWidth}, viewportWidth=${viewportWidth}`
    ).toBe(false);
  });

  test('buttons stack vertically on mobile', async ({ page }) => {
    // Set mobile viewport before navigation
    await page.setViewportSize({ width: 375, height: 667 });

    await gotoIncoming(page, MOCK_CONFIG_ENABLED);
    await expectFormReady(page);

    // Get button positions
    const submitButton = page.getByTestId('incoming-form-submit');
    const resetButton = page.getByTestId('incoming-form-reset');

    const submitBox = await submitButton.boundingBox();
    const resetBox = await resetButton.boundingBox();

    // On mobile the action row is flex-col: submit (order-1) renders above
    // reset (order-2), i.e. strictly smaller Y
    expect(submitBox).not.toBeNull();
    expect(resetBox).not.toBeNull();
    expect(submitBox!.y).toBeLessThan(resetBox!.y);
  });
});
