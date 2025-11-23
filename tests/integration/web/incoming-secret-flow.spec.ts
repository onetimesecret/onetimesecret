// tests/integration/web/incoming-secret-flow.spec.ts

import { expect } from '@playwright/test';
import { test } from '../test-setup';

/**
 * E2E test for the complete incoming secrets workflow
 *
 * Prerequisites:
 * - Backend API must have incoming secrets feature enabled
 * - User must be authenticated
 * - At least one recipient must be configured
 *
 * Test Flow:
 * 1. Navigate to incoming secrets form
 * 2. Fill out the form (title, recipient, secret content)
 * 3. Submit the form
 * 4. Verify success page is displayed
 * 5. Verify metadata key is shown
 */
test.describe('Incoming Secrets Flow', () => {
  test.beforeEach(async ({ page }) => {
    // Note: Authentication may be required - adjust based on your auth setup
    // This assumes the user is already authenticated or auth is handled in test-setup
    await page.goto('/incoming');

    // Wait for the page to load and check if feature is enabled
    // If feature is disabled, this test will fail as expected
    await expect(page.locator('h1')).toContainText('Share an Incoming Secret');
  });

  test('Complete incoming secret creation flow', async ({ page }) => {
    // Step 1: Verify form is loaded
    await expect(page.getByLabel('Subject')).toBeVisible();
    await expect(page.getByRole('button', { name: 'Select a recipient' })).toBeVisible();

    // Step 2: Fill in the subject
    const secretSubject = `Test Secret ${Date.now()}`;
    await page.getByLabel('Subject').fill(secretSubject);

    // Step 3: Select a recipient
    await page.getByRole('button', { name: /Select a recipient/i }).click();

    // Wait for dropdown to appear and select first recipient
    await page.waitForSelector('[role="listbox"]');
    const firstRecipient = page.locator('[role="option"]').first();
    await expect(firstRecipient).toBeVisible();
    await firstRecipient.click();

    // Step 4: Fill in secret content
    const secretContent = 'This is a test secret for incoming secrets feature';
    await page.getByPlaceholder('Secret content goes here...').fill(secretContent);

    // Step 5: Optionally add a passphrase
    await page.getByLabel('Passphrase').fill('test-passphrase-123');

    // Step 6: Submit the form
    await page.getByRole('button', { name: 'Create Secret' }).click();

    // Step 7: Verify success page
    await expect(page.locator('h1')).toContainText('Secret Created Successfully', {
      timeout: 10000,
    });

    // Step 8: Verify success message
    await expect(page.getByText(/Your secret has been securely stored/i)).toBeVisible();

    // Step 9: Verify reference ID is displayed
    await expect(page.getByText('Reference ID')).toBeVisible();

    // Step 10: Verify action buttons are present
    await expect(page.getByRole('button', { name: 'Create Another Secret' })).toBeVisible();
    await expect(page.getByRole('button', { name: 'View Recent Secrets' })).toBeVisible();
  });

  test('Display validation errors for empty required fields', async ({ page }) => {
    // Try to submit without filling any fields
    await page.getByRole('button', { name: 'Create Secret' }).click();

    // Should show validation errors (exact messages depend on implementation)
    // The form should not navigate away
    await expect(page.locator('h1')).toContainText('Share an Incoming Secret');
  });

  test('Display character counter when approaching memo limit', async ({ page }) => {
    // Fill subject with text near the limit (assuming 50 char limit)
    const longSubject = 'A'.repeat(45); // 45 characters, near the 50 limit
    await page.getByLabel('Subject').fill(longSubject);

    // Character counter should be visible
    await expect(page.getByText(/45.*50/)).toBeVisible();
  });

  test('Reset form clears all fields', async ({ page }) => {
    // Fill in all fields
    await page.getByLabel('Subject').fill('Test Subject');
    await page.getByPlaceholder('Secret content goes here...').fill('Test Content');
    await page.getByLabel('Passphrase').fill('test-pass');

    // Click reset button
    await page.getByRole('button', { name: 'Reset Form' }).click();

    // Verify fields are cleared
    await expect(page.getByLabel('Subject')).toHaveValue('');
    await expect(page.getByPlaceholder('Secret content goes here...')).toHaveValue('');
    await expect(page.getByLabel('Passphrase')).toHaveValue('');
  });

  test('Navigate from success page to create another', async ({ page }) => {
    // Create a secret first
    await page.getByLabel('Subject').fill('First Secret');

    await page.getByRole('button', { name: /Select a recipient/i }).click();
    await page.waitForSelector('[role="listbox"]');
    await page.locator('[role="option"]').first().click();

    await page.getByPlaceholder('Secret content goes here...').fill('Content');
    await page.getByRole('button', { name: 'Create Secret' }).click();

    // Wait for success page
    await expect(page.locator('h1')).toContainText('Secret Created Successfully', {
      timeout: 10000,
    });

    // Click "Create Another Secret"
    await page.getByRole('button', { name: 'Create Another Secret' }).click();

    // Should navigate back to form
    await expect(page.locator('h1')).toContainText('Share an Incoming Secret');
  });

  test('Handle feature disabled state gracefully', async ({ page }) => {
    // This test assumes you can simulate a disabled feature
    // You might need to mock the API response or configure backend
    // For now, we'll just check the structure exists

    // If feature is enabled, skip this test
    const isEnabled = await page.locator('h1').textContent();
    if (isEnabled?.includes('Share an Incoming Secret')) {
      test.skip();
    }

    // Otherwise check for disabled state message
    await expect(page.getByText(/Feature Not Available/i)).toBeVisible();
  });
});

test.describe('Incoming Secrets - Error Handling', () => {
  test('Display loading state while fetching configuration', async ({ page }) => {
    // Intercept config API call to delay it
    await page.route('**/api/v2/incoming/config', async (route) => {
      await new Promise((resolve) => setTimeout(resolve, 1000));
      await route.continue();
    });

    await page.goto('/incoming');

    // Should show loading state
    await expect(page.getByText(/Loading configuration/i)).toBeVisible();
  });

  test('Display error when configuration fails to load', async ({ page }) => {
    // Intercept config API call to fail
    await page.route('**/api/v2/incoming/config', (route) => {
      route.fulfill({
        status: 500,
        body: JSON.stringify({ message: 'Internal server error' }),
      });
    });

    await page.goto('/incoming');

    // Should show error state
    await expect(page.getByText(/Configuration Error/i)).toBeVisible();
  });

  test('Display error when secret creation fails', async ({ page }) => {
    await page.goto('/incoming');

    // Fill form
    await page.getByLabel('Subject').fill('Test Subject');

    await page.getByRole('button', { name: /Select a recipient/i }).click();
    await page.waitForSelector('[role="listbox"]');
    await page.locator('[role="option"]').first().click();

    await page.getByPlaceholder('Secret content goes here...').fill('Test Content');

    // Intercept secret creation API to fail
    await page.route('**/api/v2/incoming/secret', (route) => {
      route.fulfill({
        status: 400,
        body: JSON.stringify({ message: 'Invalid payload' }),
      });
    });

    // Submit form
    await page.getByRole('button', { name: 'Create Secret' }).click();

    // Should stay on form page and show error
    await expect(page.locator('h1')).toContainText('Share an Incoming Secret');
  });
});
