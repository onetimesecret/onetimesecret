// src/tests/plugins/core/diagnostics/emailRedactionCorpus.spec.ts
//
// EMAIL REDACTION INVARIANT — the shared-corpus suite (TypeScript half).
//
// THE INVARIANT
//   Every address the VALIDATOR accepts must be redacted by EVERY redactor.
//   The validator (Truemail's REGEX_EMAIL_PATTERN, backend) defines what is
//   STORABLE. A redactor narrower than the validator prints stored data in the
//   clear — that is not a cosmetic gap, it is a leak by construction.
//
// THE LEAK THIS SUITE EXISTS TO CATCH
//   `josé@example.com` is accepted by Truemail (storable) and was matched by
//   NONE of the redactors, so it rode out to Sentry in the clear. If the
//   pattern here is ever narrowed again, THIS FILE goes red and names the
//   address.
//
// WHAT THIS FILE OWNS
//   The TS half of the Sentry scrubber — EMAIL_PATTERN in
//   src/plugins/core/diagnostics/scrubbers.ts — asserted against
//   tests/fixtures/email_redaction_corpus.json, the SAME language-neutral
//   corpus the Ruby half reads (try/unit/utils/email_redaction_corpus_try.rb).
//
//   Deliberately NOT the same file as emailPatternUnicode.spec.ts: that suite
//   is the scrubbers.ts-local contract (flags, ordering, ReDoS, entry points).
//   This one is the cross-language specification.
//
// CROSS-LANGUAGE EQUALITY
//   scrubbers.ts EMAIL_PATTERN and setup_diagnostics.rb EMAIL_PATTERN are a
//   deliberate, documented mirror: same source, same sentinel, flags the only
//   permitted difference. A Sentry payload can be assembled by either half, so
//   a widening applied to only one half still leaks.
//
//   This suite does NOT hardcode a second copy of the backend's behaviour. It
//   reads setup_diagnostics.rb from disk, slices out the shipped regex literal
//   and the shipped sentinel, and rebuilds the backend pass from those. Every
//   corpus row is then asserted BYTE-IDENTICAL between the two halves. The TS
//   sentinel is likewise derived by calling the real exported scrubber rather
//   than being typed out again, so changing the sentinel in scrubbers.ts turns
//   the equality assertions red instead of sliding past them.
//
//   (Note the limit of what an in-process check can prove: it compares two
//   regexes compiled by V8. Onigmo-vs-V8 semantic divergence is caught by the
//   OTHER direction — both halves independently assert the same corpus-derived
//   expected output, so an engine that disagreed on a corpus shape would fail
//   its own contract block.)
//
// HOW FAILURES READ
//   Every case is generated per corpus entry via `it.each`, so the test NAME
//   carries the entry id and the address. Every assertion also passes an
//   explicit message naming the address and the redactor. `expected true,
//   got false` on a 30-entry corpus is what this format exists to avoid.

import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

import { EMAIL_PATTERN, scrubSensitiveStrings } from '@/plugins/core/diagnostics/scrubbers';

// ---------------------------------------------------------------- the corpus

interface CorpusEntry {
  id: string;
  input: string;
  kind: 'accepted' | 'embedded' | 'rejected' | 'informational';
  truemail_accepts: boolean;
  contains: string[];
  probes?: string;
  partial_mask_head_exempt?: { local?: boolean; host?: boolean };
}

const REPO_ROOT = process.cwd();
const CORPUS_PATH = resolve(REPO_ROOT, 'tests/fixtures/email_redaction_corpus.json');
const RUBY_TWIN_PATH = resolve(REPO_ROOT, 'lib/onetime/initializers/setup_diagnostics.rb');

const corpus = JSON.parse(readFileSync(CORPUS_PATH, 'utf8')) as {
  entries: CorpusEntry[];
};

/** Addresses the validator accepts (kind=accepted) or accepts inside free text
 *  (kind=embedded). Every one of these MUST be redacted. */
const MUST_REDACT = corpus.entries.filter((e) => e.contains.length > 0);

/** Entries the validator REJECTS. Not storable, so redacting them costs
 *  operators signal for no privacy gain: they must pass through UNCHANGED.
 *  kind=informational is excluded — the corpus states those are unasserted. */
const MUST_NOT_REDACT = corpus.entries.filter((e) => e.kind === 'rejected');

/** The addresses that actually leaked. Pinned by literal so that deleting them
 *  from the corpus turns this suite RED instead of quietly green — an eroded
 *  corpus is the one failure mode a corpus-driven suite cannot self-detect. */
const HISTORICAL_LEAKS = [
  'josé@example.com',
  'JOSÉ@EXAMPLE.COM',
  '用户@example.com',
  'пользователь@example.com',
  'user@пример.рф',
  'user@example.онлайн',
  'user@mail.пример.рф',
];

// ------------------------------------------------- the two halves under test

/** Derived from the shipped code, never typed out: whatever scrubbers.ts
 *  actually substitutes today. A sentinel change in scrubbers.ts changes this
 *  value, and the cross-language sentinel assertion below then fails. */
const TS_SENTINEL = scrubSensitiveStrings('user@example.com');

const rubySource = readFileSync(RUBY_TWIN_PATH, 'utf8');

/** The Ruby half's regex literal, sliced out of the shipped file. Fails closed:
 *  if the literal grows a flag or moves, the match is null and the mirror tests
 *  error rather than passing silently. */
const rubyPatternMatch = rubySource
  .split('\n')
  .find((line) => /^\s*EMAIL_PATTERN\s*=\s*\//.test(line))
  ?.match(/=\s*\/(.*)\/\s*$/);

/** The Ruby half's sentinel, sliced from its single substitution site. */
const rubySentinelMatch = rubySource.match(/gsub\(EMAIL_PATTERN,\s*'([^']*)'\)/);

const rubyPatternSource = rubyPatternMatch?.[1];
const rubySentinel = rubySentinelMatch?.[1];

/** The backend email pass, rebuilt from the backend's own shipped literal.
 *  `gu` because ECMAScript needs `u` for \p{...} and `g` for replace-all —
 *  the documented, and only permitted, difference from the Ruby half. */
function backendEmailPass(text: string): string {
  if (rubyPatternSource === undefined || rubySentinel === undefined) {
    throw new Error(
      `could not read the Ruby mirror out of ${RUBY_TWIN_PATH} ` +
        `(pattern=${String(rubyPatternSource)}, sentinel=${String(rubySentinel)})`
    );
  }
  return text.replace(new RegExp(rubyPatternSource, 'gu'), rubySentinel);
}

/** Expected output derived from the shared contract: each address the
 *  validator accepts is replaced by the sentinel; everything else survives. */
function expectedFullSentinelOutput(entry: CorpusEntry, sentinel: string): string {
  return entry.contains.reduce((acc, address) => acc.split(address).join(sentinel), entry.input);
}

// ------------------------------------------------------------------- corpus

describe('corpus integrity', () => {
  it('loads entries from the shared, language-neutral fixture', () => {
    expect(corpus.entries.length, `no entries in ${CORPUS_PATH}`).toBeGreaterThan(0);
    expect(MUST_REDACT.length).toBeGreaterThan(0);
    expect(MUST_NOT_REDACT.length).toBeGreaterThan(0);
  });

  it.each(HISTORICAL_LEAKS)('still carries the address that leaked: %s', (address) => {
    const hit = corpus.entries.find((e) => e.input === address && e.kind === 'accepted');
    expect(
      hit,
      `CORPUS EROSION: ${address} is one of the addresses that actually leaked, and it is no ` +
        `longer in ${CORPUS_PATH} as kind=accepted. Restore it — deleting a shape from the ` +
        `corpus silences every assertion in BOTH languages.`
    ).toBeDefined();
  });

  it.each(corpus.entries.map((e) => [e.id, e] as const))(
    '%s carries the keys both languages read',
    (_id, entry) => {
      expect(typeof entry.input).toBe('string');
      expect(typeof entry.kind).toBe('string');
      expect(Array.isArray(entry.contains)).toBe(true);
    }
  );

  /** kind=informational may only ever hold validator-REJECTED, contains-empty
   *  shapes. It records don't-care over-redaction; a storable address
   *  downgraded to informational (with contains emptied) would be unasserted
   *  in BOTH languages — the one route by which this category could swallow a
   *  leak. */
  it.each(corpus.entries.filter((e) => e.kind === 'informational').map((e) => [e.id, e] as const))(
    '%s — informational entries stay validator-rejected and unasserted',
    (id, entry) => {
      expect(
        entry.truemail_accepts,
        `entry=${id} is kind=informational but truemail_accepts=${entry.truemail_accepts} — a ` +
          `storable address must be kind=accepted so its redaction is asserted; informational ` +
          `is only for validator-rejected shapes.`
      ).toBe(false);
      expect(
        entry.contains,
        `entry=${id} is kind=informational but lists contains=${JSON.stringify(entry.contains)} — ` +
          `MUST_REDACT keys off contains, so this entry would be asserted by the leak suites ` +
          `while every kind-filtered suite skips it. Make it accepted/embedded, or empty contains.`
      ).toEqual([]);
    }
  );
});

// ------------------------------------------------------ the invariant itself

describe('TS scrubber redacts every address the validator accepts', () => {
  it.each(
    MUST_REDACT.flatMap((entry) =>
      entry.contains.map((address) => [entry.id, address, entry] as const)
    )
  )('%s — %s', (id, address, entry) => {
    const actual = scrubSensitiveStrings(entry.input);

    expect(
      actual.includes(address),
      `LEAK/[TS scrubbers.ts] entry=${id} address=${JSON.stringify(address)} survived VERBATIM in ` +
        `the Sentry-bound output ${JSON.stringify(actual)}. The validator ACCEPTS this address, so ` +
        `it is storable, and a redactor narrower than the validator prints stored data in the clear.`
    ).toBe(false);

    expect(
      actual.includes(TS_SENTINEL),
      `LEAK/[TS scrubbers.ts] entry=${id} address=${JSON.stringify(address)} — no ${TS_SENTINEL} ` +
        `sentinel in ${JSON.stringify(actual)}; nothing was redacted at all.`
    ).toBe(true);
  });

  it.each(MUST_REDACT.map((e) => [e.id, e] as const))(
    '%s — surrounding text survives, addresses do not',
    (id, entry) => {
      const expected = expectedFullSentinelOutput(entry, TS_SENTINEL);
      expect(
        scrubSensitiveStrings(entry.input),
        `entry=${id}: expected every contained address replaced by the sentinel with the ` +
          `surrounding text untouched, for input ${JSON.stringify(entry.input)}`
      ).toBe(expected);
    }
  );
});

describe('TS scrubber does NOT touch what the validator rejects', () => {
  // Over-redaction is not free: these shapes are ops signal (hostnames,
  // version strings, CSS at-rules, dev-mode SMTP addresses). None of them is
  // storable, so redacting them buys no privacy and costs debuggability.
  it.each(MUST_NOT_REDACT.map((e) => [e.id, e] as const))(
    '%s passes through unchanged',
    (id, entry) => {
      expect(
        scrubSensitiveStrings(entry.input),
        `OVER-REDACTION/[TS scrubbers.ts] entry=${id} input=${JSON.stringify(entry.input)} — the ` +
          `validator REJECTS this, so it is not storable and must survive. ${entry.probes ?? ''}`
      ).toBe(entry.input);
    }
  );
});

// ------------------------------------------- cross-language byte-identity

describe('cross-language mirror with lib/onetime/initializers/setup_diagnostics.rb', () => {
  it('reads the Ruby half off disk', () => {
    expect(
      rubyPatternSource,
      `EMAIL_PATTERN literal not found in ${RUBY_TWIN_PATH} — the mirror assertions cannot run, ` +
        `which is a failure, not a skip.`
    ).toBeTypeOf('string');
    expect(
      rubySentinel,
      `the gsub(EMAIL_PATTERN, '...') substitution site was not found in ${RUBY_TWIN_PATH}.`
    ).toBeTypeOf('string');
  });

  it('pattern source is byte-identical across the two halves', () => {
    expect(
      rubyPatternSource,
      `MIRROR BROKEN: scrubbers.ts EMAIL_PATTERN and setup_diagnostics.rb EMAIL_PATTERN must be ` +
        `byte-identical (flags are the only permitted difference). A Sentry payload can be ` +
        `assembled by either half, so a widening applied to only one half still leaks.`
    ).toBe(EMAIL_PATTERN.source);
  });

  it('sentinel is byte-identical across the two halves', () => {
    expect(
      TS_SENTINEL,
      `MIRROR BROKEN: scrubbers.ts substitutes ${JSON.stringify(TS_SENTINEL)} but ` +
        `setup_diagnostics.rb substitutes ${JSON.stringify(rubySentinel)}. Downstream consumers ` +
        `(Sentry search, support macros) treat the sentinel as a single token.`
    ).toBe(rubySentinel);
  });

  it.each(corpus.entries.filter((e) => e.kind !== 'informational').map((e) => [e.id, e] as const))(
    '%s — TS output is byte-identical to the backend pass',
    (id, entry) => {
      expect(
        scrubSensitiveStrings(entry.input),
        `DIVERGENCE/[TS scrubbers.ts vs setup_diagnostics.rb] entry=${id} ` +
          `input=${JSON.stringify(entry.input)} — the two halves are a documented mirror and must ` +
          `produce identical output. One of them has been changed without the other.`
      ).toBe(backendEmailPass(entry.input));
    }
  );
});
