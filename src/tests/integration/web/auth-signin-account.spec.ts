import { test, expect } from '@playwright/test';

test.beforeEach(async ({ page }) => {
  // See dotenv.config in playwright.config.ts, BASE_URL
  await page.goto('/');
});

// Get email address from env var
const EMAIL = process.env.TEST_ACCOUNT2_EMAIL || '';
const PW = process.env.TEST_ACCOUNT2_PW || '';

test.describe('Sign in and check account', () => {

  test('should allow me to sign in and generate an API key', async ({ page }) => {

    await expect(page.getByRole('heading', { name: 'Paste a password, secret' })).toBeVisible();
    await expect(page.getByRole('link', { name: 'Logo' })).toBeVisible();
    await expect(page.getByRole('link', { name: 'Sign In' })).toBeVisible();
    await expect(page.getByRole('link', { name: 'Create Account' })).toBeVisible();
    await expect(page.getByPlaceholder('Share your thoughts, ideas, or experiences...')).toBeVisible();
    await expect(page.getByRole('button', { name: 'Send Feedback' })).toBeVisible();
    await expect(page.getByPlaceholder('Secret content goes here...')).toBeVisible();
    //await expect(page.getByText('v0.18.0-alpha (9b51e336)')).toBeVisible();
    await expect(page.getByLabel('Toggle dark mode')).toBeVisible();
    await expect(page.getByRole('button', { name: 'en', exact: true })).toBeVisible();
    await expect(page.getByRole('navigation')).toContainText('Sign In');
    await expect(page.getByRole('navigation')).toContainText('About');
    await expect(page.getByRole('navigation')).toContainText('Create Account');
    await expect(page.getByRole('contentinfo')).toContainText('Send Feedback');
    await page.getByRole('link', { name: 'Sign In' }).click();
    await expect(page.getByPlaceholder('e.g. tom@myspace.com')).toBeVisible();
    await expect(page.getByRole('button', { name: 'Sign In' })).toBeVisible();
    await expect(page.getByLabel('Sign In')).toContainText('Enter your credentials');
    await expect(page.getByRole('group')).toContainText('Remember me');
    await expect(page.getByLabel('Sign Up')).toContainText('Need an account?');
    await expect(page.getByLabel('Forgot Password')).toContainText('Forgot your password?');
    await page.getByPlaceholder('e.g. tom@myspace.com').click();
    await page.getByPlaceholder('e.g. tom@myspace.com').fill(EMAIL);
    await page.getByPlaceholder('e.g. tom@myspace.com').press('Tab');
    await page.getByPlaceholder('Enter your password').fill(PW);
    await page.getByPlaceholder('Enter your password').press('Enter');
    // https://dev.onetimesecret.com/colonel/
    await page.getByRole('link', { name: 'Logo', exact: true }).click();
    // https://dev.onetimesecret.com/dashboard

    await expect(page.getByRole('link', { name: EMAIL })).toBeVisible();
    await expect(page.locator('#userEmail')).toContainText(EMAIL);
    await page.getByRole('link', { name: 'Account' }).click();
    await expect(page.getByText('API Key')).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Your Account' })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Update Password' })).toBeVisible();
    await expect(page.getByText('Delete Account', { exact: true })).toBeVisible();
    await expect(page.locator('h1')).toContainText('Your Account');
    await expect(page.getByRole('main')).toContainText('API Key');
    await expect(page.getByRole('main')).toContainText('Update Password');
    await expect(page.getByRole('main')).toContainText('Delete Account');

    const spanElement = page.locator('span.break-all.pr-10');
    const apiKeyButtonElement = page.getByRole('button', { name: 'Generate Token' });
    const apiKeyBefore = await spanElement.innerText();

    await expect(spanElement).toBeVisible();
    await expect(apiKeyButtonElement).toBeVisible();

    await apiKeyButtonElement.click();
    await expect(page.getByRole('main')).toContainText('Token generated');

    const apiKeyAfter = await spanElement.innerText();

    await expect(apiKeyBefore).not.toBe(apiKeyAfter);

  });

});
