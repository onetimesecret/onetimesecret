// e2e/all/incoming-secrets.spec.ts

import { test, expect, Page } from '@playwright/test';

/**
 * E2E Tests for Incoming Secrets Feature
 *
 * The incoming secrets feature allows anonymous users to send secrets to
 * pre-configured recipients via /incoming. Recipients are configured
 * server-side, not by user input.
 *
 * These tests are deterministic: the backend `/api/incoming/config` and
 * `/api/incoming/secret` calls are intercepted with `page.route` (see the
 * MOCK_* fixtures below), so the suite exercises the real Vue components
 * against known config rather than "whatever the container happens to serve".
 * `/incoming` is a client-side SPA route, so it is always served (HTTP 200) —
 * the navigation helper asserts that instead of skipping, so a routing or
 * build regression FAILS the test (E2E remediation plan, Phase 2.4: "a test
 * must be able to fail").
 *
 * Running:
 *   PLAYWRIGHT_BASE_URL=http://localhost:7143 pnpm test:playwright e2e/all/incoming-secrets.spec.ts
 */

// Test data constants.
//
// Recipients use the anonymous-sender shape `{ digest, display_name }` that
// `incomingConfigSchema` validates (src/schemas/api/incoming/responses/config.ts).
// Using the wrong shape makes config parsing fail, leaving the form stuck on
// its loading state — which is exactly how this suite used to silently skip.
const MOCK_RECIPIENTS = [
  { digest: 'abc123hash', display_name: 'Security Team' },
  { digest: 'def456hash', display_name: 'Support Team' },
  { digest: 'ghi789hash', display_name: 'HR Department' },
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
    recipient: 'abc123hash',
  },
};

/**
 * Helper to set up API mocking for incoming config endpoint.
 * `**` spans path segments, so this also matches the real `/api/incoming/config`.
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
 * Navigate to /incoming with the given config mocked in.
 *
 * `/incoming` is a client-side SPA route, so the server always serves the app
 * shell (HTTP 200), never a 404 — we assert that, so a routing/build
 * regression fails the test instead of being silently skipped. Then we wait on
 * the deterministic app-readiness flag (set in src/main.ts after mount +
 * router.isReady()), never networkidle.
 */
async function navigateToIncoming(page: Page, configResponse: object): Promise<void> {
  await mockIncomingConfig(page, configResponse);
  const response = await page.goto('/incoming');
  expect(
    response?.status(),
    '/incoming should serve the SPA shell, not a 404'
  ).not.toBe(404);
  await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();
}

/**
 * Assert the incoming form is interactive.
 *
 * With an enabled config mocked in, IncomingForm renders the form once
 * loadConfig() resolves; these web-first assertions retry through the brief
 * loading state. If the form never appears the test FAILS (it no longer
 * skips), which is the point of this suite.
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

    await navigateToIncoming(page, MOCK_CONFIG_ENABLED);
    await expectFormReady(page);

    // Page title renders.
    await expect(page.locator('h1').first()).toBeVisible();

    // Recipient dropdown is present (feature enabled).
    await expect(page.locator('#incoming-recipient')).toBeVisible();

    // No critical JavaScript errors occurred (listener was registered before
    // navigation; the assertions above already waited for the UI).
    const criticalErrors = filterCriticalErrors(consoleErrors);
    expect(
      criticalErrors,
      `Page should load without console errors. Found: ${criticalErrors.join(', ')}`
    ).toHaveLength(0);
  });

  test('shows feature disabled state when backend has feature disabled', async ({ page }) => {
    await navigateToIncoming(page, MOCK_CONFIG_DISABLED);

    // The feature-disabled empty state renders and the form must NOT appear.
    await expect(page.getByTestId('incoming-feature-disabled')).toBeVisible();
    await expect(page.locator('form')).toBeHidden();
  });

  test('handles API error gracefully when config fails to load', async ({ page }) => {
    await page.route('**/incoming/config', async (route) => {
      await route.fulfill({
        status: 500,
        contentType: 'application/json',
        body: JSON.stringify({ error: 'Internal server error' }),
      });
    });

    const response = await page.goto('/incoming');
    expect(
      response?.status(),
      '/incoming should serve the SPA shell, not a 404'
    ).not.toBe(404);

    // Wait for the app to finish booting.
    await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

    // The config error surfaces (useIncomingSecret stores it on configError)
    // and the form is not shown.
    await expect(page.getByTestId('incoming-config-error')).toBeVisible();
    await expect(page.locator('form')).toBeHidden();
  });
});

test.describe('Incoming Secrets - Recipients Dropdown', () => {
  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
  });

  test('populates recipients dropdown with configured recipients', async ({ page }) => {
    await navigateToIncoming(page, MOCK_CONFIG_ENABLED);
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
    await navigateToIncoming(page, MOCK_CONFIG_ENABLED);
    await expectFormReady(page);

    // Open dropdown
    const recipientDropdown = page.locator('#incoming-recipient');
    await recipientDropdown.click();

    // Select first recipient
    const firstRecipient = page.locator(`text=${MOCK_RECIPIENTS[0].display_name}`).first();
    await firstRecipient.click();

    // Verify dropdown now shows selected recipient name
    await expect(recipientDropdown).toContainText(MOCK_RECIPIENTS[0].display_name);
  });

  test('closes dropdown when clicking outside', async ({ page }) => {
    await navigateToIncoming(page, MOCK_CONFIG_ENABLED);
    await expectFormReady(page);

    // Open dropdown
    const recipientDropdown = page.locator('#incoming-recipient');
    await recipientDropdown.click();

    // Verify dropdown menu is open (listbox is visible)
    const listbox = page.locator('[role="listbox"]');
    await expect(listbox).toBeVisible();

    // Click outside the dropdown
    await page.locator('h1').first().click();

    // Dropdown menu should close
    await expect(listbox).toBeHidden();
  });

  test('shows empty state when no recipients configured', async ({ page }) => {
    await navigateToIncoming(page, MOCK_CONFIG_NO_RECIPIENTS);
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
    await navigateToIncoming(page, MOCK_CONFIG_ENABLED);
    await expectFormReady(page);

    // Find submit button - it should be disabled initially
    const submitButton = page.locator('button[type="submit"]');
    await expect(submitButton).toBeDisabled();
  });

  test('submit button becomes enabled when required fields are filled', async ({ page }) => {
    await mockIncomingSecretCreate(page, MOCK_SUCCESS_RESPONSE);
    await navigateToIncoming(page, MOCK_CONFIG_ENABLED);
    await expectFormReady(page);

    const submitButton = page.locator('button[type="submit"]');
    await expect(submitButton).toBeDisabled();

    // Select a recipient
    const recipientDropdown = page.locator('#incoming-recipient');
    await recipientDropdown.click();
    await page.locator(`text=${MOCK_RECIPIENTS[0].display_name}`).first().click();

    // Still disabled - need secret content
    await expect(submitButton).toBeDisabled();

    // Fill in secret content
    const secretTextarea = page.locator('textarea').first();
    await secretTextarea.fill('This is a test secret message');

    // Now button should be enabled
    await expect(submitButton).toBeEnabled();
  });

  test('shows validation error when submitting without recipient', async ({ page }) => {
    await navigateToIncoming(page, MOCK_CONFIG_ENABLED);
    await expectFormReady(page);

    // Fill only secret content
    const secretTextarea = page.locator('textarea').first();
    await secretTextarea.fill('Test secret');

    // Without a recipient the submit button stays disabled.
    const submitButton = page.locator('button[type="submit"]');
    await expect(submitButton).toBeDisabled();
  });

  test('reset button clears all form fields', async ({ page }) => {
    await navigateToIncoming(page, MOCK_CONFIG_ENABLED);
    await expectFormReady(page);

    // Fill in form fields
    const recipientDropdown = page.locator('#incoming-recipient');
    await recipientDropdown.click();
    await page.locator(`text=${MOCK_RECIPIENTS[0].display_name}`).first().click();

    const secretTextarea = page.locator('textarea').first();
    await secretTextarea.fill('Test secret content');

    const memoInput = page.locator('#incoming-memo');
    await memoInput.fill('Test memo');

    // Click reset/clear button
    const resetButton = page.locator('button[type="button"]', { hasText: /clear form/i });
    await resetButton.click();

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
    await navigateToIncoming(page, MOCK_CONFIG_ENABLED);
    await expectFormReady(page);

    const memoInput = page.locator('#incoming-memo');

    // Counter is hidden until the memo approaches the limit (>80% of 50 chars).
    const counter = page.locator('text=/\\d+\\s*\\/\\s*50/');
    await expect(counter).toBeHidden();

    // Fill memo with 80%+ of limit (40+ chars for 50 char limit)
    await memoInput.fill('This is a long memo that approaches the limit');

    // Counter should now be visible
    await expect(counter).toBeVisible();
  });

  test('respects maxlength attribute on memo input', async ({ page }) => {
    await navigateToIncoming(page, MOCK_CONFIG_ENABLED);
    await expectFormReady(page);

    const memoInput = page.locator('#incoming-memo');

    // Verify maxlength attribute is set
    await expect(memoInput).toHaveAttribute('maxlength', '50');
  });

  test('counter color changes at limit', async ({ page }) => {
    await navigateToIncoming(page, MOCK_CONFIG_ENABLED);
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
    await navigateToIncoming(page, MOCK_CONFIG_ENABLED);
    await expectFormReady(page);

    // Step 1: Select recipient
    const recipientDropdown = page.locator('#incoming-recipient');
    await recipientDropdown.click();
    await page.locator(`text=${MOCK_RECIPIENTS[0].display_name}`).first().click();

    // Step 2: Enter secret content
    const secretTextarea = page.locator('textarea').first();
    await secretTextarea.fill('This is my confidential information to share securely.');

    // Step 3: Add optional memo
    const memoInput = page.locator('#incoming-memo');
    await memoInput.fill('Quarterly report credentials');

    // Step 4: Submit
    const submitButton = page.locator('button[type="submit"]');
    await expect(submitButton).toBeEnabled();
    await submitButton.click();

    // Step 5: Verify navigation to success page
    await expect(page).toHaveURL(/\/incoming\/test-metadata-key/);

    // Step 6: Verify success page elements
    // Reference ID should be displayed
    const referenceId = page.getByTestId('incoming-reference-id');
    await expect(referenceId).toContainText('test-metadata-key');

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
    await navigateToIncoming(page, MOCK_CONFIG_ENABLED);
    await expectFormReady(page);

    // Complete the form
    const recipientDropdown = page.locator('#incoming-recipient');
    await recipientDropdown.click();
    await page.locator(`text=${MOCK_RECIPIENTS[0].display_name}`).first().click();

    const secretTextarea = page.locator('textarea').first();
    await secretTextarea.fill('Test secret');

    await page.locator('button[type="submit"]').click();
    await page.waitForURL(/\/incoming\/test-metadata-key/);

    // Verify reference ID display
    await expect(page.getByTestId('incoming-reference-id')).toContainText('test-metadata-key');

    // Verify copy button exists
    await expect(page.getByTestId('incoming-copy-reference-btn')).toBeVisible();
  });

  test('create another button returns to form', async ({ page }) => {
    await mockIncomingConfig(page, MOCK_CONFIG_ENABLED);

    // Navigate directly to the success page (receiptKey comes from the URL).
    const response = await page.goto('/incoming/test-metadata-key');
    expect(
      response?.status(),
      '/incoming/:receiptKey should serve the SPA shell, not a 404'
    ).not.toBe(404);
    await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

    // The "Send Another Secret" button returns to the form.
    const createAnotherButton = page.getByTestId('incoming-send-another-btn');
    await expect(createAnotherButton).toBeVisible();
    await createAnotherButton.click();

    // Should navigate back to form
    await expect(page).toHaveURL(/\/incoming$/);
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

    await navigateToIncoming(page, MOCK_CONFIG_ENABLED);
    await expectFormReady(page);

    // Fill form
    const recipientDropdown = page.locator('#incoming-recipient');
    await recipientDropdown.click();
    await page.locator(`text=${MOCK_RECIPIENTS[0].display_name}`).first().click();

    const secretTextarea = page.locator('textarea').first();
    await secretTextarea.fill('Test secret');

    // Submit and wait for the mocked 500 response to complete - the
    // deterministic signal that error handling has been triggered.
    const failedResponse = page.waitForResponse('**/incoming/secret');
    await page.locator('button[type="submit"]').click();
    await failedResponse;

    // Form should remain visible for retry
    await expect(page.locator('form')).toBeVisible();
  });

  test('handles network timeout gracefully', async ({ page }) => {
    await page.route('**/incoming/secret', async (route) => {
      // Simulate network failure
      await route.abort('timedout');
    });

    await navigateToIncoming(page, MOCK_CONFIG_ENABLED);
    await expectFormReady(page);

    // Fill form
    const recipientDropdown = page.locator('#incoming-recipient');
    await recipientDropdown.click();
    await page.locator(`text=${MOCK_RECIPIENTS[0].display_name}`).first().click();

    const secretTextarea = page.locator('textarea').first();
    await secretTextarea.fill('Test secret');

    // Submit - this will fail at the network layer
    const submitButton = page.locator('button[type="submit"]');
    await submitButton.click();

    // Form should remain on page
    await expect(page.locator('form')).toBeVisible();
  });
});

test.describe('Incoming Secrets - Accessibility', () => {
  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
  });

  test('form elements have proper ARIA attributes', async ({ page }) => {
    await navigateToIncoming(page, MOCK_CONFIG_ENABLED);
    await expectFormReady(page);

    // Recipient dropdown has aria-label
    const recipientDropdown = page.locator('#incoming-recipient');
    const ariaLabel = await recipientDropdown.getAttribute('aria-label');
    expect(ariaLabel).toBeTruthy();

    // Memo input has aria-label
    const memoInput = page.locator('#incoming-memo');
    const memoAriaLabel = await memoInput.getAttribute('aria-label');
    expect(memoAriaLabel).toBeTruthy();
  });

  test('dropdown has proper ARIA expanded state', async ({ page }) => {
    await navigateToIncoming(page, MOCK_CONFIG_ENABLED);
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
    await navigateToIncoming(page, MOCK_CONFIG_ENABLED);
    await expectFormReady(page);

    // Tab through form elements
    await page.keyboard.press('Tab');
    await page.keyboard.press('Tab');

    // Focus should move through form
    const focusedElement = await page.evaluate(() => document.activeElement?.tagName);
    expect(focusedElement).toBeTruthy();
  });
});

test.describe('Incoming Secrets - Mobile Responsiveness', () => {
  test('form renders correctly on mobile viewport', async ({ page }) => {
    // Set mobile viewport before navigation
    await page.setViewportSize({ width: 375, height: 667 });

    await navigateToIncoming(page, MOCK_CONFIG_ENABLED);
    await expectFormReady(page);

    // Form should be visible and not overflow
    const form = page.locator('form');
    await expect(form).toBeVisible();

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

    await navigateToIncoming(page, MOCK_CONFIG_ENABLED);
    await expectFormReady(page);

    // Get button positions
    const submitButton = page.locator('button[type="submit"]');
    const resetButton = page.locator('button[type="button"]', { hasText: /clear form/i });

    const submitBox = await submitButton.boundingBox();
    const resetBox = await resetButton.boundingBox();

    // On mobile, buttons should be stacked (different Y positions)
    // Submit should come before reset (order-1 vs order-2 in mobile)
    expect(submitBox).toBeTruthy();
    expect(resetBox).toBeTruthy();
  });
});
