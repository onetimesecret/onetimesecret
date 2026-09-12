// src/tests/utils/redirect.spec.ts

import {
  isAllowedCheckoutUrl,
  isValidInternalPath,
  MAX_REDIRECT_LENGTH,
  setAllowedCheckoutHost,
} from '@/utils/redirect';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';

/**
 * isValidInternalPath is the ONLY redirect validator now — the former
 * validateRedirect / validatePathString / validateUrl trio was dead code for
 * the `?redirect=` param (nothing but this file referenced it) and permitted
 * things this ruleset must reject: control characters, absolute same-host URLs,
 * and protocol-relative input.
 *
 * The identical ruleset is implemented in Ruby on the backend (signup stores a
 * validated redirect, verify-account replays it). Parity is ENFORCED rather
 * than requested: tests/fixtures/redirect_path_cases.json is a single
 * accept/reject table read by this suite AND by
 * spec/unit/onetime/utils/redirect_paths_spec.rb. A rule relaxed on one side
 * only turns one of the two suites red.
 *
 * What stays hand-written here: the cases JSON cannot express — non-string
 * input (undefined/null/number/object/array). The Ruby suite carries its own
 * equivalents (nil/Integer/Array/Hash, plus an invalidly-encoded String).
 */

interface RedirectCase {
  id: string;
  group: string;
  input: string;
  expected: boolean;
  note?: string;
}

// Vitest's root is the repo root, so the fixture resolves the same way the
// email-redaction corpus does (src/tests/plugins/core/diagnostics/…). A wrong
// path throws HERE, naming it, rather than yielding an empty case list.
const FIXTURE_PATH = resolve(process.cwd(), 'tests/fixtures/redirect_path_cases.json');
const REDIRECT_CASES = (
  JSON.parse(readFileSync(FIXTURE_PATH, 'utf8')) as { cases: RedirectCase[] }
).cases;

/** Fixture groups, in first-seen order — the taxonomy the tests nest under. */
const GROUPS = [...new Set(REDIRECT_CASES.map((c) => c.group))];

/**
 * Cases whose removal OR alteration must turn this suite RED. Erosion is the
 * one failure mode a fixture-driven suite cannot self-detect: delete every case
 * and it passes vacuously — and pinning bare ids is not enough, because editing
 * a pinned case's input (retargeting `protocol-relative` at some harmless path
 * and flipping `expected`) would keep both suites green while removing the
 * rejection from coverage. So the acceptance criteria named in #4305 are pinned
 * as full (id, input, expected) triples.
 */
const PINNED_CASES: Record<string, [string, boolean]> = {
  'nested-path': ['/account/settings/security', true],
  'query-and-fragment': ['/secret/abc?view=raw#content', true],
  'absolute-https': ['https://attacker.example', false],
  'protocol-relative': ['//evil.example', false],
  'backslash-authority': ['/\\evil.example', false],
  'encoded-traversal-lowercase': ['/%2e%2e/admin', false],
};

/**
 * The length boundaries are pinned too, but their ~2KB inputs are asserted by
 * construction (exact code-point length against MAX_REDIRECT_LENGTH, plus
 * expected) in the boundary test below rather than pasted here.
 */
const PINNED_LENGTH_CASE_IDS = [
  'length-at-cap',
  'length-over-cap',
  'astral-length-at-cap',
  'astral-length-over-cap',
];

describe('the shared parity fixture', () => {
  it('carries cases', () => {
    expect(Array.isArray(REDIRECT_CASES)).toBe(true);
    expect(REDIRECT_CASES.length).toBeGreaterThan(0);
  });

  it('still carries the pinned #4305 cases, unaltered', () => {
    const byId = new Map(REDIRECT_CASES.map((c) => [c.id, c]));

    for (const [id, [input, expected]] of Object.entries(PINNED_CASES)) {
      const kase = byId.get(id);
      expect(kase, `pinned case ${id} is missing from the fixture`).toBeDefined();
      expect(
        [kase?.input, kase?.expected],
        `pinned case ${id} was altered (its input/expected no longer match #4305)`
      ).toEqual([input, expected]);
    }

    for (const id of PINNED_LENGTH_CASE_IDS) {
      expect(byId.has(id), `pinned case ${id} is missing from the fixture`).toBe(true);
    }
  });

  it('uses unique ids', () => {
    const ids = REDIRECT_CASES.map((c) => c.id);
    expect(new Set(ids).size).toBe(ids.length);
  });

  it('gives every case a group', () => {
    // The group is what turns the generated tests back into a readable
    // taxonomy; a case without one would be silently unfiled.
    const ungrouped = REDIRECT_CASES.filter((c) => !c.group);
    expect(ungrouped.map((c) => c.id)).toEqual([]);
  });

  it('pins the length boundaries at MAX_REDIRECT_LENGTH', () => {
    // The cap is defined in Unicode CODE POINTS — the unit Ruby's
    // String#length measures natively — so measure the same way here:
    // [...input] iterates code points, while input.length counts UTF-16 units
    // and double-counts the astral cases (4095/4097 units). Those cases exist
    // precisely to pin that distinction: a validator measuring UTF-16 units
    // rejects at-cap input the server-side validator stores.
    const boundaries: Record<string, [number, boolean]> = {
      'length-at-cap': [0, true],
      'length-over-cap': [1, false],
      'astral-length-at-cap': [0, true],
      'astral-length-over-cap': [1, false],
    };

    for (const [id, [overBy, expected]] of Object.entries(boundaries)) {
      const kase = REDIRECT_CASES.find((c) => c.id === id);
      expect([...(kase?.input ?? '')].length, `${id} length drifted`).toBe(
        MAX_REDIRECT_LENGTH + overBy
      );
      expect(kase?.expected, `${id} expectation flipped`).toBe(expected);
    }
  });
});

describe('isValidInternalPath', () => {
  // One test per fixture case, named by the case id so a failure names the
  // offending input and the Ruby half can be checked against the same name.
  // Nested under the case's `group` so the output still reads as a taxonomy of
  // the ruleset — the same reading the hand-written describes gave, now sourced
  // from the fixture instead of restated in two languages.
  for (const group of GROUPS) {
    describe(`with ${group}`, () => {
      for (const kase of REDIRECT_CASES.filter((c) => c.group === group)) {
        const verb = kase.expected ? 'accepts' : 'rejects';
        // The length-boundary inputs are ~2KB; summarize rather than paste.
        const shown =
          kase.input.length > 64
            ? `${kase.input.length} characters`
            : JSON.stringify(kase.input);

        it(`${verb} ${kase.id} (${shown})`, () => {
          expect(isValidInternalPath(kase.input)).toBe(kase.expected);
        });
      }
    });
  }

  // TypeScript-only: not expressible as a JSON string. The Ruby suite carries
  // nil/Integer/Array/Hash on its side.
  describe('with non-string input (not expressible in the shared fixture)', () => {
    it('rejects undefined and null', () => {
      expect(isValidInternalPath(undefined)).toBe(false);
      expect(isValidInternalPath(null)).toBe(false);
    });

    it('rejects numbers, objects, and arrays', () => {
      expect(isValidInternalPath(123 as unknown as string)).toBe(false);
      expect(isValidInternalPath({} as unknown as string)).toBe(false);
      expect(isValidInternalPath([] as unknown as string)).toBe(false);
    });
  });
});

describe('isAllowedCheckoutUrl', () => {
  let originalLocation: Location;

  beforeEach(() => {
    originalLocation = window.location;
    Object.defineProperty(window, 'location', {
      value: { origin: 'https://onetimesecret.com' },
      writable: true,
      configurable: true,
    });
  });

  afterEach(() => {
    // Restore the real Location so a partial stub doesn't leak into other test
    // files sharing this Vitest worker (see src/tests/router/guards.routes.spec.ts).
    Object.defineProperty(window, 'location', {
      value: originalLocation,
      writable: true,
      configurable: true,
    });
    // Reset the module-level configured host so state doesn't leak between tests.
    setAllowedCheckoutHost(null);
  });

  it('allows the shared Stripe Checkout host', () => {
    expect(isAllowedCheckoutUrl('https://checkout.stripe.com/c/pay/cs_test_123')).toBe(true);
  });

  it('allows the current app origin', () => {
    expect(isAllowedCheckoutUrl('https://onetimesecret.com/billing/welcome')).toBe(true);
  });

  it('rejects an unrelated host', () => {
    expect(isAllowedCheckoutUrl('https://evil.example.com/c/pay/cs')).toBe(false);
  });

  describe('when no custom checkout host is configured', () => {
    it('rejects the Stripe custom-domain host (not hardcoded)', () => {
      expect(isAllowedCheckoutUrl('https://pay.onetimesecret.com/c/pay/cs_test_123')).toBe(
        false
      );
    });

    it('still allows the shared Stripe host and the app origin', () => {
      expect(isAllowedCheckoutUrl('https://checkout.stripe.com/c/pay/cs_test_123')).toBe(
        true
      );
      expect(isAllowedCheckoutUrl('https://onetimesecret.com/billing/welcome')).toBe(true);
    });
  });

  describe('when a custom checkout host is configured', () => {
    beforeEach(() => {
      setAllowedCheckoutHost('pay.onetimesecret.com');
    });

    it('allows the configured Stripe custom-domain Checkout host', () => {
      expect(isAllowedCheckoutUrl('https://pay.onetimesecret.com/c/pay/cs_test_123')).toBe(
        true
      );
    });

    it('still allows the static baseline and same-origin', () => {
      expect(isAllowedCheckoutUrl('https://checkout.stripe.com/c/pay/cs_test_123')).toBe(
        true
      );
      expect(isAllowedCheckoutUrl('https://onetimesecret.com/billing/welcome')).toBe(true);
    });

    it('still rejects lookalike siblings of the configured host', () => {
      expect(isAllowedCheckoutUrl('https://not-pay.onetimesecret.com.evil.com/')).toBe(
        false
      );
      expect(isAllowedCheckoutUrl('https://pay.onetimesecret.com.evil.com/')).toBe(false);
      expect(isAllowedCheckoutUrl('https://checkout.stripe.com.evil.com/')).toBe(false);
    });
  });

  it('clears the configured host when set to empty or null', () => {
    setAllowedCheckoutHost('pay.onetimesecret.com');
    expect(isAllowedCheckoutUrl('https://pay.onetimesecret.com/c/pay/cs')).toBe(true);

    setAllowedCheckoutHost('');
    expect(isAllowedCheckoutUrl('https://pay.onetimesecret.com/c/pay/cs')).toBe(false);

    setAllowedCheckoutHost('pay.onetimesecret.com');
    setAllowedCheckoutHost(null);
    expect(isAllowedCheckoutUrl('https://pay.onetimesecret.com/c/pay/cs')).toBe(false);
  });

  it('does not allow a wildcard sibling of an allowlisted host', () => {
    expect(isAllowedCheckoutUrl('https://not-pay.onetimesecret.com.evil.com/')).toBe(false);
    expect(isAllowedCheckoutUrl('https://checkout.stripe.com.evil.com/')).toBe(false);
  });

  it('rejects empty, null, and unparseable input', () => {
    expect(isAllowedCheckoutUrl('')).toBe(false);
    expect(isAllowedCheckoutUrl(null)).toBe(false);
    expect(isAllowedCheckoutUrl(undefined)).toBe(false);
    expect(isAllowedCheckoutUrl('not-a-url')).toBe(false);
  });

  describe('setAllowedCheckoutHost input validation', () => {
    it('tolerates surrounding whitespace on the configured host', () => {
      // env/helm values commonly carry stray spaces; they must not silently
      // clear the host and reintroduce the checkout regression.
      setAllowedCheckoutHost('  pay.onetimesecret.com  ');
      expect(isAllowedCheckoutUrl('https://pay.onetimesecret.com/c/pay/cs')).toBe(true);
    });

    it('rejects a host carrying userinfo instead of selecting the authority', () => {
      // "pay.onetimesecret.com@evil.example" parses to origin https://evil.example.
      setAllowedCheckoutHost('pay.onetimesecret.com@evil.example');
      expect(isAllowedCheckoutUrl('https://evil.example/c/pay/cs')).toBe(false);
      expect(isAllowedCheckoutUrl('https://pay.onetimesecret.com/c/pay/cs')).toBe(false);
    });

    it('rejects a host that includes a path', () => {
      setAllowedCheckoutHost('pay.onetimesecret.com/evil');
      expect(isAllowedCheckoutUrl('https://pay.onetimesecret.com/c/pay/cs')).toBe(false);
    });

    it('rejects a value that already includes a scheme', () => {
      setAllowedCheckoutHost('https://pay.onetimesecret.com');
      expect(isAllowedCheckoutUrl('https://pay.onetimesecret.com/c/pay/cs')).toBe(false);
    });

    it('accepts a host with an explicit non-default port', () => {
      // The port is part of the origin, so only matching-port URLs are allowed.
      setAllowedCheckoutHost('pay.onetimesecret.com:8443');
      expect(isAllowedCheckoutUrl('https://pay.onetimesecret.com:8443/c/pay/cs')).toBe(true);
      expect(isAllowedCheckoutUrl('https://pay.onetimesecret.com/c/pay/cs')).toBe(false);
    });

    it('accepts a host with the explicit default HTTPS port (:443)', () => {
      // new URL() normalizes :443 away; the host must still be enabled. This is
      // the regression the raw-input validation guards against — comparing the
      // input to new URL().host would drop :443 and clear the origin.
      setAllowedCheckoutHost('pay.onetimesecret.com:443');
      expect(isAllowedCheckoutUrl('https://pay.onetimesecret.com/c/pay/cs')).toBe(true);
      expect(isAllowedCheckoutUrl('https://pay.onetimesecret.com:443/c/pay/cs')).toBe(true);
    });

    it('rejects a host with an out-of-range port', () => {
      // new URL() rejects ports > 65535; fail closed rather than silently drop.
      setAllowedCheckoutHost('pay.onetimesecret.com:99999');
      expect(isAllowedCheckoutUrl('https://pay.onetimesecret.com/c/pay/cs')).toBe(false);
    });
  });
});
