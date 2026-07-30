// src/tests/plugins/core/diagnostics/emailPatternUnicode.spec.ts
//
// Unicode widening of the Sentry email redactor (EMAIL_PATTERN in
// src/plugins/core/diagnostics/scrubbers.ts).
//
// WHY THIS SUITE EXISTS
// The validator (Truemail's REGEX_EMAIL_PATTERN) accepts `\p{L}` on both sides
// of the `@` and a `\p{L}{2,63}` TLD, so `josé@example.com`, `用户@example.com`
// and `user@пример.рф` are all STORABLE. The redactor was ASCII-only, matched
// none of them, and they reached Sentry in the clear. A redactor narrower than
// the validator is a leak by construction.
//
// This suite pins the widened behaviour of the TS half specifically:
//   1. the previously-leaking unicode shapes are now fully redacted
//   2. nothing the validator REJECTS became redacted (over-redaction guard)
//   3. ops-useful strings still survive the pass
//   4. the email-before-identifier ordering invariant still holds
//   5. the TS pattern is still byte-identical to its Ruby mirror
//
// Deliberately NOT the shared-corpus test — tests/fixtures/email_redaction_corpus.json
// is driven by its own suite. This one is the scrubbers.ts-local contract.

import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { beforeEach, describe, expect, it } from 'vitest';

import {
  EMAIL_PATTERN,
  scrubQueryStringValues,
  scrubSensitiveStrings,
  scrubUrlWithPatterns,
} from '@/plugins/core/diagnostics/scrubbers';

const SENTINEL = '[EMAIL_REDACTED]';

/** EMAIL_PATTERN carries the `g` flag, so `lastIndex` is stateful across
 *  direct `.test()`/`.exec()` calls. `replace` resets it; assertions here do
 *  not rely on that. */
beforeEach(() => {
  EMAIL_PATTERN.lastIndex = 0;
});

describe('EMAIL_PATTERN flags', () => {
  it('carries both `g` (replace-all) and `u` (\\p{...} support)', () => {
    expect(EMAIL_PATTERN.flags).toBe('gu');
    expect(EMAIL_PATTERN.unicode).toBe(true);
    expect(EMAIL_PATTERN.global).toBe(true);
  });

  it('replaces every address in a string, not just the first', () => {
    expect(scrubSensitiveStrings('a: josé@example.com b: 用户@example.com')).toBe(
      `a: ${SENTINEL} b: ${SENTINEL}`
    );
  });
});

describe('EMAIL_PATTERN unicode widening — previously leaked, now redacted', () => {
  // Every address here is accepted by Truemail (therefore storable) and was
  // matched by NONE of the old ASCII-only pattern.
  const PREVIOUSLY_LEAKED = [
    ['latin-1 accented local part (NFC)', 'josé@example.com'],
    ['uppercase non-ASCII local part', 'JOSÉ@EXAMPLE.COM'],
    ['CJK local part', '用户@example.com'],
    ['Cyrillic local part', 'пользователь@example.com'],
    ['IDN host with non-ASCII TLD', 'user@пример.рф'],
    ['ASCII host with non-ASCII TLD', 'user@example.онлайн'],
    ['mixed ASCII/non-ASCII host labels', 'user@mail.пример.рф'],
  ] as const;

  it.each(PREVIOUSLY_LEAKED)('%s: %s is fully redacted', (_label, address) => {
    expect(scrubSensitiveStrings(address)).toBe(SENTINEL);
  });

  it.each(PREVIOUSLY_LEAKED)('%s: %s leaves no residue in free text', (_label, address) => {
    const scrubbed = scrubSensitiveStrings(`Signup failed for ${address} (code 42)`);
    expect(scrubbed).toBe(`Signup failed for ${SENTINEL} (code 42)`);
    expect(scrubbed).not.toContain(address);
    // The domain half must not survive on its own either.
    expect(scrubbed).not.toContain(address.split('@')[1]);
  });

  it.each(PREVIOUSLY_LEAKED)('%s: %s is redacted inside a query value', (_label, address) => {
    expect(scrubQueryStringValues(`?email=${address}&x=1`)).toBe(`?email=${SENTINEL}&x=1`);
  });

  it.each(PREVIOUSLY_LEAKED)('%s: %s is redacted inside a URL', (_label, address) => {
    expect(scrubUrlWithPatterns(`https://app.example.com/verify?email=${address}`)).toBe(
      `https://app.example.com/verify?email=${SENTINEL}`
    );
  });

  it('still redacts the ASCII shapes it always handled', () => {
    expect(scrubSensitiveStrings('user.name+tag@sub.example.co.uk')).toBe(SENTINEL);
    expect(scrubSensitiveStrings('Mixed.Case@Example.COM')).toBe(SENTINEL);
    // Shortest storable address (Truemail enforces a 6-char minimum). The
    // partial-mask redactor leaves this byte-identical; the full-sentinel
    // redactor must not.
    expect(scrubSensitiveStrings('a@b.co')).toBe(SENTINEL);
  });
});

describe('EMAIL_PATTERN over-redaction guard — validator-rejected shapes survive', () => {
  // None of these is storable, and redacting them costs operators real signal.
  const MUST_NOT_MATCH = [
    ['single-label host', 'user@localhost'],
    ['social handle / decorator', '@handle'],
    ['no dotted domain', 'a@b'],
    ['numeric TLD (version/coordinate strings)', '1.2@3.4'],
    ['bare hostname, no @', 'no-at-sign.example.com'],
    ['one-letter TLD', 'foo@bar.c'],
    ['unicode both sides, no TLD', 'подписка@сайт'],
    ['unicode single-label host', 'test@пример'],
  ] as const;

  it.each(MUST_NOT_MATCH)('%s: %s is left untouched', (_label, text) => {
    expect(scrubSensitiveStrings(text)).toBe(text);
  });

  it('leaves the widened classes unable to match without a dotted TLD', () => {
    // The unicode classes are the new risk surface: assert directly on the
    // pattern, not only through the scrub entry point.
    for (const [, text] of MUST_NOT_MATCH) {
      EMAIL_PATTERN.lastIndex = 0;
      expect(text.match(EMAIL_PATTERN)).toBeNull();
    }
  });
});

describe('EMAIL_PATTERN over-redaction guard — ops-useful strings survive', () => {
  const OPS_STRINGS = [
    'at Foo::Bar#baz (/app/lib/onetime/logic/base.rb:107:in `validate\')',
    '/Users/d/Projects/dev/onetimesecret/lib/onetime/utils/strings.rb',
    'Onetime::Utils::Strings::EMAIL_PATTERN',
    'commit 9ebdbd0374a1f2c3d4e5f60718293a4b5c6d7e8f',
    '2026-07-30T12:34:56.789Z',
    '2026-07-30 12:34:56 +0000',
    'TypeError: Cannot read properties of undefined (reading \'email\')',
    '@media (prefers-color-scheme: dark)',
    'redis://127.0.0.1:6379/0',
    'v1.2.3-rc.4',
    'ruby 3.4.10 (2026-01-15 revision abc1234) [arm64-darwin27]',
  ];

  it.each(OPS_STRINGS)('survives the email pass: %s', (text) => {
    EMAIL_PATTERN.lastIndex = 0;
    expect(text.match(EMAIL_PATTERN)).toBeNull();
  });

  it('keeps a bare host readable when no address is attached', () => {
    // `app.example.com` has no `@` before it and must survive, even though the
    // query value next to it is an address.
    expect(
      scrubSensitiveStrings('https://app.example.com/verify?email=user@example.com&token=abc')
    ).toContain('app.example.com');
  });
});

describe('ordering invariant survives the widening', () => {
  // scrubbers.ts documents this in three places: the email pass MUST run before
  // the identifier pass. An ID-shaped local part would otherwise be replaced
  // first, leaving `[REDACTED]@domain` — which EMAIL_PATTERN can no longer
  // match, leaking the domain.
  const ID62 = 'a'.repeat(62);

  it('scrubSensitiveStrings redacts an ID-shaped local part as an email', () => {
    const result = scrubSensitiveStrings(`${ID62}@example.com`);
    expect(result).toBe(SENTINEL);
    expect(result).not.toContain('example.com');
  });

  it('holds for an ID-shaped local part on a widened unicode domain', () => {
    // Regression guard specific to this change: before the widening the email
    // pass could not match `<id>@пример.рф`, so the identifier pass won and the
    // IDN domain leaked.
    const result = scrubSensitiveStrings(`${ID62}@пример.рф`);
    expect(result).toBe(SENTINEL);
    expect(result).not.toContain('пример.рф');
  });

  it('holds in scrubQueryStringValues', () => {
    expect(scrubQueryStringValues(`?from=${ID62}@пример.рф`)).toBe(`?from=${SENTINEL}`);
  });

  it('holds in scrubUrlWithPatterns', () => {
    expect(scrubUrlWithPatterns(`https://example.com/?from=${ID62}@пример.рф`)).toBe(
      'https://example.com/?from=[EMAIL_REDACTED]'
    );
  });

  it('emits only whitespace-free sentinels so later path passes compose', () => {
    expect(SENTINEL).toMatch(/^\[[A-Z_]+\]$/);
    expect(scrubSensitiveStrings('用户@example.com')).toMatch(/^\[[A-Z_]+\]$/);
  });
});

describe('backend mirror', () => {
  // The Ruby half assembles the same Sentry payloads. A widening applied to
  // only one half still leaks, so the two literals must stay byte-identical.
  it('is byte-identical to EMAIL_PATTERN in setup_diagnostics.rb', () => {
    const rubySource = readFileSync(
      resolve(process.cwd(), 'lib/onetime/initializers/setup_diagnostics.rb'),
      'utf8'
    );
    const rubyLine = rubySource
      .split('\n')
      .find((line) => /^\s*EMAIL_PATTERN\s*=\s*\//.test(line));
    expect(rubyLine, 'EMAIL_PATTERN literal not found in setup_diagnostics.rb').toBeTruthy();

    const rubyLiteral = rubyLine!.match(/=\s*\/(.*)\/\s*$/);
    expect(rubyLiteral, `could not slice the Ruby literal out of: ${rubyLine}`).toBeTruthy();

    expect(rubyLiteral![1]).toBe(EMAIL_PATTERN.source);
  });

  it('uses the same sentinel as the backend', () => {
    const rubySource = readFileSync(
      resolve(process.cwd(), 'lib/onetime/initializers/setup_diagnostics.rb'),
      'utf8'
    );
    expect(rubySource).toContain("'[EMAIL_REDACTED]'");
  });
});

describe('no catastrophic backtracking', () => {
  // The widened classes overlap (`[\p{L}\p{N}.\p{Pd}]` contains `.` and the TLD
  // letters), so this is worth pinning: every quantifier is a single pass over
  // a character class with a literal separating it from the next, giving
  // polynomial — not exponential — worst case.
  it.each([
    ['long run with no @', 'a'.repeat(20000)],
    ['long local part, unmatchable tail', `${'a'.repeat(20000)}@${'!'.repeat(50)}`],
    ['many dotted labels, no valid TLD', `u@${'a.'.repeat(5000)}`],
    ['many unicode dotted labels', `ю@${'я.'.repeat(2000)}`],
  ])('%s completes quickly', (_label, input) => {
    const start = performance.now();
    input.replace(EMAIL_PATTERN, SENTINEL);
    expect(performance.now() - start).toBeLessThan(5000);
  });
});
