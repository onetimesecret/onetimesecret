// src/tests/e2e/playwright.config.ts

import { defineConfig, devices } from '@playwright/test';

// Default local server URL (Ruby backend with built assets)
const DEFAULT_LOCAL_URL = 'http://localhost:7143';

/**
 * Playwright configuration for E2E integration testing
 *
 * Usage:
 *   # Auto-start local server (requires `pnpm run build` first)
 *   pnpm playwright test --config=src/tests/e2e/playwright.config.ts
 *
 *   # Test against external URL (skips local server)
 *   PLAYWRIGHT_BASE_URL=http://localhost:7143 pnpm test:playwright
 */
export default defineConfig({
  // Test directory relative to this config file
  testDir: './',

  // Look for test files in current directory and subdirectories
  testMatch: ['**/*.spec.ts'],

  /* Run tests in files in parallel */
  fullyParallel: false, // Disabled for integration testing to avoid resource conflicts

  /* Fail the build on CI if you accidentally left test.only in the source code. */
  forbidOnly: !!process.env.CI,

  /* Retry on CI only */
  retries: process.env.CI ? 2 : 0,

  /* Opt out of parallel tests on CI. */
  workers: process.env.CI ? 1 : undefined,

  /* Reporter to use. */
  reporter: [
    ['html', { outputFolder: 'playwright-report' }],
    ['github'], // GitHub Actions annotations
    ['line'], // Terminal output
  ],

  /* Shared settings for all the projects below. */
  use: {
    /* Base URL - uses PLAYWRIGHT_BASE_URL if set, otherwise defaults to local server */
    baseURL: process.env.PLAYWRIGHT_BASE_URL || DEFAULT_LOCAL_URL,

    /* Collect trace when retrying the failed test. See https://playwright.dev/docs/trace-viewer */
    trace: 'on-first-retry',

    /* Screenshot on failure */
    screenshot: 'only-on-failure',

    /* Video recording */
    video: 'retain-on-failure',

    /* Ignore HTTPS errors */
    ignoreHTTPSErrors: false,

    /* Global timeout for each action (e.g., click, fill) */
    actionTimeout: 5000,

    /* Global timeout for navigation actions */
    navigationTimeout: 15000,
  },

  /* Configure projects for major browsers */
  projects: [
    {
      name: 'chromium',
      use: {
        ...devices['Desktop Chrome'],
        // Extra time for container responses
        actionTimeout: 30000,
      },
    },

    // Optionally add more browsers for comprehensive testing
    // Uncomment if needed for broader browser coverage
    // {
    //   name: 'firefox',
    //   use: { ...devices['Desktop Firefox'] },
    // },
    // {
    //   name: 'webkit',
    //   use: { ...devices['Desktop Safari'] },
    // },
  ],

  /* Timeout for entire test suite */
  timeout: 60000,

  /* Global timeout for entire test run */
  globalTimeout: 10 * 60 * 1000, // 10 minutes

  /* Expect timeout for assertions */
  expect: {
    timeout: 5000,
  },

  /* Output directory for test artifacts */
  outputDir: 'test-results/',

  /* Auto-start Ruby server when no external URL is provided.
   * Requires `pnpm run build` first to generate frontend assets.
   * Set PLAYWRIGHT_BASE_URL to skip auto-start and test against external server. */
  webServer: process.env.PLAYWRIGHT_BASE_URL
    ? undefined // External URL provided - don't start local server
    : {
        command: 'RACK_ENV=production bin/ots server',
        cwd: '../../../', // Project root relative to this config
        url: DEFAULT_LOCAL_URL,
        reuseExistingServer: !process.env.CI,
        timeout: 30000,
        stdout: 'pipe',
        stderr: 'pipe',
      },
});
