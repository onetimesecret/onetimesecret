/**
 *
 * https://playwright.dev/docs/test-parameterize#parameterized-projects
 *
 *    import { test } from './test-setup';
 *
 *    test('test 1', async ({ page, person }) => {
 *      await page.goto(`/index.html`);
 *      await expect(page.locator('#node')).toContainText(person);
 *      // ...
 *    });
 */

import { test as base } from '@playwright/test';

export type TestOptions = {
  person: string;
};

export const test = base.extend<TestOptions>({
  // Define an option and provide a default value.
  // We can later override it in the config.
  person: ['Flarp', { option: true }],
});
