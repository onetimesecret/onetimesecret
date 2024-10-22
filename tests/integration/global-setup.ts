import { chromium, FullConfig } from '@playwright/test';

// NOTE: If making changes to this file (or tests/unit/vus/setup.ts)
// and running VS Code, open and resave playwright.config.ts to
// reload the test runner.
//
// Don't include vitest or jest or any other monkey junk. This is playwright!
//import { vi } from 'vitest';
//vi.mock('axios');

global.window ??= global.window || {}

global.window.supported_locales = ['en', 'fr', 'es'];

async function globalSetup(config: FullConfig) {
  const browser = await chromium.launch();
  const page = await browser.newPage();

//  // Add your custom window attributes here
//  await page.evaluate(() => {
//    window.customAttribute1 = 'value1';
//    window.customAttribute2 = 'value2';
//
//    // Mock the window object
//    window.supported_locales = ['en', 'fr', 'es'];
//  });

  await browser.close();
}

export default globalSetup;
