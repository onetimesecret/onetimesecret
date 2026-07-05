// e2e/all/accessibility.spec.ts
//
// Automated accessibility (a11y) regression suite.
//
// Data-driven over PUBLIC surfaces × BOTH themes (light + dark). Each test
// navigates, waits for the SPA to signal readiness (html[data-app-ready]),
// asserts the intended theme actually applied, then runs axe and compares the
// result to a committed baseline of KNOWN violations
// (e2e/accessibility-baseline.json).
//
//   Regression policy:
//     - FAIL on ANY violation whose stable key is not in the baseline.
//     - HARD-FAIL (called out explicitly) on any new SERIOUS/CRITICAL one.
//     - When A11Y_UPDATE_BASELINE is set, REWRITE the baseline instead of
//       asserting (this is `pnpm test:a11y:update`).
//
// Runs credential-free in the `chromium` project and is therefore picked up by
// the existing CI invocation `pnpm test:playwright e2e/all/` (see
// .github/workflows/e2e.yml). Local sandbox runs point Chromium at a
// pre-installed binary via the A11Y_CHROME_PATH env var (wired in
// e2e/playwright.config.ts); CI uses the default managed browser.

import { test, expect, type Page } from '@playwright/test';
import {
  scanPage,
  loadBaseline,
  compareToBaseline,
  formatFailure,
  updateBaselineScope,
  IS_UPDATE_BASELINE,
  type Theme,
} from '../support/axe';

/** Public, credential-free surfaces to scan. */
const PUBLIC_SURFACES = ['/', '/signin', '/signup', '/forgot', '/pricing', '/feedback'];

const THEMES: Theme[] = ['light', 'dark'];

/** localStorage key read by src/shared/composables/useTheme.ts ('true' = dark). */
const THEME_STORAGE_KEY = 'restMode';

/**
 * Make a theme apply deterministically BEFORE any app script runs:
 *  - Persist the app's own preference key (useTheme reads localStorage first),
 *  - and set the OS-level color-scheme media as a belt-and-suspenders fallback.
 * useTheme.initializeTheme() then toggles `html.dark` from the stored value.
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
  test.describe(`Accessibility — ${theme} theme`, () => {
    for (const route of PUBLIC_SURFACES) {
      test(`${route} has no a11y regressions (${theme})`, async ({ page }, testInfo) => {
        await primeTheme(page, theme);

        await page.goto(route);
        await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();
        await assertThemeApplied(page, theme);

        const violations = await scanPage(page, testInfo, { theme, route });

        if (IS_UPDATE_BASELINE) {
          updateBaselineScope(theme, route, violations);
          // Surface what got captured in the report/log for this scope.
          testInfo.annotations.push({
            type: 'a11y-baseline-updated',
            description: `${theme} ${route}: ${violations.length} violation(s) captured`,
          });
          return;
        }

        const baseline = loadBaseline();
        const cmp = compareToBaseline(violations, baseline);
        expect(cmp.regressions, formatFailure(cmp)).toHaveLength(0);
      });
    }
  });
}
