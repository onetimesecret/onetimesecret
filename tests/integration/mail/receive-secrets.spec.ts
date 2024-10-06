import { test, expect } from '@playwright/test';

/**
 * The page.evaluate() API can run a JavaScript function in the context of the web page and bring results back to the Playwright environment. Browser globals like window and document can be used in evaluate.
 *
 *  const href = await page.evaluate(() => document.location.href);
 *
 *  // Or if the result is a promise
 *  const status = await page.evaluate(async () => {
 *    const response = await fetch(location.href);
 *    return response.status;
 *  });
 *
 *  const data = 'some data';
 *  // Pass |data| as a parameter.
 *  const result = await page.evaluate(data => {
 *    window.myApp.use(data);
 *  }, data);
 *
 * Running initialization scripts:
 *
 * First, create a preload.js file that contains the mock.
 *
 * // preload.js
 * Math.random = () => 42;
 *
 * Next, add init script to the page.
 *
 * import { test, expect } from '@playwright/test';
 * import path from 'path';
 *
 * test.beforeEach(async ({ page }) => {
 *   // Add script for every test in the beforeEach hook.
 *   // Make sure to correctly resolve the script path.
 *   await page.addInitScript({ path: path.resolve(__dirname, '../mocks/preload.js') });
 * });
 *
 * Alternatively, you can pass a function instead of creating a preload script file. This is more convenient for short or one-off scripts. You can also pass an argument this way.
 *
 * import { test, expect } from '@playwright/test';
 *
 * // Add script for every test in the beforeEach hook.
 * test.beforeEach(async ({ page }) => {
 *   const value = 42;
 *   await page.addInitScript(value => {
 *     Math.random = () => value;
 *   }, value);
 * });
 *
 */

test('test secrets', async ({ browser }) => {
  // Launch a new browser instance
  const context = await browser.newContext();

  // Create a new page in the context
  const pageCreate = await context.newPage();

  await pageCreate.goto('https://dev.onetimesecret.com/');
  await pageCreate.getByPlaceholder('Secret content goes here...').click();
  await pageCreate.keyboard.type('Hello, World!');
  await pageCreate.getByText('Create a secret link').click();
  await pageCreate.getByRole('link', { name: 'Sign In' }).click();
  await pageCreate.getByPlaceholder('e.g. tom@myspace.com').click();
  await pageCreate.getByPlaceholder('e.g. tom@myspace.com').fill('delbo@solutious.com');
  await pageCreate.getByPlaceholder('e.g. tom@myspace.com').press('Tab');
  await pageCreate.getByPlaceholder('Enter your password').fill('123456');
  await pageCreate.getByText('Rembember me').click();
  await pageCreate.getByRole('button', { name: 'Sign In' }).click();
  await pageCreate.getByRole('link', { name: 'Logo', exact: true }).click();
  await pageCreate.getByPlaceholder('Secret content goes here...').fill('Secret to email');
  await pageCreate.getByText('Link Preview').click();
  await pageCreate.locator('div').filter({ hasText: /^Privacy Options$/ }).first().click();
  await pageCreate.getByLabel('Lifetime:').selectOption('1800.0');
  await pageCreate.getByPlaceholder('Enter a passphrase').click();
  await pageCreate.getByPlaceholder('Enter a passphrase').fill('123');
  await pageCreate.getByPlaceholder('tom@myspace.com').click();
  await pageCreate.getByPlaceholder('tom@myspace.com').fill('deltaburke@solutious.com');
  await pageCreate.getByPlaceholder('tom@myspace.com').press('Enter');
  await pageCreate.getByLabel('Create a secret link').click();

  const page1 = await context.newPage();
  await page1.goto('http://localhost:8025/');
  await page1.getByRole('link', { name: 'support@onetimesecret.com To' }).click();
  await expect(page1.getByRole('strong')).toContainText('delbo@solutious.com sent you a secret');
  await expect(page1.getByRole('rowgroup')).toContainText('delbo@solutious.com');
  await expect(page1.getByRole('rowgroup')).toContainText('deltaburke@solutious.com');
  await page1.getByRole('link', { name: 'support@onetimesecret.com' }).click();
  await expect(page1.getByRole('rowgroup')).toContainText('support@onetimesecret.com');
  await expect(page1.locator('#preview-html').contentFrame().locator('body')).toContainText('We have a secret for you from delbo@solutious.com:');
  await page1.locator('#message-view div').filter({ hasText: 'From <support@onetimesecret.' }).nth(1).click();
  await page1.locator('#MessageList').click();
  const page2Promise = page1.waitForEvent('popup');
    await page1.locator('#preview-html').contentFrame().getByRole('link', { name: 'https://another.subdomain.' }).click();
    const page2 = await page2Promise;
});
