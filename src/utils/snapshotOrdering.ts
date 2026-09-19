// src/utils/snapshotOrdering.ts
//
// Client acceptance of complete bootstrap snapshots (ADR-046, #4464).
//
// Pure: no store, no clock, no I/O; the shared Zod contract is its only
// import. The refresh coordinator in authStore asks this module what to do
// with a response and then does exactly that; the rules live here so every
// ADR-046 acceptance item can be tested as a table row.
//
// `snapshot_generated_at` is deliberately NOT an input to classifySnapshot. It
// orders nothing (ADR-046, "Gating acceptance on snapshot_generated_at" —
// rejected). It is read only by describeGeneratedAt, for diagnostics.

import {
  bootstrapSchema,
  SNAPSHOT_GENERATED_AT_PATTERN,
  withoutWireNulls,
  type BootstrapPayload,
} from '@/schemas/contracts/bootstrap';

/** A validated epoch/version pair, as it appears on the wire. */
export interface OrderingPair {
  epoch: string;
  /** Canonical decimal string. Compared as BigInt, never as a number. */
  version: string;
}

export type RefreshKindForOrdering = 'ordinary' | 'auth-mutation';

export interface ClassifyInput {
  /** False when a later request generation has started. Decides staleness alone. */
  generationIsCurrent: boolean;
  /** The kind of request that owns the current generation. */
  kind: RefreshKindForOrdering;
  /** The accepted pair, or null for an unordered tab. */
  watermark: OrderingPair | null;
  /** Every epoch this page has replaced. Never shrinks for the page's lifetime. */
  retiredEpochs: ReadonlyArray<string>;
  /** Whether the last ACCEPTED snapshot reported a session. */
  priorSession: boolean;
  /** Whether the response reports an authenticated or MFA-pending session. */
  reportsSession: boolean;
  /** The response's valid pair, or null when absent or malformed. */
  pair: OrderingPair | null;
}

export type AnomalyCause = 'not-newer' | 'retired-epoch' | 'missing-pair';

/**
 * What the coordinator must do with one response.
 *
 * - `stale`            another generation is current: drop as a unit.
 * - `apply`            commit atomically. `retire` names an epoch to remember
 *                      as replaced. The snapshot's own pair becomes the
 *                      watermark; without one the tab is unordered.
 * - `force-page-load`  do NOT apply; enter the stale-session state and reload.
 * - `anomaly`          do NOT apply; one immediate retry, then a page load.
 */
export type SnapshotDecision =
  | { outcome: 'stale' }
  | {
      outcome: 'apply';
      stream: 'unordered' | 'start' | 'advance' | 'new-epoch' | 'ended';
      retire: string | null;
    }
  | { outcome: 'force-page-load'; cause: 'ended' | 'replaced'; retire: string | null }
  | { outcome: 'anomaly'; cause: AnomalyCause };

function isStrictlyGreater(candidate: string, accepted: string): boolean {
  return BigInt(candidate) > BigInt(accepted);
}

/**
 * Classifies one response, in ADR-046's order: stale generation, session
 * ended, session replaced, strictly greater version, anomaly.
 *
 * Two principles decide every branch. Ordering exists to stop stale state
 * replacing newer state; it never stops the end of a session from reaching
 * the tab. And the client never stays on state it refused to replace: every
 * response is applied, ends in a page load, or is retried once and then ends
 * in a page load.
 */
export function classifySnapshot(input: ClassifyInput): SnapshotDecision {
  if (!input.generationIsCurrent) return { outcome: 'stale' };
  return input.reportsSession ? classifySession(input) : classifyEnded(input);
}

/**
 * Rule 1 — session ended. Never rejected, whatever its ordering metadata,
 * including none.
 */
function classifyEnded({ watermark, kind, priorSession }: ClassifyInput): SnapshotDecision {
  const retire = watermark?.epoch ?? null;
  // This tab's own logout, or a tab that held no session to begin with.
  if (kind === 'auth-mutation' || !priorSession) {
    return { outcome: 'apply', stream: 'ended', retire };
  }
  // Expiry, revocation, or logout in another tab. Applying it in place would
  // depend on a teardown of every session-scoped store; a page load needs no
  // inventory.
  return { outcome: 'force-page-load', cause: 'ended', retire };
}

/** Rules 2 to 4, for a snapshot that reports a session. */
function classifySession(input: ClassifyInput): SnapshotDecision {
  const { watermark, pair, kind, retiredEpochs } = input;

  // A retired epoch is an anomaly with or without a watermark: this page
  // replaced that stream and must never resume it.
  if (pair && retiredEpochs.includes(pair.epoch)) {
    return { outcome: 'anomaly', cause: 'retired-epoch' };
  }

  // Unordered tab: applies complete snapshots until the first valid ordered
  // one on the current generation establishes a watermark. Also the behaviour
  // against a server that predates the contract.
  if (!watermark) {
    return { outcome: 'apply', stream: pair ? 'start' : 'unordered', retire: null };
  }

  // Downgrade guard: once a watermark is held, a session-bearing snapshot
  // without a valid pair cannot make the client forget it.
  if (!pair) return { outcome: 'anomaly', cause: 'missing-pair' };

  // Rule 2 — session replaced: the epoch is neither accepted nor retired.
  if (pair.epoch !== watermark.epoch) {
    return kind === 'auth-mutation'
      ? { outcome: 'apply', stream: 'new-epoch', retire: watermark.epoch }
      : { outcome: 'force-page-load', cause: 'replaced', retire: watermark.epoch };
  }

  // Rule 3 — accepted epoch, strictly greater version.
  if (isStrictlyGreater(pair.version, watermark.version)) {
    return { outcome: 'apply', stream: 'advance', retire: null };
  }

  // Rule 4 — equal or lower: a replayed response, a Redis clock regression
  // across a key loss, or a worker that predates the contract.
  return { outcome: 'anomaly', cause: 'not-newer' };
}

export type GeneratedAtReport =
  | { state: 'ok'; value: string }
  | { state: 'missing' }
  | { state: 'malformed' };

/**
 * Diagnostic reading of `snapshot_generated_at`. A missing or malformed value
 * means the snapshot's age is unknown; it changes nothing else.
 */
export function describeGeneratedAt(value: unknown): GeneratedAtReport {
  if (value === undefined || value === null || value === '') return { state: 'missing' };
  if (typeof value !== 'string' || !SNAPSHOT_GENERATED_AT_PATTERN.test(value)) {
    return { state: 'malformed' };
  }
  return { state: 'ok', value };
}

/**
 * True when the version advanced while the generation time moved backwards:
 * a server clock regression. Diagnostic only. The fixed-width UTC format
 * makes string comparison exact to the microsecond, which `Date` is not.
 */
export function isClockRegression(prior: GeneratedAtReport, next: GeneratedAtReport): boolean {
  return prior.state === 'ok' && next.state === 'ok' && next.value < prior.value;
}

const ORDERING_PAIR_KEYS: ReadonlyArray<string> = ['snapshot_epoch', 'snapshot_version'];

export type ParsedSnapshot =
  | { ok: true; payload: BootstrapPayload; pairMalformed: boolean }
  | { ok: false; invalidPaths: string[] };

/**
 * Validates a complete snapshot BEFORE anything is mutated.
 *
 * A payload whose only contract failures are in the ordering pair is parsed
 * again without the pair and reported as `pairMalformed`. ADR-046 classifies a
 * malformed pair (rule 4, or rule 1 when no session is reported); it does not
 * make the rest of the payload unreadable, and "session ended" must never be
 * refused over its ordering metadata. Any other failure is a contract
 * failure: the payload reaches no store.
 *
 * Reports issue PATHS only, never values: the payload carries personal data.
 */
export function parseCompleteSnapshot(wire: unknown): ParsedSnapshot {
  // A wire null on a key whose schema has no null means "not emitted".
  const data = withoutWireNulls(wire);
  const parsed = bootstrapSchema.safeParse(data);
  if (parsed.success) return { ok: true, payload: parsed.data, pairMalformed: false };

  const invalidPaths = parsed.error.issues.map((issue) => issue.path.join('.'));
  const onlyOrdering = invalidPaths.every((path) => ORDERING_PAIR_KEYS.includes(path));
  if (onlyOrdering && typeof data === 'object' && data !== null) {
    const stripped: Record<string, unknown> = { ...(data as Record<string, unknown>) };
    for (const key of ORDERING_PAIR_KEYS) delete stripped[key];
    const retry = bootstrapSchema.safeParse(stripped);
    if (retry.success) return { ok: true, payload: retry.data, pairMalformed: true };
  }
  return { ok: false, invalidPaths };
}

/** The payload's valid pair, or null. */
export function pairOf(payload: BootstrapPayload): OrderingPair | null {
  const { snapshot_epoch: epoch, snapshot_version: version } = payload;
  return epoch !== undefined && version !== undefined ? { epoch, version } : null;
}
