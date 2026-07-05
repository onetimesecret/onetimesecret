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

import { test, expect, type Page } from '@playwright/test';
import {
  scanPage,
  loadBaseline,
  compareToBaseline,
  formatFailure,
  updateBaselineScope,
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

/** localStorage key read by src/shared/composables/useTheme.ts ('true' = dark). */
const THEME_STORAGE_KEY = 'restMode';

/**
 * Make a theme apply deterministically BEFORE any app script runs:
 *  - Persist the app's own preference key (useTheme reads localStorage first),
 *  - and set the OS-level color-scheme media as a belt-and-suspenders fallback.
 * useTheme.initializeTheme() then toggles `html.dark` from the stored value.
 * addInitScript runs after storageState localStorage is applied, so this wins.
 */
async function primeTheme(page: Page, theme: Theme): Promise<void> {
  const isDark = theme === 'dark';
  await page.emulateMedia({ colorScheme: isDark ? 'dark' : 'light' });
  await page.addInitScript(
    ([key, value]) => {
      try {
        window.localStorage.setItem(key, value);
      } catch {
        /* localStorage may be unavailable; media emulation still applies */
      }
    },
    [THEME_STORAGE_KEY, String(isDark)]
  );
}

/**
 * Assert the requested theme genuinely took effect. A silent light-mode scan
 * mislabeled 'dark' is worse than useless, so fail loudly if `html.dark`
 * disagrees with the intended theme.
 */
async function assertThemeApplied(page: Page, theme: Theme): Promise<void> {
  const hasDarkClass = await page.evaluate(() =>
    document.documentElement.classList.contains('dark')
  );
  if (theme === 'dark') {
    expect(
      hasDarkClass,
      "Dark theme did not apply: html is missing the 'dark' class after load. " +
        'Refusing to scan — a light-mode scan mislabeled "dark" would poison the baseline.'
    ).toBe(true);
  } else {
    expect(
      hasDarkClass,
      "Light theme did not apply: html unexpectedly has the 'dark' class after load."
    ).toBe(false);
  }
}

for (const theme of THEMES) {
  test.describe(`Accessibility (authenticated) — ${theme} theme`, () => {
    for (const route of AUTH_SURFACES) {
      test(`${route} has no a11y regressions (${theme})`, async ({ page }, testInfo) => {
        await primeTheme(page, theme);

        await page.goto(route);
        await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

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
