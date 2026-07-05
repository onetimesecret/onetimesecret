// e2e/support/axe.ts
//
// Shared accessibility (a11y) scanning helper for the Playwright suite.
//
// Wraps @axe-core/playwright's AxeBuilder with:
//  - a fixed set of WCAG + best-practice tags,
//  - report attachment of the full axe result JSON (so failures are
//    debuggable in the HTML report), and
//  - baseline compare logic keyed on a STABLE identity (no volatile data
//    like exact contrast ratios) so the committed baseline is diff-friendly.
//
// Consumed by e2e/all/accessibility.spec.ts (public surfaces) and
// e2e/full/accessibility.spec.ts (authenticated surfaces). Each spec passes
// its OWN baseline file so the two suites never collide:
//  - public:        e2e/accessibility-baseline.json      (default)
//  - authenticated: e2e/accessibility-baseline.full.json (FULL_BASELINE_PATH)
// The baseline-aware functions (loadBaseline / updateBaselineScope) take an
// optional path that defaults to the public baseline, so existing public
// callers are unaffected.

import { AxeBuilder } from '@axe-core/playwright';
import { expect, type Page, type TestInfo } from '@playwright/test';
import type { AxeResults, Result as AxeRule } from 'axe-core';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const SUPPORT_DIR = path.dirname(fileURLToPath(import.meta.url));

/** Committed baseline of KNOWN violations. Absolute so writer/reader agree. */
export const BASELINE_PATH = path.join(SUPPORT_DIR, '..', 'accessibility-baseline.json');

/**
 * Separate baseline for the AUTHENTICATED (`full` project) surfaces. Kept
 * apart from the public baseline so the two suites' keys never collide and so
 * regenerating one doesn't touch the other.
 */
export const FULL_BASELINE_PATH = path.join(
  SUPPORT_DIR,
  '..',
  'accessibility-baseline.full.json'
);

/**
 * Separate baseline for the INTERACTIVE-STATE scans (dropdown open, error
 * banners, open modals) in e2e/all/accessibility-interactive.spec.ts. The
 * public at-rest baseline (BASELINE_PATH) is a pure "pages load clean" signal;
 * post-interaction DOM is a conceptually distinct scope, so it gets its own
 * file. Separate files also mean regenerating one never touches another and
 * there is no read-modify-write contention if the a11y specs ever update in
 * parallel.
 */
export const INTERACTIVE_BASELINE_PATH = path.join(
  SUPPORT_DIR,
  '..',
  'accessibility-baseline.interactive.json'
);

/** True when the run should REWRITE the baseline instead of asserting. */
export const IS_UPDATE_BASELINE = !!process.env.A11Y_UPDATE_BASELINE;

/**
 * Rule tags scanned. Covers WCAG 2.0/2.1 levels A and AA plus axe's
 * best-practice rules.
 */
export const AXE_TAGS = [
  'wcag2a',
  'wcag2aa',
  'wcag21a',
  'wcag21aa',
  'best-practice',
] as const;

export type Theme = 'light' | 'dark';

/** localStorage key read by src/shared/composables/useTheme.ts ('true' = dark). */
export const THEME_STORAGE_KEY = 'restMode';

/**
 * Make a theme apply deterministically BEFORE any app script runs:
 *  - Persist the app's own preference key (useTheme reads localStorage first),
 *  - and set the OS-level color-scheme media as a belt-and-suspenders fallback.
 * useTheme.initializeTheme() then toggles `html.dark` from the stored value.
 * addInitScript runs after storageState localStorage is applied, so this wins.
 *
 * Shared by the public (e2e/all) and authenticated (e2e/full) a11y specs so a
 * future change (e.g. to THEME_STORAGE_KEY) only happens in one place.
 */
export async function primeTheme(page: Page, theme: Theme): Promise<void> {
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
export async function assertThemeApplied(page: Page, theme: Theme): Promise<void> {
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

/** A single violating DOM node, flattened to one stable-keyed record. */
export interface FlatViolation {
  /** `${theme}|${route}|${rule.id}|${node.target.join(' ')}` */
  key: string;
  theme: Theme;
  route: string;
  ruleId: string;
  /** CSS selector path(s) for the offending node. */
  target: string;
  /** axe impact: 'minor' | 'moderate' | 'serious' | 'critical' | null. */
  impact: string | null;
  /** Short human help text (metadata only — never part of the key). */
  help: string;
}

/** Baseline is a map of stable key -> violation metadata (sans the key). */
export type Baseline = Record<string, Omit<FlatViolation, 'key'>>;

/** Build the stable identity key for a single violating node. */
export function violationKey(
  theme: Theme,
  route: string,
  ruleId: string,
  target: string
): string {
  return `${theme}|${route}|${ruleId}|${target}`;
}

/** Filesystem-safe slug for a route, used in the attachment filename. */
export function routeSlug(route: string): string {
  const trimmed = route.replace(/^\/+|\/+$/g, '');
  return trimmed === '' ? 'root' : trimmed.replace(/[^a-z0-9]+/gi, '-');
}

/** Flatten an AxeResults into one record per (rule, node). */
export function flattenViolations(
  results: AxeResults,
  theme: Theme,
  route: string
): FlatViolation[] {
  const flat: FlatViolation[] = [];
  for (const rule of results.violations as AxeRule[]) {
    for (const node of rule.nodes) {
      const target = node.target.join(' ');
      flat.push({
        key: violationKey(theme, route, rule.id, target),
        theme,
        route,
        ruleId: rule.id,
        target,
        impact: rule.impact ?? node.impact ?? null,
        help: rule.help,
      });
    }
  }
  return flat;
}

/**
 * Run axe against the current page state, attach the full result JSON to the
 * Playwright report, and return the flattened violations.
 */
export async function scanPage(
  page: Page,
  testInfo: TestInfo,
  opts: { theme: Theme; route: string }
): Promise<FlatViolation[]> {
  const results = await new AxeBuilder({ page })
    .withTags([...AXE_TAGS])
    .analyze();

  await testInfo.attach(`axe-${routeSlug(opts.route)}-${opts.theme}.json`, {
    body: JSON.stringify(results, null, 2),
    contentType: 'application/json',
  });

  return flattenViolations(results, opts.theme, opts.route);
}

/**
 * Load the committed baseline; an absent file is treated as empty. Pass a
 * `baselinePath` to read a suite-specific baseline (defaults to the public
 * one at BASELINE_PATH).
 */
export function loadBaseline(baselinePath: string = BASELINE_PATH): Baseline {
  try {
    const raw = fs.readFileSync(baselinePath, 'utf8');
    return JSON.parse(raw) as Baseline;
  } catch {
    return {};
  }
}

/** Serialize a baseline with keys sorted so diffs are minimal. */
export function serializeBaseline(baseline: Baseline): string {
  const sortedKeys = Object.keys(baseline).sort();
  const ordered: Baseline = {};
  for (const k of sortedKeys) ordered[k] = baseline[k];
  return JSON.stringify(ordered, null, 2) + '\n';
}

/**
 * REWRITE the baseline for a single (theme, route) scope from the current
 * scan: drop any existing entries under that scope's key prefix, then add the
 * current violations. Read-modify-write is safe because the a11y spec runs
 * serially in one worker (fullyParallel: false). Running the full
 * `test:a11y:update` therefore regenerates every scope.
 */
export function updateBaselineScope(
  theme: Theme,
  route: string,
  violations: FlatViolation[],
  baselinePath: string = BASELINE_PATH
): void {
  const baseline = loadBaseline(baselinePath);
  const prefix = `${theme}|${route}|`;
  for (const k of Object.keys(baseline)) {
    if (k.startsWith(prefix)) delete baseline[k];
  }
  for (const v of violations) {
    const { key, ...meta } = v;
    baseline[key] = meta;
  }
  fs.writeFileSync(baselinePath, serializeBaseline(baseline), 'utf8');
}

export interface CompareResult {
  /** Current violations whose key is NOT present in the baseline. */
  regressions: FlatViolation[];
  /** Subset of regressions with impact 'serious' or 'critical'. */
  seriousOrCritical: FlatViolation[];
}

/** Compare a current scan against the baseline map. */
export function compareToBaseline(
  violations: FlatViolation[],
  baseline: Baseline
): CompareResult {
  const regressions = violations.filter((v) => !(v.key in baseline));
  const seriousOrCritical = regressions.filter(
    (v) => v.impact === 'serious' || v.impact === 'critical'
  );
  return { regressions, seriousOrCritical };
}

/** Format regressions into a readable, report-friendly failure message. */
export function formatFailure(cmp: CompareResult): string {
  const lines: string[] = [];
  lines.push(
    `Found ${cmp.regressions.length} NEW accessibility violation(s) not in the baseline (a11y regression).`
  );
  if (cmp.seriousOrCritical.length > 0) {
    lines.push(
      `  ${cmp.seriousOrCritical.length} of these are SERIOUS or CRITICAL and are hard failures:`
    );
    for (const v of cmp.seriousOrCritical) {
      lines.push(`    [${v.impact}] ${v.ruleId} @ ${v.target} — ${v.help}`);
    }
  }
  const others = cmp.regressions.filter(
    (v) => v.impact !== 'serious' && v.impact !== 'critical'
  );
  if (others.length > 0) {
    lines.push(`  ${others.length} other new violation(s):`);
    for (const v of others) {
      lines.push(`    [${v.impact ?? 'n/a'}] ${v.ruleId} @ ${v.target} — ${v.help}`);
    }
  }
  lines.push(
    'Fix the source component, or (if intentional/known) re-baseline via `pnpm test:a11y:update`.'
  );
  return lines.join('\n');
}
