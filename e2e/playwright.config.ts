// e2e/playwright.config.ts

import { defineConfig, devices } from '@playwright/test';
import { existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

// Default local server URL (Ruby backend with built assets)
const DEFAULT_LOCAL_URL = 'http://localhost:7143';

// Directory containing this config file. package.json is `"type": "module"`,
// so the config loads as ESM and `__dirname` is unavailable.
const CONFIG_DIR = path.dirname(fileURLToPath(import.meta.url));

/**
 * Remote/sandboxed dev environments (e.g. Claude Code on the web) preinstall
 * Chromium at a fixed path baked into the container image, which can lag
 * behind the revision this @playwright/test version expects — the default
 * resolution then tries to download, which these environments block. Point
 * at the preinstalled binary directly when present; everywhere else (real
 * CI, local dev) this path doesn't exist and Playwright's normal
 * resolution applies unchanged.
 */
const SANDBOX_CHROMIUM = '/opt/pw-browsers/chromium';
const sandboxLaunchOptions = existsSync(SANDBOX_CHROMIUM)
  ? { executablePath: SANDBOX_CHROMIUM }
  : {};

/**
 * Authenticated session produced by global.setup.ts and consumed by the
 * `full` / `full-billing` projects via `storageState`. Absolute on purpose
 * so writer (setup script) and readers (project `use` blocks) agree on one
 * location regardless of cwd — Playwright path resolution is inconsistent
 * (e.g. the blob reporter below resolves against cwd, not the config dir).
 * The .auth/ directory is gitignored.
 */
export const STORAGE_STATE = path.join(CONFIG_DIR, '.auth', 'user.json');

/**
 * Playwright configuration for E2E integration testing
 *
 * Usage:
 *   # Auto-start local server (requires `pnpm run build` first)
 *   pnpm playwright test --config=e2e/playwright.config.ts
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

  /* Reporter to use.
   *
   * Environment-aware so nothing needs a `--reporter` CLI override (a CLI
   * override *replaces* this whole array — that's how CI lost its HTML
   * report; see e2e/docs/e2e-remediation-plan.md, Phase 1).
   *
   * CI additionally emits:
   *  - json → test-results/results.json, parsed by the workflow's flaky
   *    gate (a "passed only on retry" outcome fails the job)
   *  - blob → blob-report/, mergeable across future CI shards
   */
  reporter: process.env.CI
    ? [
        ['list'], // Terminal output (CI logs)
        ['github'], // GitHub Actions annotations
        ['html', { outputFolder: 'playwright-report', open: 'never' }],
        ['json', { outputFile: 'test-results/results.json' }],
        // Unlike the other reporters, blob's default outputDir resolves
        // against process.cwd(), not this config's directory - pin it.
        ['blob', { outputDir: 'blob-report' }],
      ]
    : [
        ['html', { outputFolder: 'playwright-report', open: 'never' }],
        ['line'], // Terminal output
      ],

  /* Shared settings for all the projects below. */
  use: {
    /* Base URL - uses PLAYWRIGHT_BASE_URL if set, otherwise defaults to local server */
    baseURL: process.env.PLAYWRIGHT_BASE_URL || DEFAULT_LOCAL_URL,

    /* See SANDBOX_CHROMIUM above - no-op outside the preinstalled sandbox. */
    launchOptions: sandboxLaunchOptions,

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

  /* Configure projects.
   *
   * Auth model (e2e/docs/e2e-remediation-plan.md, Phase 2.1):
   *  - `setup` registers/signs in the TEST_USER_* account once via the real
   *    signup + signin UI and saves the session to STORAGE_STATE.
   *  - `full` and `full-billing` depend on `setup` and start every test
   *    already authenticated via storageState.
   *  - `chromium` (all/ + auth/ suites) stays credential-free: no
   *    dependency on `setup`, no storageState.
   *
   * CLI path filters (e.g. `pnpm test:playwright e2e/all e2e/full`) select
   * which suites run; Playwright always runs dependency projects in full, so
   * `setup` only executes when a dependent project has matching tests.
   */
  projects: [
    {
      name: 'setup',
      // Overrides the top-level testMatch (which only matches *.spec.ts)
      testMatch: 'global.setup.ts',
      use: {
        ...devices['Desktop Chrome'],
        // Extra time for container responses
        actionTimeout: 30000,
      },
    },

    {
      // Credential-free suites: all/ (runs in CI) and auth/ (unauthenticated
      // signup/SSO-CSRF flows). Keep the historical project name so existing
      // `--project=chromium` invocations keep working.
      name: 'chromium',
      testIgnore: ['full/**', 'full-billing/**'],
      use: {
        ...devices['Desktop Chrome'],
        // Extra time for container responses
        actionTimeout: 30000,
      },
    },

    {
      // Authenticated suite; requires TEST_USER_EMAIL / TEST_USER_PASSWORD.
      name: 'full',
      testMatch: 'full/**/*.spec.ts',
      dependencies: ['setup'],
      use: {
        ...devices['Desktop Chrome'],
        actionTimeout: 30000,
        storageState: STORAGE_STATE,
      },
    },

    {
      // Authenticated suite + billing enabled on the target server.
      name: 'full-billing',
      testMatch: 'full-billing/**/*.spec.ts',
      dependencies: ['setup'],
      use: {
        ...devices['Desktop Chrome'],
        actionTimeout: 30000,
        storageState: STORAGE_STATE,
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

  /* Global timeout for entire test run.
   *
   * Sized for the post-Phase-2 reality: CI runs all/ + full/ (~330 tests)
   * on a single serial worker, which cannot finish inside the old 10-minute
   * budget - runs aborted at exactly 10.0m with hundreds of tests reported
   * "did not run" (observed on #3414/#3416 CI). Keep this under the
   * workflow job's timeout-minutes (30) minus ~4-5 min of container
   * build/setup overhead. Shrinking this again is a Phase 3 goal
   * (fullyParallel + more workers), not a budget to win back by hiding
   * tests. */
  globalTimeout: 20 * 60 * 1000, // 20 minutes

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
        cwd: '../', // Project root relative to this config
        url: DEFAULT_LOCAL_URL,
        reuseExistingServer: !process.env.CI,
        timeout: 30000,
        stdout: 'pipe',
        stderr: 'pipe',
      },
});
