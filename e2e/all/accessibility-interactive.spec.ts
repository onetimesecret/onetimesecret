// e2e/all/accessibility-interactive.spec.ts
//
// Automated accessibility (a11y) regression suite for INTERACTIVE STATES.
//
// Companion to e2e/all/accessibility.spec.ts, which scans each public route in
// its initial, at-rest DOM. axe only ever sees the DOM present at scan time,
// so any UI that exists ONLY after an interaction — an open dropdown, a
// rendered error banner, an open modal — is invisible to the at-rest scan.
// This spec closes that gap: it drives the app INTO each state, asserts the
// state actually rendered, and only then runs axe.
//
// Data-driven over SCENARIOS × BOTH themes (light + dark). Each scenario has a
// stable `scope` string used as the baseline key namespace (analogous to a
// route in the at-rest spec) and a `drive()` that navigates + reaches the
// state. Results compare against a SEPARATE committed baseline
// (e2e/accessibility-baseline.interactive.json) so interactive-state debt never
// collides with the at-rest public baseline and rebaselining one never touches
// the other.
//
//   Regression policy (identical to the at-rest spec):
//     - FAIL on ANY violation whose stable key is not in the baseline.
//     - HARD-FAIL (called out explicitly) on any new SERIOUS/CRITICAL one.
//     - When A11Y_UPDATE_BASELINE is set, REWRITE the baseline instead of
//       asserting (this is `pnpm test:a11y:interactive:update`).
//
// Credential-free: every scenario reaches its state without signing in, so it
// runs in the `chromium` project and is picked up by CI's existing blocking
// invocation `pnpm test:playwright e2e/all/`. Local sandbox runs point Chromium
// at a pre-installed binary via A11Y_CHROME_PATH (wired in playwright.config).

import { test, expect, type Page } from '@playwright/test';
import {
  scanPage,
  loadBaseline,
  compareToBaseline,
  formatFailure,
  updateBaselineScope,
  primeTheme,
  assertThemeApplied,
  waitForAppReady,
  IS_UPDATE_BASELINE,
  INTERACTIVE_BASELINE_PATH,
  type Theme,
} from '../support/axe';

// The A11Y_UPDATE_BASELINE path (updateBaselineScope) does a read-modify-write
// of one JSON baseline file, which is only correct when these tests don't run
// concurrently. Assert runs are pure reads and can safely parallelize — and
// keeping them parallel preserves independent per-test failure reporting, so a
// regression in one scenario doesn't cascade-skip the others. So pin serial
// execution for baseline-regeneration runs only. That keeps regeneration
// race-free even if playwright.config.ts later flips `fullyParallel: true`
// (a stated Phase 3 goal there); today `fullyParallel: false` already
// serializes within a file, so this is belt-and-suspenders.
if (IS_UPDATE_BASELINE) {
  test.describe.configure({ mode: 'serial' });
}

const THEMES: Theme[] = ['light', 'dark'];

/**
 * One interactive scenario.
 *  - `scope`: stable baseline-key namespace. NOT a literal URL — it names the
 *    state ("/#split-button-open") so keys stay readable and never collide
 *    with the at-rest spec's real-route scopes.
 *  - `drive`: navigate + reach the state, asserting along the way that the
 *    intended DOM actually rendered. A silent no-op here would scan the wrong
 *    state and poison the baseline, so each driver ends on an explicit
 *    visibility expectation.
 */
interface Scenario {
  scope: string;
  title: string;
  drive: (page: Page) => Promise<void>;
}

const SCENARIOS: Scenario[] = [
  {
    scope: '/#split-button-open',
    title: 'split-button dropdown open (home create-secret form)',
    async drive(page) {
      await page.goto('/');
      await waitForAppReady(page);

      // Open the "more actions" dropdown next to the primary Create Link button.
      const toggle = page.locator('[data-testid="split-button-dropdown-toggle"]');
      await expect(toggle).toBeVisible();
      await expect(toggle).toHaveAttribute('aria-expanded', 'false');
      await toggle.click();

      // The menu is conditionally rendered; scan only once it is present.
      await expect(page.locator('#split-button-dropdown')).toBeVisible();
      await expect(toggle).toHaveAttribute('aria-expanded', 'true');
    },
  },
  {
    scope: '/signin#auth-error',
    title: 'sign-in form showing the auth-error banner',
    async drive(page) {
      await page.goto('/signin');
      await waitForAppReady(page);

      // Well-formed but bogus credentials → the backend rejects the login and
      // the form renders its role="alert" error banner. Non-destructive: no
      // account is created and the page stays on /signin. Randomized so a
      // rerun never trips rate-limiting on a fixed identity.
      const nonce = Math.random().toString(36).slice(2, 10);
      await page.fill('[data-testid="signin-email-input"]', `nobody-${nonce}@example.com`);
      await page.fill('[data-testid="signin-password-input"]', `wrong-${nonce}`);
      await page.click('[data-testid="signin-submit"]');

      // Wait for the actual error UI. Generous timeout: this is a real
      // round-trip (token refresh + login), unlike the pure-client states.
      await expect(page.locator('[data-testid="signin-error-message"]')).toBeVisible({
        timeout: 15_000,
      });
      // Guard against an unexpected successful login navigating away.
      await expect(page).toHaveURL(/\/signin/);
    },
  },
  {
    scope: '/#feedback-modal-open',
    title: 'feedback modal open (footer)',
    async drive(page) {
      await page.goto('/');
      await waitForAppReady(page);

      // The footer feedback toggle opens a role="dialog" modal (FocusTrap).
      // Match on the accessible name rather than a testid it doesn't expose;
      // both the visible "Send feedback" label and the "Open feedback form"
      // aria-label contain "feedback".
      const openFeedback = page.getByRole('button', { name: /feedback/i }).first();
      await expect(openFeedback).toBeVisible();
      await openFeedback.scrollIntoViewIfNeeded();
      await openFeedback.click();

      const dialog = page.getByRole('dialog');
      await expect(dialog).toBeVisible();
      await expect(dialog).toHaveAttribute('aria-modal', 'true');
    },
  },
];

for (const theme of THEMES) {
  test.describe(`Accessibility (interactive) — ${theme} theme`, () => {
    for (const scenario of SCENARIOS) {
      test(`${scenario.title} has no a11y regressions (${theme})`, async ({ page }, testInfo) => {
        await primeTheme(page, theme);
        await scenario.drive(page);
        await assertThemeApplied(page, theme);

        const violations = await scanPage(page, testInfo, { theme, route: scenario.scope });

        if (IS_UPDATE_BASELINE) {
          updateBaselineScope(theme, scenario.scope, violations, INTERACTIVE_BASELINE_PATH);
          testInfo.annotations.push({
            type: 'a11y-baseline-updated',
            description: `${theme} ${scenario.scope}: ${violations.length} violation(s) captured`,
          });
          return;
        }

        const baseline = loadBaseline(INTERACTIVE_BASELINE_PATH);
        const cmp = compareToBaseline(violations, baseline);
        expect(cmp.regressions, formatFailure(cmp)).toHaveLength(0);
      });
    }
  });
}
