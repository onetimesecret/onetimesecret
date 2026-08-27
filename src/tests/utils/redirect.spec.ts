// src/tests/utils/redirect.spec.ts

import {
  isAllowedCheckoutUrl,
  isValidInternalPath,
  setAllowedCheckoutHost,
} from '@/utils/redirect';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';

/**
 * isValidInternalPath is the ONLY redirect validator now — the former
 * validateRedirect / validatePathString / validateUrl trio was dead code for
 * the `?redirect=` param (nothing but this file referenced it) and permitted
 * things this ruleset must reject: control characters, absolute same-host URLs,
 * and protocol-relative input.
 *
 * The identical ruleset is implemented in Ruby on the backend (signup stores a
 * validated redirect, verify-account replays it). Every case below is a parity
 * case: if one side changes, both specs should.
 */
describe('isValidInternalPath', () => {
  describe('accepts', () => {
    it('plain internal paths', () => {
      expect(isValidInternalPath('/')).toBe(true);
      expect(isValidInternalPath('/dashboard')).toBe(true);
      expect(isValidInternalPath('/users/123/profile')).toBe(true);
      expect(isValidInternalPath('/path-with-hyphens')).toBe(true);
      expect(isValidInternalPath('/path_with_underscores')).toBe(true);
    });

    it('a query string and hash, intact (the whole point of the string form)', () => {
      expect(isValidInternalPath('/secret/abc?view=raw')).toBe(true);
      expect(isValidInternalPath('/secret/abc#content')).toBe(true);
      expect(isValidInternalPath('/secret/abc?view=raw#content')).toBe(true);
      expect(isValidInternalPath('/search?q=a%20b&sort=desc#results')).toBe(true);
    });

    it('percent-encoded characters that decode to something harmless', () => {
      expect(isValidInternalPath('/path%20with%20spaces')).toBe(true);
      expect(isValidInternalPath('/caf%C3%A9')).toBe(true);
    });

    it('a `..` substring that is not its own segment', () => {
      // Traversal is a SEGMENT, not a substring: these resolve to themselves.
      expect(isValidInternalPath('/reports/..data')).toBe(true);
      expect(isValidInternalPath('/a/b..c/d')).toBe(true);
      expect(isValidInternalPath('/search?q=a..b')).toBe(true);
      // Not slash-delimited, so it is not a segment on either side.
      expect(isValidInternalPath('/search?q=..')).toBe(true);
    });

    it('a path of exactly the length limit', () => {
      expect(isValidInternalPath('/' + 'a'.repeat(2047))).toBe(true);
    });
  });

  describe('rejects', () => {
    it('non-strings and empty input', () => {
      expect(isValidInternalPath(undefined)).toBe(false);
      expect(isValidInternalPath(null)).toBe(false);
      expect(isValidInternalPath('')).toBe(false);
      expect(isValidInternalPath(123 as unknown as string)).toBe(false);
      expect(isValidInternalPath({} as unknown as string)).toBe(false);
      expect(isValidInternalPath([] as unknown as string)).toBe(false);
    });

    it('anything over 2048 characters', () => {
      expect(isValidInternalPath('/' + 'a'.repeat(2048))).toBe(false);
    });

    it('paths not anchored at a single leading slash', () => {
      expect(isValidInternalPath('dashboard')).toBe(false);
      expect(isValidInternalPath('   /dashboard')).toBe(false);
      expect(isValidInternalPath('../dashboard')).toBe(false);
    });

    it('protocol-relative and backslash-disguised authorities', () => {
      // '//evil.example' and '/\evil.example' both leave the origin — browsers
      // normalize the backslash to a slash.
      expect(isValidInternalPath('//evil.example')).toBe(false);
      expect(isValidInternalPath('//evil.example/path')).toBe(false);
      expect(isValidInternalPath('/\\evil.example')).toBe(false);
      expect(isValidInternalPath('/\\/evil.example')).toBe(false);
    });

    it('a backslash anywhere in the path', () => {
      expect(isValidInternalPath('/a\\b')).toBe(false);
      expect(isValidInternalPath('/dashboard?next=\\\\evil.example')).toBe(false);
    });

    it('absolute URLs and any embedded `://`', () => {
      expect(isValidInternalPath('https://evil.example/dashboard')).toBe(false);
      // Same-origin absolute URLs are rejected too: this validator returns
      // PATHS for router.push, and an origin is not our concern here.
      expect(isValidInternalPath('https://example.com/dashboard')).toBe(false);
      expect(isValidInternalPath('javascript://example.com')).toBe(false);
      expect(isValidInternalPath('/redirect?to=https://evil.example')).toBe(false);
      expect(isValidInternalPath('/a://b')).toBe(false);
    });

    it('raw control characters (CR/LF/NUL/DEL) — header and request splitting', () => {
      expect(isValidInternalPath('/path\nwith\nnewlines')).toBe(false);
      expect(isValidInternalPath('/path\rwith\rreturns')).toBe(false);
      expect(isValidInternalPath('/path\x00with\x00nulls')).toBe(false);
      expect(isValidInternalPath('/path\x1funit-separator')).toBe(false);
      expect(isValidInternalPath('/path\x7fdel')).toBe(false);
      expect(isValidInternalPath('/tab\there')).toBe(false);
    });

    it('control characters smuggled in as percent-encoding', () => {
      expect(isValidInternalPath('/%0D%0ASet-Cookie:%20x=y')).toBe(false);
      expect(isValidInternalPath('/%00')).toBe(false);
      expect(isValidInternalPath('/%7F')).toBe(false);
    });

    it('an encoded backslash or encoded protocol-relative prefix', () => {
      expect(isValidInternalPath('/%5Cevil.example')).toBe(false);
      expect(isValidInternalPath('/%2F%2Fevil.example')).toBe(false);
      expect(isValidInternalPath('/%2f%2fevil.example')).toBe(false);
    });

    it('path traversal, raw or encoded', () => {
      expect(isValidInternalPath('/../../etc/passwd')).toBe(false);
      expect(isValidInternalPath('/a/../b')).toBe(false);
      expect(isValidInternalPath('/%2e%2e/config')).toBe(false);
      expect(isValidInternalPath('/a/%2E%2E/b')).toBe(false);
      expect(isValidInternalPath('/dashboard/..')).toBe(false);
    });

    it('a `..` segment reached through the query or fragment (backend parity)', () => {
      // The whole decoded string is split on '/', query and fragment included,
      // exactly as RedirectPaths#traversal_segment? does. A bare '?q=..' is
      // still fine (it is not delimited by slashes) — see the accepts block.
      expect(isValidInternalPath('/a?next=/../b')).toBe(false);
      expect(isValidInternalPath('/a#/..')).toBe(false);
      expect(isValidInternalPath('/a?next=%2F..%2Fb')).toBe(false);
    });

    it('malformed percent-encoding, rather than guessing at intent', () => {
      expect(isValidInternalPath('/%')).toBe(false);
      expect(isValidInternalPath('/%zz')).toBe(false);
      expect(isValidInternalPath('/%E0%A4%A')).toBe(false);
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
