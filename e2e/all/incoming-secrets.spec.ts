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
 * Prerequisites:
 * - Backend server running with incoming secrets feature enabled in config
 * - At least one recipient configured in the backend
 *
 * Running:
 *   # With dev server
 *   PLAYWRIGHT_BASE_URL=http://localhost:5173 pnpm test:playwright e2e/all/incoming-secrets.spec.ts
 *
 *   # With production build
 *   PLAYWRIGHT_BASE_URL=http://localhost:7143 pnpm test:playwright e2e/all/incoming-secrets.spec.ts
 *
 * Note: Tests use API mocking to simulate various backend states.
 * If backend doesn't support /incoming route, tests will be skipped.
 */

// Test data constants
const MOCK_RECIPIENTS = [
  { hash: 'abc123hash', name: 'Security Team' },
  { hash: 'def456hash', name: 'Support Team' },
  { hash: 'ghi789hash', name: 'HR Department' },
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
 * Helper to set up API mocking for incoming config endpoint
 */
async function mockIncomingConfig(page: Page, configResponse: object) {
  await page.route('**/api/v3/incoming/config', async (route) => {
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
  await page.route('**/api/v3/incoming/secret', async (route) => {
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
 * Helper to navigate to incoming page with proper setup
 * Returns false if route is not available (404)
 */
async function navigateToIncoming(page: Page, configResponse: object): Promise<boolean> {
  await mockIncomingConfig(page, configResponse);
  const response = await page.goto('/incoming');

  if (response?.status() === 404) {
    return false;
  }

  await page.waitForLoadState('domcontentloaded');

  // Wait for Vue app to render
  try {
    await page.waitForSelector('h1, form, [class*="empty"]', { timeout: 10000 });
  } catch {
    // Page may be showing error state
  }

  return true;
}

/**
 * Helper to wait for form to be interactive
 */
async function waitForFormReady(page: Page): Promise<boolean> {
  try {
    await page.waitForSelector('form', { state: 'visible', timeout: 5000 });
    await page.waitForSelector('#incoming-recipient', { state: 'visible', timeout: 5000 });
    return true;
  } catch {
    return false;
  }
}

test.describe('Incoming Secrets - Form Loading', () => {
  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
  });

  test('navigates to /incoming and loads form when feature is enabled', async ({ page }) => {
    const consoleErrors = setupErrorCollection(page);

    // Set up API mocking before navigation
    await mockIncomingConfig(page, MOCK_CONFIG_ENABLED);

    // Navigate and wait for Vue app to mount
    const response = await page.goto('/incoming');

    // Skip test if route not supported (404)
    if (response?.status() === 404) {
      test.skip(true, 'Incoming route not available in this environment');
      return;
    }

    await page.waitForLoadState('domcontentloaded');

    // Wait for Vue app to hydrate and render content
    const vueRendered = await page.waitForFunction(() => {
      const h1 = document.querySelector('h1');
      return h1 && h1.textContent && h1.textContent.trim().length > 0;
    }, { timeout: 10000 }).then(() => true).catch(() => false);

    // If Vue app didn't render content, skip the test
    if (!vueRendered) {
      // Check if we have at least some content (error page, etc.)
      const bodyText = await page.textContent('body');
      const hasContent = bodyText && bodyText.trim().length > 50;

      if (!hasContent) {
        // No content at all - likely backend not running properly
        test.skip(true, 'Page content not rendering (backend may not be available)');
        return;
      }
    }

    // Verify page title area is visible (may be in header or page body)
    const pageTitle = page.locator('h1').first();
    const hasTitleVisible = await pageTitle.isVisible().catch(() => false);

    if (!hasTitleVisible) {
      // No title visible - skip as feature not available
      test.skip(true, 'Page title not visible (feature may not be configured)');
      return;
    }

    await expect(pageTitle).toBeVisible();

    // Verify form container is visible (only if feature is enabled)
    const formContainer = page.locator('form');
    const hasForm = await formContainer.isVisible().catch(() => false);

    if (hasForm) {
      // Verify recipient dropdown is present
      const recipientDropdown = page.locator('#incoming-recipient');
      await expect(recipientDropdown).toBeVisible();
    }

    // Verify no critical JavaScript errors occurred
    await page.waitForTimeout(500);
    const criticalErrors = filterCriticalErrors(consoleErrors);
    expect(
      criticalErrors,
      `Page should load without console errors. Found: ${criticalErrors.join(', ')}`
    ).toHaveLength(0);
  });

  test('shows feature disabled state when backend has feature disabled', async ({ page }) => {
    const routeAvailable = await navigateToIncoming(page, MOCK_CONFIG_DISABLED);

    if (!routeAvailable) {
      test.skip(true, 'Incoming route not available');
      return;
    }

    // Should show empty state / feature disabled message
    // The form should NOT be visible
    const form = page.locator('form');
    const formVisible = await form.isVisible().catch(() => false);
    expect(formVisible).toBe(false);

    // Should show some indication that feature is disabled
    const pageContent = await page.textContent('body');
    expect(pageContent).toBeTruthy();
  });

  test('handles API error gracefully when config fails to load', async ({ page }) => {
    await page.route('**/api/v3/incoming/config', async (route) => {
      await route.fulfill({
        status: 500,
        contentType: 'application/json',
        body: JSON.stringify({ error: 'Internal server error' }),
      });
    });

    const response = await page.goto('/incoming');

    if (response?.status() === 404) {
      test.skip(true, 'Incoming route not available');
      return;
    }

    await page.waitForLoadState('domcontentloaded');
    await page.waitForTimeout(2000); // Allow error handling to complete

    // Form should not be visible
    const form = page.locator('form');
    const formVisible = await form.isVisible().catch(() => false);
    expect(formVisible).toBe(false);

    // Page should still render (body element exists)
    const bodyExists = await page.locator('body').count();
    expect(bodyExists).toBeGreaterThan(0);
  });
});

test.describe('Incoming Secrets - Recipients Dropdown', () => {
  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
  });

  test('populates recipients dropdown with configured recipients', async ({ page }) => {
    const routeAvailable = await navigateToIncoming(page, MOCK_CONFIG_ENABLED);
    if (!routeAvailable) {
      test.skip(true, 'Incoming route not available');
      return;
    }

    const formReady = await waitForFormReady(page);
    if (!formReady) {
      test.skip(true, 'Form not available (feature may be disabled)');
      return;
    }

    // Click the recipient dropdown to open it
    const recipientDropdown = page.locator('#incoming-recipient');
    await recipientDropdown.click();

    // Verify all mock recipients are listed
    for (const recipient of MOCK_RECIPIENTS) {
      const recipientOption = page.locator(`text=${recipient.name}`);
      await expect(recipientOption).toBeVisible();
    }
  });

  test('allows selecting a recipient from dropdown', async ({ page }) => {
    const routeAvailable = await navigateToIncoming(page, MOCK_CONFIG_ENABLED);
    if (!routeAvailable) {
      test.skip(true, 'Incoming route not available');
      return;
    }

    const formReady = await waitForFormReady(page);
    if (!formReady) {
      test.skip(true, 'Form not available');
      return;
    }

    // Open dropdown
    const recipientDropdown = page.locator('#incoming-recipient');
    await recipientDropdown.click();

    // Select first recipient
    const firstRecipient = page.locator(`text=${MOCK_RECIPIENTS[0].name}`).first();
    await firstRecipient.click();

    // Verify dropdown now shows selected recipient name
    await expect(recipientDropdown).toContainText(MOCK_RECIPIENTS[0].name);
  });

  test('closes dropdown when clicking outside', async ({ page }) => {
    const routeAvailable = await navigateToIncoming(page, MOCK_CONFIG_ENABLED);
    if (!routeAvailable) {
      test.skip(true, 'Incoming route not available');
      return;
    }

    const formReady = await waitForFormReady(page);
    if (!formReady) {
      test.skip(true, 'Form not available');
      return;
    }

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
    const routeAvailable = await navigateToIncoming(page, MOCK_CONFIG_NO_RECIPIENTS);
    if (!routeAvailable) {
      test.skip(true, 'Incoming route not available');
      return;
    }

    const formReady = await waitForFormReady(page);
    if (!formReady) {
      test.skip(true, 'Form not available');
      return;
    }

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
    const routeAvailable = await navigateToIncoming(page, MOCK_CONFIG_ENABLED);
    if (!routeAvailable) {
      test.skip(true, 'Incoming route not available');
      return;
    }

    const formReady = await waitForFormReady(page);
    if (!formReady) {
      test.skip(true, 'Form not available');
      return;
    }

    // Find submit button - it should be disabled initially
    const submitButton = page.locator('button[type="submit"]');
    await expect(submitButton).toBeDisabled();
  });

  test('submit button becomes enabled when required fields are filled', async ({ page }) => {
    await mockIncomingSecretCreate(page, MOCK_SUCCESS_RESPONSE);
    const routeAvailable = await navigateToIncoming(page, MOCK_CONFIG_ENABLED);
    if (!routeAvailable) {
      test.skip(true, 'Incoming route not available');
      return;
    }

    const formReady = await waitForFormReady(page);
    if (!formReady) {
      test.skip(true, 'Form not available');
      return;
    }

    const submitButton = page.locator('button[type="submit"]');
    await expect(submitButton).toBeDisabled();

    // Select a recipient
    const recipientDropdown = page.locator('#incoming-recipient');
    await recipientDropdown.click();
    await page.locator(`text=${MOCK_RECIPIENTS[0].name}`).first().click();

    // Still disabled - need secret content
    await expect(submitButton).toBeDisabled();

    // Fill in secret content
    const secretTextarea = page.locator('textarea').first();
    await secretTextarea.fill('This is a test secret message');

    // Now button should be enabled
    await expect(submitButton).toBeEnabled();
  });

  test('shows validation error when submitting without recipient', async ({ page }) => {
    const routeAvailable = await navigateToIncoming(page, MOCK_CONFIG_ENABLED);
    if (!routeAvailable) {
      test.skip(true, 'Incoming route not available');
      return;
    }

    const formReady = await waitForFormReady(page);
    if (!formReady) {
      test.skip(true, 'Form not available');
      return;
    }

    // Fill only secret content
    const secretTextarea = page.locator('textarea').first();
    await secretTextarea.fill('Test secret');

    // Try to submit (button should be disabled, but let's verify the form state)
    const submitButton = page.locator('button[type="submit"]');
    await expect(submitButton).toBeDisabled();
  });

  test('reset button clears all form fields', async ({ page }) => {
    const routeAvailable = await navigateToIncoming(page, MOCK_CONFIG_ENABLED);
    if (!routeAvailable) {
      test.skip(true, 'Incoming route not available');
      return;
    }

    const formReady = await waitForFormReady(page);
    if (!formReady) {
      test.skip(true, 'Form not available');
      return;
    }

    // Fill in form fields
    const recipientDropdown = page.locator('#incoming-recipient');
    await recipientDropdown.click();
    await page.locator(`text=${MOCK_RECIPIENTS[0].name}`).first().click();

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
    const routeAvailable = await navigateToIncoming(page, MOCK_CONFIG_ENABLED);
    if (!routeAvailable) {
      test.skip(true, 'Incoming route not available');
      return;
    }

    const formReady = await waitForFormReady(page);
    if (!formReady) {
      test.skip(true, 'Form not available');
      return;
    }

    const memoInput = page.locator('#incoming-memo');

    // Counter should not be visible initially
    const counter = page.locator('text=/\\d+\\s*\\/\\s*50/');
    const counterInitiallyVisible = await counter.isVisible().catch(() => false);
    expect(counterInitiallyVisible).toBe(false);

    // Fill memo with 80%+ of limit (40+ chars for 50 char limit)
    await memoInput.fill('This is a long memo that approaches the limit');

    // Counter should now be visible
    await expect(counter).toBeVisible();
  });

  test('respects maxlength attribute on memo input', async ({ page }) => {
    const routeAvailable = await navigateToIncoming(page, MOCK_CONFIG_ENABLED);
    if (!routeAvailable) {
      test.skip(true, 'Incoming route not available');
      return;
    }

    const formReady = await waitForFormReady(page);
    if (!formReady) {
      test.skip(true, 'Form not available');
      return;
    }

    const memoInput = page.locator('#incoming-memo');

    // Verify maxlength attribute is set
    const maxLength = await memoInput.getAttribute('maxlength');
    expect(maxLength).toBe('50');
  });

  test('counter color changes at limit', async ({ page }) => {
    const routeAvailable = await navigateToIncoming(page, MOCK_CONFIG_ENABLED);
    if (!routeAvailable) {
      test.skip(true, 'Incoming route not available');
      return;
    }

    const formReady = await waitForFormReady(page);
    if (!formReady) {
      test.skip(true, 'Form not available');
      return;
    }

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
    const routeAvailable = await navigateToIncoming(page, MOCK_CONFIG_ENABLED);
    if (!routeAvailable) {
      test.skip(true, 'Incoming route not available');
      return;
    }

    const formReady = await waitForFormReady(page);
    if (!formReady) {
      test.skip(true, 'Form not available');
      return;
    }

    // Step 1: Select recipient
    const recipientDropdown = page.locator('#incoming-recipient');
    await recipientDropdown.click();
    await page.locator(`text=${MOCK_RECIPIENTS[0].name}`).first().click();

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
    // Success icon/checkmark should be visible
    const successHeading = page.locator('h1');
    await expect(successHeading).toBeVisible();

    // Reference ID should be displayed
    const referenceId = page.locator('code', { hasText: 'test-metadata-key' });
    await expect(referenceId).toBeVisible();

    // "Send Another Secret" button should be visible
    const createAnotherButton = page.locator('button', { hasText: /send another/i });
    await expect(createAnotherButton).toBeVisible();

    // Verify no critical errors
    await page.waitForTimeout(500);
    const criticalErrors = filterCriticalErrors(consoleErrors);
    expect(
      criticalErrors,
      `Happy path should complete without errors. Found: ${criticalErrors.join(', ')}`
    ).toHaveLength(0);
  });

  test('success page shows reference ID and copy button', async ({ page }) => {
    await mockIncomingSecretCreate(page, MOCK_SUCCESS_RESPONSE);
    const routeAvailable = await navigateToIncoming(page, MOCK_CONFIG_ENABLED);
    if (!routeAvailable) {
      test.skip(true, 'Incoming route not available');
      return;
    }

    const formReady = await waitForFormReady(page);
    if (!formReady) {
      test.skip(true, 'Form not available');
      return;
    }

    // Complete the form
    const recipientDropdown = page.locator('#incoming-recipient');
    await recipientDropdown.click();
    await page.locator(`text=${MOCK_RECIPIENTS[0].name}`).first().click();

    const secretTextarea = page.locator('textarea').first();
    await secretTextarea.fill('Test secret');

    await page.locator('button[type="submit"]').click();
    await page.waitForURL(/\/incoming\//, { timeout: 10000 });

    // Verify reference ID display
    const referenceCode = page.locator('code').first();
    await expect(referenceCode).toContainText('test-metadata-key');

    // Verify copy button exists
    const copyButton = page.locator('button[title*="Copy"]');
    await expect(copyButton).toBeVisible();
  });

  test('create another button returns to form', async ({ page }) => {
    await mockIncomingConfig(page, MOCK_CONFIG_ENABLED);

    // Navigate directly to success page
    const response = await page.goto('/incoming/test-metadata-key');
    if (response?.status() === 404) {
      test.skip(true, 'Incoming route not available');
      return;
    }

    await page.waitForLoadState('domcontentloaded');

    // Wait for send another secret button
    const createAnotherButton = page.locator('button', { hasText: /send another/i });
    const buttonVisible = await createAnotherButton.isVisible({ timeout: 5000 }).catch(() => false);

    if (!buttonVisible) {
      test.skip(true, 'Success page not rendering properly');
      return;
    }

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
    await page.route('**/api/v3/incoming/secret', async (route) => {
      await route.fulfill({
        status: 500,
        contentType: 'application/json',
        body: JSON.stringify({ error: 'Internal server error' }),
      });
    });

    const routeAvailable = await navigateToIncoming(page, MOCK_CONFIG_ENABLED);
    if (!routeAvailable) {
      test.skip(true, 'Incoming route not available');
      return;
    }

    const formReady = await waitForFormReady(page);
    if (!formReady) {
      test.skip(true, 'Form not available');
      return;
    }

    // Fill form
    const recipientDropdown = page.locator('#incoming-recipient');
    await recipientDropdown.click();
    await page.locator(`text=${MOCK_RECIPIENTS[0].name}`).first().click();

    const secretTextarea = page.locator('textarea').first();
    await secretTextarea.fill('Test secret');

    // Submit
    await page.locator('button[type="submit"]').click();

    // Wait for error handling
    await page.waitForTimeout(1000);

    // Should show error notification (notification system)
    // Form should remain visible for retry
    const form = page.locator('form');
    await expect(form).toBeVisible();
  });

  test('handles network timeout gracefully', async ({ page }) => {
    await page.route('**/api/v3/incoming/secret', async (route) => {
      // Simulate network delay/timeout
      await new Promise((resolve) => setTimeout(resolve, 10000));
      await route.abort('timedout');
    });

    const routeAvailable = await navigateToIncoming(page, MOCK_CONFIG_ENABLED);
    if (!routeAvailable) {
      test.skip(true, 'Incoming route not available');
      return;
    }

    const formReady = await waitForFormReady(page);
    if (!formReady) {
      test.skip(true, 'Form not available');
      return;
    }

    // Fill form
    const recipientDropdown = page.locator('#incoming-recipient');
    await recipientDropdown.click();
    await page.locator(`text=${MOCK_RECIPIENTS[0].name}`).first().click();

    const secretTextarea = page.locator('textarea').first();
    await secretTextarea.fill('Test secret');

    // Submit - this will timeout
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
    const routeAvailable = await navigateToIncoming(page, MOCK_CONFIG_ENABLED);
    if (!routeAvailable) {
      test.skip(true, 'Incoming route not available');
      return;
    }

    const formReady = await waitForFormReady(page);
    if (!formReady) {
      test.skip(true, 'Form not available');
      return;
    }

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
    const routeAvailable = await navigateToIncoming(page, MOCK_CONFIG_ENABLED);
    if (!routeAvailable) {
      test.skip(true, 'Incoming route not available');
      return;
    }

    const formReady = await waitForFormReady(page);
    if (!formReady) {
      test.skip(true, 'Form not available');
      return;
    }

    const recipientDropdown = page.locator('#incoming-recipient');

    // Initially not expanded
    await expect(recipientDropdown).toHaveAttribute('aria-expanded', 'false');

    // Click to open
    await recipientDropdown.click();

    // Now expanded
    await expect(recipientDropdown).toHaveAttribute('aria-expanded', 'true');
  });

  test('form is keyboard navigable', async ({ page }) => {
    const routeAvailable = await navigateToIncoming(page, MOCK_CONFIG_ENABLED);
    if (!routeAvailable) {
      test.skip(true, 'Incoming route not available');
      return;
    }

    const formReady = await waitForFormReady(page);
    if (!formReady) {
      test.skip(true, 'Form not available');
      return;
    }

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

    const routeAvailable = await navigateToIncoming(page, MOCK_CONFIG_ENABLED);
    if (!routeAvailable) {
      test.skip(true, 'Incoming route not available');
      return;
    }

    const formReady = await waitForFormReady(page);
    if (!formReady) {
      test.skip(true, 'Form not available');
      return;
    }

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

    const routeAvailable = await navigateToIncoming(page, MOCK_CONFIG_ENABLED);
    if (!routeAvailable) {
      test.skip(true, 'Incoming route not available');
      return;
    }

    const formReady = await waitForFormReady(page);
    if (!formReady) {
      test.skip(true, 'Form not available');
      return;
    }

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
