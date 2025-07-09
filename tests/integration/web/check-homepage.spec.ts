import { expect, test } from '@playwright/test';

test.beforeEach(async ({ page }) => {
  // See dotenv.config in playwright.config.ts, BASE_URL
  await page.goto('/');
});

//test.afterAll(async ({ page, browser, context }) => {
//  // Close browser
//  await browser.close();
//
//});

// Get email address from env var
const EMAIL = process.env.TEST_ACCOUNT1_EMAIL;
const PASSPHRASE = process.env.TEST_ACCOUNT1_PW;

test.describe('View the homepage anonymously', () => {
  test('should have marketing copy', async ({ page }) => {
    const main = page.locator('main');

    // "Paste a password" heading
    const pastePasswordHeading = main.locator('h3.font-base');
    console.log('Checking for heading', pastePasswordHeading);
    await expect(pastePasswordHeading).toHaveText(
      /Paste a password, secret message or private link below/
    );
    await expect(pastePasswordHeading).toBeVisible();

    // "Keep sensitive" paragraph
    const keepSensitiveParagraph = main.locator('p.text-base.text-gray-400');
    await expect(keepSensitiveParagraph).toHaveText(
      /Keep sensitive info out of your email and chat logs/
    );
    await expect(keepSensitiveParagraph).toBeVisible();

    // Link preview section
    const linkPreview = main.locator('div[class*="border-dashed"]');
    await expect(linkPreview).toHaveText(/Link Preview/);
    await expect(linkPreview).toBeVisible();

    // Privacy options section
    const privacyOptions = main.locator('div[class*="border-gray-300"]').nth(1);
    await expect(privacyOptions).toHaveText(/Privacy Options/);
    await expect(privacyOptions).toBeVisible();

    // Generate button
    const generateButton = main.locator('button[name="kind"][value="generate"]');
    await expect(generateButton).toHaveText(/Generate/);
    await expect(generateButton).toBeVisible();

    // Create a secret button
    const createSecretButton = main.locator('button[name="kind"][value="conceal"]');
    await expect(createSecretButton).toHaveText(/Create a secret/);
    await expect(createSecretButton).toBeVisible();
  });

  test('should have logo with nav', async ({ page }) => {
    // Locator for the <a> link with the logo
    const logoLink = page.locator('header a[href="/"]');

    // Locator for the <img> element with the logo
    const logoImage = page.locator('header img#logo');

    // Check that the logo link is visible
    await expect(logoLink).toBeVisible();

    // Check that the logo link has the expected href attribute
    await expect(logoLink).toHaveAttribute('href', '/');

    // Check that the logo image is visible
    await expect(logoImage).toBeVisible();

    // Check that the logo image has the expected alt attribute
    await expect(logoImage).toHaveAttribute('alt', 'Logo');
  });

  test('should have header navigation', async ({ page }) => {
    const header = page.locator('header');

    const signInLink = header.getByRole('link', { name: 'Sign In' });
    const signUpLink = header.getByRole('link', { name: 'Create Account' });
    const aboutLink = header.getByRole('link', { name: 'About' });

    // Check that the "Sign In" link is visible and links to the correct URL
    await expect(signInLink).toBeVisible();
    await expect(signInLink).toHaveAttribute('href', '/signin');

    // Check that the "Create Account" link is visible and links to the correct URL
    await expect(signUpLink).toBeVisible();
    await expect(signUpLink).toHaveAttribute('href', '/signup');

    // Check that the "About" link is visible and links to the correct URL
    await expect(aboutLink).toBeVisible();
    await expect(aboutLink).toHaveAttribute('href', '/feedback');
  });

  test('should have secret form in default state', async ({ page }) => {
    const main = page.locator('main');
    await expect(page.getByPlaceholder('Secret content goes here...')).toBeVisible();
  });

  test('should have footer feedback form', async ({ page }) => {
    const footer = page.locator('footer');
    await expect(
      footer.getByPlaceholder('Share your thoughts, ideas, or experiences...')
    ).toBeVisible();
    await expect(footer.getByRole('button', { name: 'Send Feedback' })).toBeVisible();

    await footer.getByPlaceholder('Share your thoughts, ideas, or experiences...').click();
    await footer
      .getByPlaceholder('Share your thoughts, ideas, or experiences...')
      .fill('My feedback is!');
    await footer.getByRole('button', { name: 'Send Feedback' }).click();

    await page.goto('/');

    await footer.getByPlaceholder('Share your thoughts, ideas, or experiences...').click();
    await footer
      .getByPlaceholder('Share your thoughts, ideas, or experiences...')
      .fill('My feedback is 2');
    await footer.getByPlaceholder('Share your thoughts, ideas, or experiences...').press('Enter');
    await footer.getByPlaceholder('Share your thoughts, ideas, or experiences...').click();
    await page
      .getByPlaceholder('Share your thoughts, ideas, or experiences...')
      .fill('More feedback from the /feedback page');
    await page.getByPlaceholder('Share your thoughts, ideas, or experiences...').press('Enter');
    await expect(
      page.getByPlaceholder('Share your thoughts, ideas, or experiences...')
    ).toBeVisible();
    await expect(page.getByRole('button', { name: 'Send Feedback' })).toBeVisible();

    await expect(page.locator('body')).toContainText('Message received. Send as much as you like');
    await expect(page.getByLabel('Feedback Form')).toContainText('Give us your feedback');
    await expect(
      footer.getByPlaceholder('Share your thoughts, ideas, or experiences...')
    ).not.toBeVisible();
    await expect(footer.getByRole('button', { name: 'Send Feedback' })).not.toBeVisible();
  });
});
