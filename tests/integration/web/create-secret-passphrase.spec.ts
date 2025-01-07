// @ts-check
import { test, expect } from '@playwright/test';

test.beforeEach(async ({ page }) => {
  // See dotenv.config in playwright.config.ts, BASE_URL
  await page.goto('/');
});

const SECRET_CONTENT = 'feed the cat';
const PASSPHRASE = '$J9jtg(jJQvk'; // nosec

test.describe('Create secret', () => {
  test('should allow me to add a passphrase', async ({ page }) => {
    // create a new secret
    await page.getByLabel('Enter the secret content to share here').click()
    //await page.getByPlaceholder('Secret content goes here...').click();

    await page.getByLabel('Enter the secret content to share here').fill(SECRET_CONTENT);
    await page.locator('div').filter({ hasText: /^Privacy Options$/ }).nth(1).click();
    await expect(page.locator('#createSecret')).toContainText('Privacy Options');
    await expect(page.getByText('Privacy Options')).toBeVisible();
    await expect(page.getByPlaceholder('Enter a passphrase')).toBeVisible();
    await expect(page.getByLabel('Lifetime:')).toBeVisible();
    await page.getByLabel('Lifetime:').selectOption('259200.0');
    await page.getByLabel('Lifetime:').selectOption('300.0');
    await expect(page.getByLabel('Create a secret link')).toContainText('Create a secret link*');
    await page.getByPlaceholder('Enter a passphrase').click();
    await page.getByPlaceholder('Enter a passphrase').fill(SECRET_CONTENT);
    await page.getByLabel('Create a secret link').click();
    await expect(page.locator('#secreturi')).toBeVisible();
    await expect(page.getByText('Requires a passphrase.')).toBeVisible();
    await expect(page.getByText('Expires in 5 minutes.')).toBeVisible();
    await expect(page.getByRole('main')).toContainText('Requires a passphrase');
    await expect(page.getByRole('strong')).toContainText('Expires in 5 minutes');
    await expect(page.getByRole('link', { name: 'Burn this secret' })).toBeVisible();

    // Get the value of the input element with the locator #secreturi
    const link = await page.locator('#secreturi').inputValue();

    // Use the link for further testing
    console.log('Generated link:', link);

    await page.goto(link);

    await expect(page.getByRole('heading', { name: 'This message requires a' })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Click to reveal →' })).toBeVisible();
    await expect(page.getByPlaceholder('Enter the passphrase here')).toBeVisible();
    await expect(page.getByRole('main')).toContainText('This message requires a passphrase');
    await expect(page.getByRole('main')).toContainText('Careful: we will only show it once');
    await page.getByPlaceholder('Enter the passphrase here').click();
    await page.getByPlaceholder('Enter the passphrase here').fill(SECRET_CONTENT);
    await page.getByRole('button', { name: 'Click to reveal →' }).click();
    await expect(page.getByRole('heading', { name: 'This message is for you:' })).toBeVisible();
    await expect(page.getByRole('textbox')).toBeVisible();
    await expect(page.getByRole('link', { name: 'Powered by Onetime Secret' })).toBeVisible();
    await expect(page.getByRole('link')).toContainText('Powered by Onetime Secret');

    const content = await page.getByRole('textbox').inputValue();
    await expect(content).toBe(SECRET_CONTENT);
  });
});
