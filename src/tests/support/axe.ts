// src/tests/support/axe.ts

//
// Shared helper for Layer-1 (component-level) accessibility tests.
//
// Runs axe-core (via vitest-axe) against a mounted component's root DOM node
// inside jsdom. This catches structural / ARIA / label / role regressions on
// every `pnpm test` run, complementing the browser-level Playwright scans.
//
// Matcher wiring note:
//   vitest-axe ships an `extend-expect` entry, but in this installed version
//   `dist/extend-expect.js` is EMPTY (0 bytes), so importing it registers
//   nothing. We therefore wire the matcher explicitly via `expect.extend`
//   using the `toHaveNoViolations` export from `vitest-axe/dist/matchers`
//   (see the import comment below for why `dist/matchers` specifically),
//   and declare it on vitest's `Matchers` interface ourselves for typing.
//

import { axe } from 'vitest-axe';
// Import from the `dist/matchers` entry point rather than the public
// `vitest-axe/matchers` subpath: in this installed version (0.1.0), the
// public entry's declaration file re-exports everything as type-only
// (`export type * from './dist/matchers'`), so under `isolatedModules`
// `toHaveNoViolations` cannot be used as a value from there (TS1362) even
// though the runtime export is a real function. `dist/matchers` is the same
// underlying module (the public entry just re-exports it) with a correct,
// value-preserving declaration, so this changes nothing at runtime.
import { toHaveNoViolations } from 'vitest-axe/dist/matchers';
import { expect } from 'vitest';
import type { VueWrapper } from '@vue/test-utils';

// Register the custom matcher once for the whole test process. Any spec that
// imports from this module gets `expect(...).toHaveNoViolations()` wired up.
expect.extend({ toHaveNoViolations });

// vitest-axe also ships a `vitest-axe/extend-expect` entry that declares this
// matcher on `Assertion`/`AsymmetricMatchersContaining`, but it augments an
// old `Vi.Assertion` namespace that no longer exists in the installed vitest
// (4.x moved these interfaces into the `vitest`/`@vitest/expect` module
// directly), so importing it would not actually type `expect(...).toHaveNoViolations()`.
// Augment the current extension point directly instead.
declare module 'vitest' {
  interface Matchers<T = any> {
    toHaveNoViolations(): void;
  }
}

/**
 * axe-core rules that cannot be meaningfully evaluated for an isolated
 * component mounted in jsdom.
 *
 * - color-contrast: needs real layout/paint (computed colors + geometry),
 *   which jsdom does not provide. Always produces false results here.
 * - region: a page-level rule requiring all content to live inside a landmark
 *   (main/nav/footer/...). A Layer-1 component is mounted in isolation and
 *   receives its landmark from the parent layout at runtime, so this rule
 *   always false-positives at the component level.
 */
const JSDOM_DISABLED_RULES = {
  'color-contrast': { enabled: false },
  region: { enabled: false },
} as const;

type AxeElement = Element | VueWrapper<any>;

function resolveElement(target: AxeElement): Element {
  // Accept either a raw DOM Element or a @vue/test-utils wrapper.
  if (target && typeof (target as VueWrapper<any>).element !== 'undefined') {
    return (target as VueWrapper<any>).element as Element;
  }
  return target as Element;
}

/**
 * Runs axe against the given mounted component (or DOM element) and asserts
 * there are no accessibility violations, excluding rules jsdom cannot judge
 * (color-contrast).
 *
 * @param target  A @vue/test-utils wrapper or a raw DOM Element.
 * @param extraRules  Optional axe rule overrides merged on top of the jsdom
 *   defaults (e.g. to additionally disable a rule for a specific case).
 */
export async function expectNoA11yViolations(
  target: AxeElement,
  extraRules: Record<string, { enabled: boolean }> = {}
): Promise<void> {
  const element = resolveElement(target);

  const results = await axe(element, {
    rules: {
      ...JSDOM_DISABLED_RULES,
      ...extraRules,
    },
  });

  expect(results).toHaveNoViolations();
}
