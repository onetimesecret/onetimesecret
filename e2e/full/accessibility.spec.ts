// e2e/full/accessibility.spec.ts
//
// Automated accessibility (a11y) regression suite for AUTHENTICATED surfaces.
//
// Companion to e2e/all/accessibility.spec.ts (public surfaces). This spec runs
// in the `full` Playwright project, which depends on `setup` (global.setup.ts
// registers + signs in a TEST_USER_* account and saves the session to
// STORAGE_STATE), so every test starts already authenticated via storageState.
//
// Data-driven over the primary requiresAuth routes × BOTH themes (light +
// dark). Each test navigates, waits for the SPA to signal readiness
// (html[data-app-ready]), asserts the intended theme actually applied, then
// runs axe and compares the result to a SEPARATE committed baseline of KNOWN
// violations (e2e/accessibility-baseline.full.json) so it never collides with
// the public baseline.
//
//   Regression policy (identical to the public spec):
//     - FAIL on ANY violation whose stable key is not in the baseline.
//     - HARD-FAIL (called out explicitly) on any new SERIOUS/CRITICAL one.
//     - When A11Y_UPDATE_BASELINE is set, REWRITE the full baseline instead
//       of asserting.
//
// Runs in CI via the `full/` suite step in .github/workflows/e2e.yml
// (`pnpm test:playwright e2e/full/`), which pulls in `setup` automatically.
// Local sandbox runs point Chromium at a pre-installed binary via the
// A11Y_CHROME_PATH env var (wired in e2e/playwright.config.ts).

import { test, expect } from '@playwright/test';
import {
  scanPage,
  loadBaseline,
  compareToBaseline,
  formatFailure,
  updateBaselineScope,
  primeTheme,
  assertThemeApplied,
  IS_UPDATE_BASELINE,
  FULL_BASELINE_PATH,
  type Theme,
} from '../support/axe';

/**
 * Authenticated, requiresAuth surfaces to scan. A representative, high-value,
 * NON-DESTRUCTIVE set: the dashboard, recents, account profile, the main
 * profile/security settings sections, API settings, and the organizations
 * list. Routes carrying path params (domain detail, single-org settings) and
 * destructive surfaces (caution/close-account) are intentionally excluded.
 *
 * All of these are reachable by a fresh self-signup account (owner of its own
 * default org, full-auth mode, password-based) — the identity global.setup.ts
 * provisions — so no extra fixtures are required.
 */
const AUTH_SURFACES = [
  '/dashboard',
  '/recent',
  '/account',
  '/account/settings/profile/privacy',
  '/account/settings/profile/notifications',
  '/account/settings/security',
  '/account/settings/api',
  '/orgs',
];

const THEMES: Theme[] = ['light', 'dark'];

/**
 * Readiness timeout for `html[data-app-ready]`. Authenticated surfaces hydrate
 * more (org/account data, more components) than the public pages, so give them
 * headroom over Playwright's default rather than risk a flaky bounce on a slow
 * first paint.
 */
const APP_READY_TIMEOUT_MS = 30_000;

for (const theme of THEMES) {
  test.describe(`Accessibility (authenticated) — ${theme} theme`, () => {
    for (const route of AUTH_SURFACES) {
      test(`${route} has no a11y regressions (${theme})`, async ({ page }, testInfo) => {
        await primeTheme(page, theme);

        await page.goto(route);
        await expect(page.locator('html[data-app-ready="true"]')).toBeAttached({
          timeout: APP_READY_TIMEOUT_MS,
        });

        // Guard against a silent auth-guard bounce: an unauthenticated session
        // would redirect these requiresAuth routes to /signin, which would
        // scan the wrong page and poison the baseline.
        await expect(page).not.toHaveURL(/\/signin/);

        await assertThemeApplied(page, theme);

        const violations = await scanPage(page, testInfo, { theme, route });

        if (IS_UPDATE_BASELINE) {
          updateBaselineScope(theme, route, violations, FULL_BASELINE_PATH);
          testInfo.annotations.push({
            type: 'a11y-baseline-updated',
            description: `${theme} ${route}: ${violations.length} violation(s) captured`,
          });
          return;
        }

        const baseline = loadBaseline(FULL_BASELINE_PATH);
        const cmp = compareToBaseline(violations, baseline);
        expect(cmp.regressions, formatFailure(cmp)).toHaveLength(0);
      });
    }
  });
}
