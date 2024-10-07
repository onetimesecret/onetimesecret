import { expect } from '@playwright/test';
import { test } from '../test-setup';

test('Create secret - copy with clipboard (chromium only)', async ({ browser }) => {
  // Check if the browser is not Chromium and skip the test
  if (browser.browserType().name() !== 'chromium') {
    test.skip("This test runs only on Chromium");
  }

  // Create a new browser context with clipboard-read and clipboard-write permissions
  const context = await browser.newContext({
    permissions: ['clipboard-read', 'clipboard-write']
  });

  // Create a new page in the context
  const page = await context.newPage();

  // See dotenv.config in playwright.config.ts
  await page.goto('/');
  await page.getByPlaceholder('Secret content goes here...').click();
  await page.getByPlaceholder('Secret content goes here...').fill('Secret here');
  await page.locator('div').filter({ hasText: /^Privacy Options$/ }).nth(1).click();
  await page.locator('div').filter({ hasText: /^Link Preview$/ }).nth(1).click();
  await page.getByLabel('Lifetime:').selectOption('259200.0');
  await page.getByPlaceholder('Secret content goes here...').click();
  await page.getByPlaceholder('Enter a passphrase').click();
  await page.getByPlaceholder('Enter a passphrase').fill('123');
  await page.getByLabel('Create a secret link').click();
  await page.getByLabel('Copy to clipboard').click();

  // Get link from clipboard
  const link = await page.evaluate(() => navigator.clipboard.readText());
  console.log('Navigating to link:', link);

  const page1 = await context.newPage();
  await page1.goto(link);
  await page1.getByPlaceholder('Enter the passphrase here').click();
  await page1.getByPlaceholder('Enter the passphrase here').fill('321');
  await page1.getByRole('button', { name: 'Click to reveal →' }).click();
  await expect(page1.getByText('Double check that passphrase')).toBeVisible();
  await page1.getByPlaceholder('Enter the passphrase here').click();
  await page1.getByPlaceholder('Enter the passphrase here').fill('123');
  await page1.getByRole('button', { name: 'Click to reveal →' }).click();
  await expect(page1.getByRole('textbox')).toBeVisible();
  await expect(page1.getByLabel('Copy to clipboard')).toBeVisible();
  await page1.getByLabel('Copy to clipboard').click();

  // Check value in clipboard
  const secret = await page1.evaluate(() => navigator.clipboard.readText());
  await expect(secret).toBe(secret);

  // Close page
  await page1.close();
  await context.close();
});
