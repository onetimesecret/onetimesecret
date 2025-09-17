import { defineConfig, devices } from '@playwright/test';

/**
 * Playwright configuration for E2E integration testing
 * This config runs tests against production builds and containers
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
    // ['html', { outputFolder: 'playwright-report' }],
    // ['github'], // GitHub Actions annotations
    ['line'], // Terminal output
  ],

  /* Shared settings for all the projects below. */
  use: {
    /* Base URL - will be set by environment variable */
    baseURL:
      process.env.PLAYWRIGHT_BASE_URL ||
      process.env.FRONTEND_HOST ||
      (() => {
        throw new Error(
          'No base URL configured. Set PLAYWRIGHT_BASE_URL or FRONTEND_HOST environment variable.'
        );
      })(),

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
  globalTimeout: 10 * 60 * 1000, // 15 minutes

  /* Expect timeout for assertions */
  expect: {
    timeout: 5000,
  },

  /* Output directory for test artifacts */
  outputDir: 'test-results/',

  /* Don't configure webServer - we're testing against already running applications */
  webServer: undefined,
});
