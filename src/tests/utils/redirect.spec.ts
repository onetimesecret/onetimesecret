// src/tests/utils/redirect.spec.ts

import {
  isAllowedCheckoutUrl,
  isValidInternalPath,
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

/**
 * Cases whose removal from the fixture must turn this suite RED. Erosion is the
 * one failure mode a fixture-driven suite cannot self-detect: delete every case
 * and it passes vacuously. These are the acceptance criteria named in #4305
 * plus the two length boundaries.
 */
const PINNED_CASE_IDS = [
  'nested-path',
  'query-and-fragment',
  'absolute-https',
  'protocol-relative',
  'backslash-authority',
  'encoded-traversal-lowercase',
  'length-at-cap',
  'length-over-cap',
];

const MAX_REDIRECT_LENGTH = 2048;

describe('the shared parity fixture', () => {
  it('carries cases', () => {
    expect(Array.isArray(REDIRECT_CASES)).toBe(true);
    expect(REDIRECT_CASES.length).toBeGreaterThan(0);
  });

  it('still carries the pinned #4305 cases', () => {
    const ids = REDIRECT_CASES.map((c) => c.id);
    for (const id of PINNED_CASE_IDS) {
      expect(ids).toContain(id);
    }
  });

  it('uses unique ids', () => {
    const ids = REDIRECT_CASES.map((c) => c.id);
    expect(new Set(ids).size).toBe(ids.length);
  });

  it('pins the length boundaries at MAX_REDIRECT_LENGTH', () => {
    const atCap = REDIRECT_CASES.find((c) => c.id === 'length-at-cap');
    const overCap = REDIRECT_CASES.find((c) => c.id === 'length-over-cap');
    expect(atCap?.input.length).toBe(MAX_REDIRECT_LENGTH);
    expect(overCap?.input.length).toBe(MAX_REDIRECT_LENGTH + 1);
  });
});

describe('isValidInternalPath', () => {
  describe('against tests/fixtures/redirect_path_cases.json', () => {
    // One test per case, named by the fixture id, so a failure names the
    // offending case and the Ruby half can be checked against the same name.
    for (const kase of REDIRECT_CASES) {
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
