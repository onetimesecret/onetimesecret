import { test, expect } from '@playwright/test';

test.beforeEach(async ({ page }) => {
  // See dotenv.config in playwright.config.ts, BASE_URL
  await page.goto('/');
});

// Get email address from env var
const EMAIL = process.env.TEST_ACCOUNT1_EMAIL;
const PASSPHRASE = process.env.TEST_ACCOUNT1_PW;
const BASE_URL = process.env.BASE_URL || '';

test.describe('Sign up and verify account', () => {

  test('should allow me to create an account', async ({ page, browser }) => {
    const uniqueDate = formattedDate();
    const browserName = browser.browserType().name();
    const emailUnique = `playwright+${uniqueDate}+${browserName}@solutious.com`;
    const passwordVal = PASSPHRASE || 'zoomies';

    console.log(`Email: ${emailUnique}`);

    await page.goto(BASE_URL);
    await expect(page.getByRole('link', { name: 'Create Account' })).toBeVisible();
    await expect(page.getByRole('navigation')).toContainText('Create Account');
    await page.getByRole('link', { name: 'Create Account' }).click();
    await expect(page.getByRole('heading', { name: 'Custom Domains' })).toBeVisible();
    await expect(page.locator('h4')).toContainText('Custom Domains');
    await page.getByRole('link', { name: 'Get Started' }).click();
    await page.getByRole('radio', { name: 'Yearly' }).click();
    await page.getByRole('radio', { name: 'Monthly' }).click();
    await expect(page.getByRole('main')).toContainText('$35');
    await page.getByRole('radio', { name: 'Yearly' }).click();
    await expect(page.getByRole('main')).toContainText('$365');
    await page.getByRole('link', { name: 'Get Started for Free' }).click();
    await expect(page.getByPlaceholder('e.g. tom@myspace.com')).toBeVisible();
    await page.getByPlaceholder('e.g. tom@myspace.com').click();
    await page.getByPlaceholder('e.g. tom@myspace.com').fill(emailUnique);
    await page.getByPlaceholder('e.g. tom@myspace.com').press('Tab');
    await page.getByPlaceholder('Enter your password').fill(passwordVal);
    await page.getByPlaceholder('Enter your password').press('Tab');
    await page.getByPlaceholder('Confirm your password').fill(passwordVal);
    await page.getByRole('button', { name: 'Create Account' }).click();
    await expect(page.getByText('A verification was sent to')).toBeVisible();


    // Step 1: Create a new tab
    const newPage = await page.context().newPage();

    // Step 2: Navigate to the desired URL in the new tab
    await newPage.goto('http://127.0.0.1:8025/'); // Mailpit

    await expect(newPage.getByRole('link', { name: 'MailpitMailpit' })).toBeVisible();
    await expect(newPage.locator('#message-page')).toContainText('Verify your Onetime Secret account');
    await newPage.getByRole('link', { name: `support@onetimesecret.com To: ${emailUnique} Verify your Onetime Secret` }).click();
    await expect(newPage.locator('#preview-html').contentFrame().locator('body')).toContainText('Please verify your account');


    await newPage.getByRole('tab', { name: 'Link Check' }).click();
    await newPage.getByRole('button', { name: ' Check message links' }).click();


    // Step 1: Locate the li element that contains the link
    const liElement = await newPage.locator('li').filter({ hasText: '/secret/' });

    // Step 2: Find the a tag within the li
    const linkText = await liElement.innerText()

    // Step 4: Copy the href value (you can use it as needed)
    console.log(`Found link: ${linkText}`);

    await page.goto(linkText);

    await expect(page.locator('form')).toContainText('Click to reveal →');
    await expect(page.getByRole('button', { name: 'Click to reveal →' })).toBeVisible();
    await page.getByRole('button', { name: 'Click to reveal →' }).click();
    await page.getByRole('textbox').click();
    await expect(page.getByRole('textbox')).toBeVisible();
    await expect(page.getByRole('main')).toContainText('Log in to your account');
    await page.getByRole('link', { name: 'Log in to your account' }).click();
    await page.getByPlaceholder('e.g. tom@myspace.com').fill(emailUnique);
        await page.getByPlaceholder('e.g. tom@myspace.com').press('Tab');
        await page.getByPlaceholder('Enter your password').fill(passwordVal);

await page.getByLabel('Remember me').check();
await page.getByRole('button', { name: 'Sign In' }).click();
await expect(page.getByRole('list')).toContainText('Recent Secrets');
//
//    const navLinkLocator = await navCheckLocator.locator('li').nth(1)
//
//await navLinkLocator.click();
//
//await page.getByRole('tab', { name: 'Link Check' }).click();
//await page.getByRole('button', { name: ' Check message links' }).click();
//await expect().toContainText('https://dev.onetimesecret.com/secret/30kieslpw0m6zb8140lbiax9sr428uw');
//    // Navigate to the link
//    const href = await linkLocator.getAttribute('href');
//    if (href) {
//      await page.goto(href);
//    } else {
//      throw new Error('Failed to get href attribute from the link');
//    }
  });
});

/**
 * Generates the current date and time in the format YYYYMMDD-HHMMSS without spaces.
 *
 * @returns {string} The formatted date and time string.
 */
const formattedDate = (() => {
  return new Date().toISOString() // Get the current date and time in ISO format.
      .replace(/[-:T]/g, '') // Remove dashes, colons, and the 'T' character.
      .replace(/\.\d{3}Z$/, '') // Remove the milliseconds and 'Z' character.
      .slice(0, 15); // Trim the string to include only the first 15 characters (YYYYMMDDHHMMSS).
});
