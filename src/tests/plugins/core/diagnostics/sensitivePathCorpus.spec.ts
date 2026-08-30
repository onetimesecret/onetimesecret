// src/tests/plugins/core/diagnostics/sensitivePathCorpus.spec.ts
//
// SENSITIVE-PATH INVARIANT — the shared-corpus suite (TypeScript half).
//
// THE INVARIANT
//   A credential that can appear in a URL must be removed by BOTH scrubbers.
//   A Sentry payload can be assembled by either the browser or the server, so
//   a shape covered on only one side still leaks — the covered half just hides
//   which one is broken.
//
// THE LEAK THIS SUITE EXISTS TO CATCH
//   Signup (#4305) threads the post-auth return destination through the
//   browser URL as `?redirect=<path>`. An invited user's destination is
//   `/invite/<token>`, and that token is a bearer credential — a valid
//   invite_token is accepted as proof of email ownership. Two independent
//   holes let it through:
//
//     - The backend had no `/invite/` arm at all, in either path pattern.
//     - SENSITIVE_PATH_PATTERN's value class was `[a-zA-Z0-9]+`, which stops
//       at the first `-` or `_` that `SecureRandom.urlsafe_base64(32)` emits.
//       `/invite/ab-cdef` scrubbed to `/invite/[REDACTED]-cdef` — a PARTIAL
//       credential, which reads as redacted and is not.
//
//   The `invite-token-dash-underscore-head` row pins the second one: its
//   `secret` is deliberately the TAIL of the token, so a narrowed value class
//   fails on exactly the bytes it would have leaked.
//
// WHAT THIS FILE OWNS
//   The TS half — `scrubUrlWithPatterns` in
//   src/plugins/core/diagnostics/scrubbers.ts — asserted against
//   tests/fixtures/sensitive_path_corpus.json, the SAME language-neutral
//   corpus the Ruby half reads (the 'shared sensitive-path corpus' block in
//   spec/unit/onetime/initializers/setup_diagnostics_spec.rb).
//
//   Deliberately NOT the same file as scrubUrl.spec.ts: that suite is the
//   scrubbers.ts-local contract (pass ordering, entry points, edge cases).
//   This one is the cross-language specification.
//
// WHY NO BYTE-EQUALITY ASSERTION
//   Unlike emailRedactionCorpus.spec.ts — where both halves compile the same
//   single regex and can be compared literally — the two path scrubbers reach
//   the same contract through deliberately different pattern sets. The backend
//   discriminates identifier paths by length (MIN_IDENTIFIER_LENGTH), the
//   frontend leans on generated route metadata. Asserting one identical output
//   string would pin an implementation detail instead of the security
//   property, and would go red on a legitimate refactor of either half. The
//   corpus therefore carries no expected output: each half independently
//   proves `secret` is gone and every `must_survive` fragment remains.
//
// HOW FAILURES READ
//   Cases are generated per corpus entry, so the test NAME carries the entry
//   id. Every assertion passes an explicit message naming the leaked value and
//   the input it came from.

import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

import { scrubUrlWithPatterns } from '@/plugins/core/diagnostics/scrubbers';

interface CorpusEntry {
  id: string;
  input: string;
  kind: 'redacted' | 'divergent' | 'preserved';
  secret?: string;
  must_survive?: string[];
  probes: string;
  scope?: 'both' | 'ruby';
}

interface Corpus {
  _readme: Record<string, unknown>;
  entries: CorpusEntry[];
}

const CORPUS_PATH = resolve(__dirname, '../../../../../tests/fixtures/sensitive_path_corpus.json');

const corpus = JSON.parse(readFileSync(CORPUS_PATH, 'utf-8')) as Corpus;

describe('shared sensitive-path corpus (TypeScript half)', () => {
  it('loads a non-empty corpus with unique ids', () => {
    const ids = corpus.entries.map((entry) => entry.id);

    expect(ids.length).toBeGreaterThan(0);
    expect(new Set(ids).size).toBe(ids.length);
  });

  // `scope: 'ruby'` marks a shape only the server ever sees. Each such row
  // records WHY in its `probes` text — the exemption is from the
  // cross-language invariant, so it is not granted silently.
  const shared = corpus.entries.filter(
    (entry) => entry.kind === 'redacted' && entry.scope !== 'ruby'
  );

  it('has shared rows to assert', () => {
    expect(shared.length).toBeGreaterThan(0);
  });

  // `preserved` rows carry no credential. They guard the other direction:
  // over-redaction is not free — a scrubber that eats a route TEMPLATE
  // collapses every parameterized transaction into one group and destroys the
  // signal the transaction name exists to carry.
  const preserved = corpus.entries.filter(
    (entry) => entry.kind === 'preserved' && entry.scope !== 'ruby'
  );

  it.each(preserved.map((entry) => [entry.id, entry] as const))(
    'leaves %s unchanged',
    (_id, entry) => {
      expect(
        scrubUrlWithPatterns(entry.input),
        `${entry.id}: over-redacted a template that carries no data`
      ).toBe(entry.input);
    }
  );

  describe.each(shared.map((entry) => [entry.id, entry] as const))('%s', (_id, entry) => {
    const result = scrubUrlWithPatterns(entry.input);

    it('is a well-formed corpus row', () => {
      expect(
        entry.input.includes(entry.secret as string),
        `corpus row ${entry.id} is malformed: \`secret\` is not in \`input\``
      ).toBe(true);
    });

    it('removes the credential', () => {
      expect(
        result.includes(entry.secret as string),
        `${entry.id}: scrubUrlWithPatterns leaked ${JSON.stringify(entry.secret)} ` +
          `from ${JSON.stringify(entry.input)} -> ${JSON.stringify(result)}`
      ).toBe(false);
    });

    it.each(entry.must_survive ?? [])('keeps %j readable', (fragment) => {
      expect(
        result.includes(fragment),
        `${entry.id}: over-redacted — ${JSON.stringify(fragment)} vanished from ${JSON.stringify(result)}`
      ).toBe(true);
    });
  });
});
