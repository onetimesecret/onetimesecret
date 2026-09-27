// src/tests/utils/snapshotOrdering.spec.ts
//
// ADR-046 "Client acceptance" and "Downgrade guard" as a table (#4464). One
// row per item in the ADR's acceptance, session-end and rollout test lists.

import { bootstrapSchema } from '@/schemas/contracts/bootstrap';
import {
  anonymousBootstrap,
  authenticatedBootstrap,
  snapshotOrdering,
} from '@/tests/fixtures/bootstrap.fixture';
import { toWire } from '@/tests/fixtures/bootstrap-wire';
import {
  classifySnapshot,
  describeGeneratedAt,
  isClockRegression,
  pairOf,
  parseCompleteSnapshot,
  type ClassifyInput,
  type SnapshotDecision,
} from '@/utils/snapshotOrdering';
import { describe, expect, it } from 'vitest';

const EPOCH_A = snapshotOrdering.snapshot_epoch;
const EPOCH_B = 'fedcba9876543210fedcba9876543210';
const held = { epoch: EPOCH_A, version: '100' };

/** An ordered, authenticated tab receiving an ordinary refresh. */
const base: ClassifyInput = {
  generationIsCurrent: true,
  kind: 'ordinary',
  watermark: held,
  retiredEpochs: [],
  priorSession: true,
  reportsSession: true,
  pair: { epoch: EPOCH_A, version: '101' },
};

const rows: Array<[string, Partial<ClassifyInput>, SnapshotDecision]> = [
  // Request generation decides staleness, whatever the epoch or version.
  [
    'a stale generation is dropped even with a strictly newer version',
    { generationIsCurrent: false, pair: { epoch: EPOCH_A, version: '999' } },
    { outcome: 'stale' },
  ],
  [
    'a stale generation is dropped even when it reports the end of the session',
    { generationIsCurrent: false, reportsSession: false, pair: null },
    { outcome: 'stale' },
  ],

  // Rule 3.
  ['a strictly newer version is applied', {}, { outcome: 'apply', stream: 'advance', retire: null }],
  [
    'versions are compared as integers, not as strings or floats',
    { watermark: { epoch: EPOCH_A, version: '9' }, pair: { epoch: EPOCH_A, version: '10' } },
    { outcome: 'apply', stream: 'advance', retire: null },
  ],
  [
    'a version beyond 2^64 still orders exactly',
    {
      watermark: { epoch: EPOCH_A, version: '18446744073709551616' },
      pair: { epoch: EPOCH_A, version: '18446744073709551617' },
    },
    { outcome: 'apply', stream: 'advance', retire: null },
  ],

  // Rule 4: each anomaly cause.
  [
    'an equal version is an anomaly (replayed response)',
    { pair: { epoch: EPOCH_A, version: '100' } },
    { outcome: 'anomaly', cause: 'not-newer' },
  ],
  [
    'a lower version is an anomaly (clock regression across a key loss)',
    { pair: { epoch: EPOCH_A, version: '99' } },
    { outcome: 'anomaly', cause: 'not-newer' },
  ],
  [
    'a lower version beyond 2^53 is still seen as lower',
    {
      watermark: { epoch: EPOCH_A, version: '9007199254740993' },
      pair: { epoch: EPOCH_A, version: '9007199254740992' },
    },
    { outcome: 'anomaly', cause: 'not-newer' },
  ],
  [
    'a retired epoch is an anomaly',
    { watermark: { epoch: EPOCH_B, version: '5' }, retiredEpochs: [EPOCH_A] },
    { outcome: 'anomaly', cause: 'retired-epoch' },
  ],
  [
    'a retired epoch is an anomaly for an unordered tab too (after a local sign-out)',
    { watermark: null, priorSession: false, retiredEpochs: [EPOCH_A] },
    { outcome: 'anomaly', cause: 'retired-epoch' },
  ],
  [
    'a retired epoch is an anomaly even on an authentication mutation',
    { kind: 'auth-mutation', watermark: { epoch: EPOCH_B, version: '5' }, retiredEpochs: [EPOCH_A] },
    { outcome: 'anomaly', cause: 'retired-epoch' },
  ],
  [
    'downgrade guard: a session without a pair cannot bypass the watermark (pre-contract worker)',
    { pair: null },
    { outcome: 'anomaly', cause: 'missing-pair' },
  ],

  // Rule 1: the end of a session is never rejected.
  [
    'session ended on an ordinary refresh forces a page load (expiry, revocation, logout elsewhere)',
    { reportsSession: false, pair: null },
    { outcome: 'force-page-load', cause: 'ended', retire: EPOCH_A },
  ],
  [
    'session ended wins over ordering metadata, even a lower version',
    { reportsSession: false, pair: { epoch: EPOCH_A, version: '1' } },
    { outcome: 'force-page-load', cause: 'ended', retire: EPOCH_A },
  ],
  [
    'session ended wins over a retired epoch',
    { reportsSession: false, retiredEpochs: [EPOCH_A] },
    { outcome: 'force-page-load', cause: 'ended', retire: EPOCH_A },
  ],
  [
    "session ended on this tab's own mutation is applied and retires the epoch",
    { kind: 'auth-mutation', reportsSession: false, pair: null },
    { outcome: 'apply', stream: 'ended', retire: EPOCH_A },
  ],
  [
    'session ended in an unordered tab that held a session still forces a page load',
    { watermark: null, reportsSession: false, pair: null },
    { outcome: 'force-page-load', cause: 'ended', retire: null },
  ],
  [
    'no session, and none before: applied in place (an anonymous tab stays anonymous)',
    { watermark: null, priorSession: false, reportsSession: false, pair: null },
    { outcome: 'apply', stream: 'ended', retire: null },
  ],

  // Rule 2: session replaced.
  [
    'a new epoch on an ordinary refresh forces a page load without applying',
    { pair: { epoch: EPOCH_B, version: '1' } },
    { outcome: 'force-page-load', cause: 'replaced', retire: EPOCH_A },
  ],
  [
    'a new epoch on an authentication mutation starts a new stream, whatever its version',
    { kind: 'auth-mutation', pair: { epoch: EPOCH_B, version: '1' } },
    { outcome: 'apply', stream: 'new-epoch', retire: EPOCH_A },
  ],

  // Unordered tabs.
  [
    'an unordered tab applies an unordered snapshot as the client always did',
    { watermark: null, pair: null },
    { outcome: 'apply', stream: 'unordered', retire: null },
  ],
  [
    'the first valid ordered snapshot establishes the watermark',
    { watermark: null },
    { outcome: 'apply', stream: 'start', retire: null },
  ],
  [
    'an anonymous tab that signs in starts a stream',
    { watermark: null, priorSession: false, kind: 'auth-mutation' },
    { outcome: 'apply', stream: 'start', retire: null },
  ],
];

describe('classifySnapshot (ADR-046 client acceptance)', () => {
  it.each(rows)('%s', (_name, overrides, expected) => {
    expect(classifySnapshot({ ...base, ...overrides })).toEqual(expected);
  });

  it('has no input for snapshot_generated_at: the timestamp cannot decide', () => {
    const keys = Object.keys(base);
    expect(keys.some((key) => /generated|time|date/i.test(key))).toBe(false);
  });
});

describe('parseCompleteSnapshot', () => {
  const wire = toWire(authenticatedBootstrap) as Record<string, unknown>;

  it('accepts a valid ordered payload', () => {
    const parsed = parseCompleteSnapshot(wire);
    expect(parsed.ok && !parsed.pairMalformed).toBe(true);
    expect(parsed.ok && pairOf(parsed.payload)).toEqual({
      epoch: snapshotOrdering.snapshot_epoch,
      version: snapshotOrdering.snapshot_version,
    });
  });

  it.each([
    ['a version sent as a JSON number', { snapshot_version: 42 }],
    ['a version in exponent form', { snapshot_version: '1.7e15' }],
    ['an epoch of the wrong shape', { snapshot_epoch: 'NOT-HEX' }],
    ['half a pair', { snapshot_version: undefined }],
  ])('%s is a malformed pair, not an unreadable payload', (_name, overrides) => {
    const parsed = parseCompleteSnapshot({ ...wire, ...overrides });

    expect(parsed.ok && parsed.pairMalformed).toBe(true);
    expect(parsed.ok && pairOf(parsed.payload)).toBeNull();
    expect(parsed.ok && parsed.payload.authenticated).toBe(true);
  });

  it('a malformed pair never hides the end of a session', () => {
    const parsed = parseCompleteSnapshot({ ...toWire(anonymousBootstrap), snapshot_epoch: 'x' });
    expect(parsed.ok && parsed.payload.authenticated).toBe(false);
  });

  it('any other contract failure is a failure, reported by path only', () => {
    const parsed = parseCompleteSnapshot({ ...wire, authenticated: 'yes', snapshot_epoch: 'x' });
    expect(parsed).toEqual({ ok: false, invalidPaths: expect.arrayContaining(['authenticated']) });
  });

  it('a missing or malformed snapshot_generated_at does not fail the parse', () => {
    for (const value of [undefined, '2026-09-17T17:28:59.123Z', 'yesterday']) {
      expect(parseCompleteSnapshot({ ...wire, snapshot_generated_at: value }).ok).toBe(true);
    }
    expect(bootstrapSchema.safeParse({ ...wire, snapshot_generated_at: 'yesterday' }).success).toBe(true);
  });
});

describe('snapshot_generated_at diagnostics', () => {
  it('reports the age as unknown when missing or malformed', () => {
    expect(describeGeneratedAt(undefined)).toEqual({ state: 'missing' });
    expect(describeGeneratedAt('')).toEqual({ state: 'missing' });
    expect(describeGeneratedAt('2026-09-17T17:28:59.123Z')).toEqual({ state: 'malformed' });
    expect(describeGeneratedAt(1758130139)).toEqual({ state: 'malformed' });
    expect(describeGeneratedAt('2026-09-17T17:28:59.123456Z').state).toBe('ok');
  });

  it('detects a clock regression to the microsecond', () => {
    const earlier = describeGeneratedAt('2026-09-17T17:28:59.123456Z');
    const later = describeGeneratedAt('2026-09-17T17:28:59.123457Z');
    expect(isClockRegression(later, earlier)).toBe(true);
    expect(isClockRegression(earlier, later)).toBe(false);
    expect(isClockRegression(earlier, earlier)).toBe(false);
    expect(isClockRegression({ state: 'missing' }, earlier)).toBe(false);
  });
});
