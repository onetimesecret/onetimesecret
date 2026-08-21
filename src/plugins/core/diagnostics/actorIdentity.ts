// src/plugins/core/diagnostics/actorIdentity.ts
//
// ═══════════════════════════════════════════════════════════════════════════════
// THE ACTOR-IDENTITY PRIVACY BOUNDARY
// ═══════════════════════════════════════════════════════════════════════════════
//
// This module is the ONLY place in the frontend that is allowed to populate
// Sentry's `user` context. Everything about it is written to be auditable in a
// single read: what goes in, what is refused, and what is emitted.
//
// ── What Sentry receives ──────────────────────────────────────────────────────
//
//   user = { id: <opaque actor_ref>, ip_address: null }
//   tags.actor_scope = "federated" | "deployment"
//
// That is the complete set. No `email`, no `username`, no `name`, no
// `ip_address` other than the explicit null, and no additional user keys. The
// shape is built by literal construction (never by spreading the server block),
// so a new server-side field cannot ride along even if the schema were loosened.
//
// ── What Sentry must never receive ────────────────────────────────────────────
//
//   email address · display name · customer objid · customer extid ·
//   IP address · secret identifier · secret passphrase · session id · shrimp
//
// `actor_ref` is contractually an OPAQUE DETERMINISTIC REFERENCE derived
// server-side. The client cannot prove a value is a keyed digest, so it does
// the two things it can, and it does BOTH:
//
//   1. refuses any block whose KEY SET it does not recognise (`telemetrySchema`
//      is a strictObject), and
//   2. refuses any `actor_ref` whose CONTENT is not exactly the shape the
//      server-side derivation produces — 16 lowercase hex chars, matched
//      against `ACTOR_REF_PATTERN`.
//
// Check 2 is not redundant. Without it, `{ actor_ref: "alice@example.com",
// actor_scope: "deployment" }` is a fully VALID block (two keys, valid enum,
// non-empty string) and the outbound gate below — which strips email, username
// and name but KEEPS `id` — would ship that address as `user.id` on every error
// and every transaction. A strict key set stops an unexpected FIELD; only the
// content check stops an unexpected VALUE in a permitted field.
//
// `ACTOR_REF_PATTERN` lives in the contract module and is the single source of
// truth on this side. It mirrors `Onetime::Utils::TelemetryRef::REF_LENGTH`
// (16 lowercase hex, lib/onetime/utils/telemetry_ref.rb) and must be changed in
// the same commit as any change to the Ruby derivation — it fails CLOSED, so
// drift costs actor correlation rather than leaking.
// See `telemetrySchema` in src/schemas/contracts/bootstrap.ts.
//
// ── Anonymous sessions ────────────────────────────────────────────────────────
//
// The server OMITS the `telemetry` block entirely for anonymous sessions. There
// is no anonymous sentinel, no empty-string actor, and — critically — no
// generated fallback id. `resolveBootstrapActor()` returns null and
// `applyActorIdentity()` calls `setUser(null)`, leaving the session
// unidentified. Minting a random/device id here would silently recreate the
// cross-session tracking identifier this whole design exists to avoid.
//
// ── ip_address: null, explicitly ──────────────────────────────────────────────
//
// Sentry infers the reporter's IP SERVER-SIDE when the event's user object
// carries `ip_address: "{{auto}}"` or (with `sendDefaultPii: true`) when the
// SDK fills it in. We run with `sendDefaultPii: false`, but that is a default
// that a future config spread could flip. Sending an explicit `null` is the
// belt to that suspenders: an explicit null is not `{{auto}}`, so relay has
// nothing to substitute regardless of the PII flag.
//
// ── Two scopes, always ────────────────────────────────────────────────────────
//
// Identity must be applied to BOTH the isolated `Scope` (manual captures via
// diagnostics.service) and the CURRENT scope (integration-captured events:
// unhandled rejections, browserApiErrors async callbacks, browserTracing
// transactions). This mirrors `applyDeploymentTags` in enableDiagnostics.ts and
// exists for the same reason documented there — a value set only on the
// detached isolated scope never reaches integration-captured events.
//
// The same duality applies to CLEARING. A `setUser(null)` on one scope only
// would leave the previous actor attached to half of all subsequent events,
// which is worse than never having identified at all: it mislabels one user's
// errors as another's after an account switch.

import {
  ACTOR_REF_PATTERN,
  isActorRef,
  telemetrySchema,
  type TelemetryBlock,
} from '@/schemas/contracts/bootstrap';
import { getBootstrapValue } from '@/services/bootstrap.service';
import type { Scope } from '@sentry/browser';

/**
 * The Sentry tag key carrying the actor scope.
 *
 * Exported so tests and the diagnostics service refer to one literal rather
 * than three copies of the string.
 */
export const ACTOR_SCOPE_TAG = 'actor_scope';

/**
 * The subset of `Scope` this module touches.
 *
 * Deliberately narrow: it documents at the type level that actor identity only
 * ever calls `setUser` and `setTag`, and it lets tests pass plain objects
 * without constructing a real Sentry scope.
 */
export type IdentityScope = Pick<Scope, 'setUser' | 'setTag'>;

/**
 * The exact user object shipped to Sentry. Constructed literally, never
 * spread from server data.
 */
export interface ActorUser {
  /** The opaque server-derived reference. Never PII. */
  id: string;
  /**
   * Explicit null — see the `ip_address` note in the module header. `null`
   * suppresses Sentry's server-side IP inference in a way that `undefined`
   * (an absent key) does not reliably do.
   */
  ip_address: null;
}

/**
 * Validates an untrusted `telemetry` block against the strict contract.
 *
 * Fail-CLOSED by construction: any deviation — a missing field, a non-string
 * `actor_ref`, an `actor_scope` outside the closed enum, or ANY extra key
 * (`email`, `name`, `objid`, …) — yields `null`, and the session runs
 * unidentified. That is the intended trade: losing actor correlation in Sentry
 * is an observability regression; forwarding an unexpected server field to a
 * third-party processor is a privacy incident.
 *
 * @param raw - Untrusted value, typically `bootstrap.telemetry`.
 * @returns The validated block, or null when absent/anonymous/malformed.
 */
export function parseTelemetryBlock(raw: unknown): TelemetryBlock | null {
  if (raw === null || raw === undefined) {
    // Anonymous session (or an older server that predates the block). Not an
    // error condition — absence IS the anonymous signal.
    return null;
  }
  const result = telemetrySchema.safeParse(raw);
  if (!result.success) {
    // Intentionally does not log the offending value: the whole reason this
    // path exists is that the value may contain something we must not
    // propagate, and console output is itself captured as a breadcrumb.
    console.debug('[actorIdentity] telemetry block rejected by strict contract');
    return null;
  }
  return result.data;
}

/**
 * Reads and validates the actor block from the pre-Pinia bootstrap snapshot.
 *
 * Uses `getBootstrapValue` rather than `useBootstrapStore()` because Sentry is
 * created BEFORE Pinia is installed (`appInitializer.ts` calls
 * `createDiagnostics()` well ahead of `app.use(pinia)`), so reaching for the
 * store here would throw "no active Pinia". Same reason and same pattern as the
 * `regions` read in `applyDeploymentTags`.
 *
 * @returns The validated actor block, or null for anonymous/absent/invalid.
 */
export function resolveBootstrapActor(): TelemetryBlock | null {
  return parseTelemetryBlock(getBootstrapValue('telemetry'));
}

/**
 * Applies — or clears — actor identity on every supplied scope.
 *
 * Idempotent and total: calling it with `null` fully clears identity, so the
 * same function serves initial configuration, account change, and logout. There
 * is deliberately no separate "clear" code path that could drift from the "set"
 * path and leave a tag behind.
 *
 * On clear, `actor_scope` is set to `undefined`, which is how Sentry's Scope
 * removes a tag (the key is dropped during event serialization). Leaving a
 * stale `actor_scope` after logout would let an anonymous session be filtered
 * as if it were still the previous, identified actor.
 *
 * @param scopes - Every scope that must agree. In practice
 *   `[isolatedScope, getCurrentScope()]` — see the module header.
 * @param actor - Validated actor block, or null to run unidentified.
 */
export function applyActorIdentity(
  scopes: readonly IdentityScope[],
  actor: TelemetryBlock | null
): void {
  // Literal construction. NEVER `{ ...actor }` — a spread would forward any
  // field the schema might one day stop rejecting.
  //
  // The ref is re-checked here rather than trusted from the type: callers reach
  // this function with a `TelemetryBlock`, but a TypeScript type is not a
  // runtime guarantee (a cast, a hand-built object, or a future caller that
  // skips `parseTelemetryBlock` all produce one). An unrecognised ref CLEARS
  // identity — the same fail-closed answer as a malformed block, never a
  // partially applied one.
  const user: ActorUser | null =
    actor && isActorRef(actor.actor_ref) ? { id: actor.actor_ref, ip_address: null } : null;

  for (const scope of scopes) {
    scope.setUser(user);
    // Keyed off `user`, not `actor`: when the ref was refused above there is no
    // identity, so there must be no scope tag either — a lone `actor_scope`
    // would label an unidentified session as if it were still identified.
    // `undefined` clears the tag; Sentry drops undefined tag values when
    // serializing the event.
    scope.setTag(ACTOR_SCOPE_TAG, user && actor ? actor.actor_scope : undefined);
  }
}

/**
 * Final-gate sanitizer for the `user` context on an outbound event.
 *
 * `applyActorIdentity` is the only sanctioned writer, but it is not the only
 * possible one: `Sentry.setUser()` is a global API, `@sentry/vue` helpers and
 * any future integration can write user context, and events can arrive with a
 * `user` object this module never produced. Rather than trusting that no such
 * writer will ever appear, `beforeSend`/`beforeSendTransaction` run every event
 * through this whitelist on the way out.
 *
 * Keeps: `id`, and ONLY when it is a recognised opaque actor ref
 * (`ACTOR_REF_PATTERN` — 16 lowercase hex), plus a forced `ip_address: null`.
 * Drops: `email`, `username`, `name`, `ip_address` values, geo, segment, and
 * every other key — including ones that do not exist yet.
 *
 * ## Why `id` is content-checked here too
 *
 * A "non-empty string" test made this gate a LAUNDERER rather than a filter:
 * `Sentry.setUser({ id: cust.email })` — a one-line change anyone can make,
 * anywhere, without touching this module — produced a valid `id` that was then
 * copied verbatim onto every outbound event, while the same function
 * conscientiously deleted the `email` key beside it. Re-asserting the SHAPE of
 * the value is what makes the advertised guarantee ("no email / username /
 * inferred IP leaves the browser regardless of who populated the scope") true
 * for the one field this gate preserves.
 *
 * Fails CLOSED: an unrecognised ref means the whole `user` context is dropped.
 * There is deliberately no fallback id — see the anonymous-session note in the
 * module header for why minting one is worse than being unidentified.
 *
 * Mutates in place and returns nothing, matching the other `scrub*` helpers in
 * this directory.
 *
 * @param event - Any event carrying an optional `user` context.
 */
export function sanitizeEventUser(event: { user?: Record<string, unknown> | null }): void {
  const user = event.user;
  if (!user) {
    return;
  }
  const id = user.id;
  if (!isActorRef(id)) {
    // Not an opaque reference of the expected shape — an email, an objid, a
    // random device id, an empty husk. Drop the whole user context rather than
    // forwarding an unrecognised identifier or shipping a husk that Sentry
    // might backfill with an inferred IP.
    delete event.user;
    return;
  }
  event.user = { id, ip_address: null };
}

/**
 * Re-exported so consumers and tests reach the pattern through the privacy
 * boundary that enforces it, without importing the contract module directly.
 */
export { ACTOR_REF_PATTERN, isActorRef };
