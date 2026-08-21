// src/tests/plugins/core/diagnostics/opaqueIdentifierPatterns.spec.ts
//
// DIRECT tests for the opaque-identifier nets in
// src/plugins/core/diagnostics/scrubbers.ts.
//
// Each of these constants is exported and annotated "@internal Exported for
// testing", and until now none of them had a single reference in src/tests —
// the annotation promised a test suite that did not exist. They were covered
// only indirectly, through `scrubSensitiveStrings`, which composes six nets in
// a fixed order: a failure there says "something scrubbed the wrong thing"
// without saying WHICH net, and a net that quietly widened could be masked by
// an earlier one consuming the text first.
//
// The nets are load-bearing in BOTH directions, so both directions are pinned
// here. An over-broad net degrades every event this app sends (the false
// positives below are real strings from this tree — schema field names, version
// numbers, Ruby constant paths, trace ids); an under-broad one leaks. Every
// vector below is taken from a documented claim on the pattern it exercises.
//
// Run:
//   pnpm vitest run src/tests/plugins/core/diagnostics/opaqueIdentifierPatterns.spec.ts

import { describe, expect, it } from 'vitest';

import {
  IPV4_PATTERN,
  IPV6_PATTERN,
  OTS_EXTID_PATTERN,
  PREFIXED_ID_PATTERN,
  PREFIXED_SECRET_PATTERN,
  UUID_PATTERN,
} from '@/plugins/core/diagnostics/scrubbers';

/**
 * Every pattern here is `g`-flagged, which makes `RegExp.prototype.test`
 * STATEFUL: it resumes from `lastIndex` and therefore alternates true/false on
 * repeated calls with the same input. Resetting before each probe is what makes
 * the assertions below mean what they say.
 */
const matches = (pattern: RegExp, input: string): boolean => {
  pattern.lastIndex = 0;
  return pattern.test(input);
};

/** All matches, as strings, with the same statefulness hygiene. */
const allMatches = (pattern: RegExp, input: string): string[] => {
  pattern.lastIndex = 0;
  return input.match(pattern) ?? [];
};

describe('opaque-identifier patterns (direct)', () => {
  describe('the g-flag hazard the helpers exist for', () => {
    it('is real: consecutive .test() calls on one input alternate', () => {
      PREFIXED_SECRET_PATTERN.lastIndex = 0;
      const first = PREFIXED_SECRET_PATTERN.test('sk_live_SUPER_SECRET');
      const second = PREFIXED_SECRET_PATTERN.test('sk_live_SUPER_SECRET');
      expect(first).toBe(true);
      expect(second).toBe(false);
      PREFIXED_SECRET_PATTERN.lastIndex = 0;
    });

    it('is neutralized by the helper', () => {
      expect(matches(PREFIXED_SECRET_PATTERN, 'sk_live_SUPER_SECRET')).toBe(true);
      expect(matches(PREFIXED_SECRET_PATTERN, 'sk_live_SUPER_SECRET')).toBe(true);
    });
  });

  describe('PREFIXED_SECRET_PATTERN', () => {
    it.each([
      ['sk_live_SUPER_SECRET', 'Stripe secret key'],
      ['pk_test_51H8xKzABCdef', 'Stripe publishable key'],
      ['rk_live_restrictedkey1', 'Stripe restricted key'],
      ['whsec_abc123DEF456ghi', 'webhook signing secret'],
    ])('matches %s (%s)', (vector) => {
      expect(matches(PREFIXED_SECRET_PATTERN, vector)).toBe(true);
    });

    it('consumes the key WHOLE, underscores included', () => {
      // The documented reason the body class is loose: a narrower class would
      // stop at the first `_` and ship the tail.
      expect(allMatches(PREFIXED_SECRET_PATTERN, 'key=sk_live_SUPER_SECRET end')).toEqual([
        'sk_live_SUPER_SECRET',
      ]);
    });

    it.each([
      ['risk_score', 'no word boundary before sk_'],
      ['sk_abc', 'body shorter than 6'],
      ['[SECRET_REDACTED]', 'its own sentinel (case-sensitive prefix)'],
      ['SK_LIVE_ABCDEFG', 'SCREAMING_CASE constant'],
    ])('does NOT match %s (%s)', (vector) => {
      expect(matches(PREFIXED_SECRET_PATTERN, vector)).toBe(false);
    });
  });

  describe('PREFIXED_ID_PATTERN', () => {
    it.each([
      ['org_9f3a2b1c8d7e6f50', 'organization id'],
      ['cus_NffrFeUfNV2Hib', 'Stripe customer'],
      ['sub_1P4kLdGtEXAMPLE', 'Stripe subscription'],
      ['price_1MoBy5LkdIwHu7ix', 'Stripe price'],
    ])('matches %s (%s)', (vector) => {
      expect(matches(PREFIXED_ID_PATTERN, vector)).toBe(true);
    });

    // These are FIELD NAMES from this codebase. Redacting them destroys the
    // schema-failure diagnostic this whole telemetry boundary exists to deliver
    // — `subscription_period_end` is literally the bug this branch was opened
    // for.
    it.each([
      ['org_id', 'too short (<6 body)'],
      ['org_context', 'no digit and no uppercase'],
      ['price_formatted', 'no digit and no uppercase'],
      ['price_metadata', 'no digit and no uppercase'],
      ['price_nickname', 'no digit and no uppercase'],
      ['sub_total', 'no digit and no uppercase'],
      ['subscription_period_end', 'sub is followed by s, not _'],
    ])('does NOT match %s (%s)', (vector) => {
      expect(matches(PREFIXED_ID_PATTERN, vector)).toBe(false);
    });

    it('preserves the field name while redacting the id in one string', () => {
      expect(allMatches(PREFIXED_ID_PATTERN, 'sub_total for cus_NffrFeUfNV2Hib')).toEqual([
        'cus_NffrFeUfNV2Hib',
      ]);
    });
  });

  describe('OTS_EXTID_PATTERN', () => {
    const base36 = 'a1b2c3d4e5f6g7h8i9j0k1l2m'; // exactly 25 chars

    it.each([
      [`ur${base36}`, 'Customer extid'],
      [`cd${base36}`, 'CustomDomain extid'],
      [`on${base36}`, 'Organization extid'],
    ])('matches %s (%s)', (vector) => {
      expect(matches(OTS_EXTID_PATTERN, vector)).toBe(true);
    });

    it.each([
      [`ur${base36.slice(0, 24)}`, '24 body chars — length is exact'],
      [`ur${base36}x`, '26 body chars — length is exact'],
      [`ur${base36.toUpperCase()}`, 'uppercase — generation is lowercase'],
      ['xx' + base36, 'unknown two-letter prefix'],
    ])('does NOT match %s (%s)', (vector) => {
      expect(matches(OTS_EXTID_PATTERN, vector)).toBe(false);
    });
  });

  describe('UUID_PATTERN', () => {
    it('matches a canonical hyphenated UUID', () => {
      expect(matches(UUID_PATTERN, '3f2504e0-4f89-11d3-9a0c-0305e82c3301')).toBe(true);
    });

    it('matches regardless of hex case', () => {
      expect(matches(UUID_PATTERN, '3F2504E0-4F89-11D3-9A0C-0305E82C3301')).toBe(true);
    });

    // The hyphens are load-bearing EVIDENCE, not decoration: these two shapes
    // are ops-useful and are not personal data.
    it.each([
      ['c'.repeat(32), 'bare 32-hex — indistinguishable from a trace_id'],
      ['d'.repeat(40), '40-hex — a git commit sha'],
      ['3f2504e0-4f89-11d3-9a0c-0305e82c330', 'one hex short of a UUID'],
    ])('does NOT match %s (%s)', (vector) => {
      expect(matches(UUID_PATTERN, vector)).toBe(false);
    });
  });

  describe('IPV4_PATTERN', () => {
    it.each([
      ['192.168.1.1', 'RFC1918 — where real client addresses live in self-hosted'],
      ['203.0.113.5', 'documentation range'],
      ['127.0.0.1', 'loopback still MATCHES the pattern (the caller exempts it)'],
    ])('matches %s (%s)', (vector) => {
      expect(matches(IPV4_PATTERN, vector)).toBe(true);
    });

    it.each([
      ['10.0.19041.1', 'a Windows build string — 19041 is not an octet'],
      ['v1.2.3-rc.4', 'a version string — the lookbehind blocks the 1.2.3 run'],
      ['1.2.3.4.5', 'five parts — the trailing fence rejects it'],
      ['256.1.1.1', 'out-of-range octet, and no legal later start offset'],
    ])('does NOT match %s (%s)', (vector) => {
      expect(matches(IPV4_PATTERN, vector)).toBe(false);
    });
  });

  describe('IPV6_PATTERN', () => {
    it.each([
      ['2001:db8::1', 'compressed documentation address'],
      ['fe80::1', 'link-local'],
      ['2001:0db8:85a3:0000:0000:8a2e:0370:7334', 'full eight-group form'],
    ])('matches %s (%s)', (vector) => {
      expect(matches(IPV6_PATTERN, vector)).toBe(true);
    });

    // Ruby stack frames are a primary input to the scrubber, so constant paths
    // with `::` are the false positive that matters most here.
    it.each([
      ['Db::add', 'Ruby scope operator — uppercase'],
      ['Cafe::Face', 'Ruby scope operator that is also valid hex'],
      ['bad::face', 'all-letter token — no digit'],
      ['12:34:56', 'a clock time — three groups, no ::'],
    ])('does NOT match %s (%s)', (vector) => {
      expect(matches(IPV6_PATTERN, vector)).toBe(false);
    });
  });
});
