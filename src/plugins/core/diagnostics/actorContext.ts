// src/plugins/core/diagnostics/actorContext.ts
//
// ═══════════════════════════════════════════════════════════════════════════════
// THE SENTRY USER-CONTEXT BOUNDARY
// ═══════════════════════════════════════════════════════════════════════════════
//
// This module is the ONLY place in the frontend that is allowed to populate
// Sentry's `user` context. Everything about it is written to be auditable in a
// single read: what goes in, what is refused, and what is emitted.
//
// ── What Sentry receives ──────────────────────────────────────────────────────
//
//   user = { id: <opaque server-derived ref>, ip_address: null }
//   tags.actor_scope = "federated" | "deployment"
//
// That is the complete set. No `email`, no `username`, no `name`, no
// `ip_address` other than the explicit null, and no additional user keys. The
// shape is built by literal construction (never by spreading the server
// block), so a new server-side field cannot ride along even if the schema were
// loosened.
//
// ── What Sentry must never receive ────────────────────────────────────────────
//
//   email address · display name · customer objid · customer extid ·
//   IP address · secret identifier · secret passphrase · session id · shrimp
//
// The ref is contractually an OPAQUE DETERMINISTIC REFERENCE derived
// server-side. The client cannot prove a value is a keyed digest, so it does
// the two things it can, and it does BOTH:
//
//   1. refuses any block whose KEY SET it does not recognise
//      (`diagnosticsRefSchema` is a strictObject), and
//   2. refuses any ref whose CONTENT is not exactly the shape the server-side
//      derivation produces — 16 lowercase hex chars, matched against
//      `DIAGNOSTICS_REF_PATTERN`.
//
// Check 2 is not redundant. `{ actor_ref: "alice@example.com", actor_scope:
// "deployment" }` is a fully VALID block by key set alone — two keys, valid
// enum, non-empty string. The outbound gate keeps exactly one field, `id`, and
// drops the rest, so with a key-set check only, that address would be shipped
// as `user.id` on every error and every transaction while `email` was
// conscientiously deleted beside it. A strict key set stops an unexpected
// FIELD; only the content check stops an unexpected VALUE in a permitted
// field, which is why BOTH the inbound parse and `sanitizeEventUser` apply it.
//
// `DIAGNOSTICS_REF_PATTERN` lives in the contract module and is the single
// source of truth on this side. It mirrors
// `Onetime::Utils::DiagnosticsRef::REF_LENGTH` (16 lowercase hex,
// lib/onetime/utils/diagnostics_ref.rb) and must be changed in the same commit
// as any change to the Ruby derivation — it fails CLOSED, so drift costs
// correlation rather than leaking. See `diagnosticsRefSchema` in
// src/schemas/contracts/bootstrap.ts.
//
// ── Anonymous sessions ────────────────────────────────────────────────────────
//
// The server OMITS the `diagnostics_ref` block entirely for anonymous
// sessions. There is no anonymous sentinel, no empty-string ref, and —
// critically — no generated fallback id. `resolveDiagnosticsRef()` returns
// null and `applyActorContext()` calls `setUser(null)`, leaving the session
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
// User context must be applied to BOTH the isolated `Scope` (manual captures
// via diagnostics.service) and the CURRENT scope (integration-captured events:
// unhandled rejections, browserApiErrors async callbacks, browserTracing
// transactions). This mirrors `applyDeploymentTags` in enableDiagnostics.ts
// and exists for the same reason documented there — a value set only on the
// detached isolated scope never reaches integration-captured events.
//
// The same duality applies to CLEARING. A `setUser(null)` on one scope only
// would leave the previous reference attached to half of all subsequent
// events, which is worse than never having identified at all: it mislabels
// one user's errors as another's after an account switch.

import {
  DIAGNOSTICS_REF_PATTERN,
  isDiagnosticsRef,
  diagnosticsRefSchema,
  type DiagnosticsRefBlock,
} from '@/schemas/contracts/bootstrap';
import { getBootstrapValue } from '@/services/bootstrap.service';
import type { Scope } from '@sentry/browser';

/**
 * The Sentry tag key carrying the ref scope (which secret keyed the ref).
 *
 * Exported so tests and the diagnostics service refer to one literal rather
 * than three copies of the string.
 */
export const ACTOR_SCOPE_TAG = 'actor_scope';

/**
 * The subset of `Scope` this module touches.
 *
 * Deliberately narrow: it documents at the type level that actor context only
 * ever calls `setUser` and `setTag`, and it lets tests pass plain objects
 * without constructing a real Sentry scope.
 */
export type ActorContextScope = Pick<Scope, 'setUser' | 'setTag'>;

/**
 * The exact user object shipped to Sentry. Constructed literally, never
 * spread from server data.
 */
export interface DiagnosticsActor {
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
 * Validates an untrusted `diagnostics_ref` block against the strict contract.
 *
 * Fail-CLOSED by construction: any deviation — a missing field, a non-string
 * ref, a scope outside the closed enum, or ANY extra key (`email`, `name`,
 * `objid`, …) — yields `null`, and the session runs unidentified. That is the
 * intended trade: losing correlation in Sentry is an observability
 * regression; forwarding an unexpected server field to a third-party
 * processor is a privacy incident.
 *
 * @param raw - Untrusted value, typically `bootstrap.diagnostics_ref`.
 * @returns The validated block, or null when absent/anonymous/malformed.
 */
export function parseDiagnosticsRefBlock(raw: unknown): DiagnosticsRefBlock | null {
  if (raw === null || raw === undefined) {
    // Anonymous session (or an older server that predates the block). Not an
    // error condition — absence IS the anonymous signal.
    return null;
  }
  const result = diagnosticsRefSchema.safeParse(raw);
  if (!result.success) {
    // Intentionally does not log the offending value: the whole reason this
    // path exists is that the value may contain something we must not
    // propagate, and console output is itself captured as a breadcrumb.
    console.debug('[actorContext] diagnostics_ref block rejected by strict contract');
    return null;
  }
  return result.data;
}

/**
 * Reads and validates the ref block from the pre-Pinia bootstrap snapshot.
 *
 * Uses `getBootstrapValue` rather than `useBootstrapStore()` because Sentry is
 * created BEFORE Pinia is installed (`appInitializer.ts` calls
 * `createDiagnostics()` well ahead of `app.use(pinia)`), so reaching for the
 * store here would throw "no active Pinia". Same reason and same pattern as
 * the `regions` read in `applyDeploymentTags`.
 *
 * @returns The validated ref block, or null for anonymous/absent/invalid.
 */
export function resolveDiagnosticsRef(): DiagnosticsRefBlock | null {
  return parseDiagnosticsRefBlock(getBootstrapValue('diagnostics_ref'));
}

/**
 * Applies — or clears — Sentry user context on every supplied scope.
 *
 * Idempotent and total: calling it with `null` fully clears the context, so
 * the same function serves initial configuration, account change, and logout.
 * There is deliberately no separate "clear" code path that could drift from
 * the "set" path and leave a tag behind.
 *
 * On clear, `actor_scope` is set to `undefined`, which is how Sentry's Scope
 * removes a tag (the key is dropped during event serialization). Leaving a
 * stale `actor_scope` after logout would let an anonymous session be filtered
 * as if it were still the previous, identified session.
 *
 * @param scopes - Every scope that must agree. In practice
 *   `[isolatedScope, getCurrentScope()]` — see the module header.
 * @param ref - Validated ref block, or null to run unidentified.
 */
export function applyActorContext(
  scopes: readonly ActorContextScope[],
  ref: DiagnosticsRefBlock | null
): void {
  // Literal construction. NEVER `{ ...ref }` — a spread would forward any
  // field the schema might one day stop rejecting.
  //
  // The ref value is re-checked here rather than trusted from the type:
  // callers reach this function with a `DiagnosticsRefBlock`, but a TypeScript
  // type is not a runtime guarantee (a cast, a hand-built object, or a future
  // caller that skips `parseDiagnosticsRefBlock` all produce one). An
  // unrecognised ref CLEARS the context — the same fail-closed answer as a
  // malformed block, never a partially applied one.
  const user: DiagnosticsActor | null =
    ref && isDiagnosticsRef(ref.actor_ref) ? { id: ref.actor_ref, ip_address: null } : null;

  for (const scope of scopes) {
    scope.setUser(user);
    // Keyed off `user`, not `ref`: when the ref value was refused above there
    // is no user context, so there must be no scope tag either — a lone
    // `actor_scope` would label an unidentified session as if it were still
    // identified. `undefined` clears the tag; Sentry drops undefined tag
    // values when serializing the event.
    scope.setTag(ACTOR_SCOPE_TAG, user && ref ? ref.actor_scope : undefined);
  }
}

/**
 * Final-gate sanitizer for the `user` context on an outbound event.
 *
 * `applyActorContext` is the only sanctioned writer, but it is not the only
 * possible one: `Sentry.setUser()` is a global API, `@sentry/vue` helpers and
 * any future integration can write user context, and events can arrive with a
 * `user` object this module never produced. Rather than trusting that no such
 * writer will ever appear, `beforeSend`/`beforeSendTransaction` run every
 * event through this whitelist on the way out.
 *
 * Keeps: `id`, and ONLY when it is a recognised opaque ref
 * (`DIAGNOSTICS_REF_PATTERN` — 16 lowercase hex), plus a forced
 * `ip_address: null`. Drops: `email`, `username`, `name`, `ip_address`
 * values, geo, segment, and every other key — including ones that do not
 * exist yet.
 *
 * ## Why `id` is content-checked here too
 *
 * A "non-empty string" test made this gate a LAUNDERER rather than a filter:
 * `Sentry.setUser({ id: cust.email })` — a one-line change anyone can make,
 * anywhere, without touching this module — produced a valid `id` that was
 * then copied verbatim onto every outbound event, while the same function
 * conscientiously deleted the `email` key beside it. Re-asserting the SHAPE
 * of the value is what makes the advertised guarantee ("no email / username /
 * inferred IP leaves the browser regardless of who populated the scope") true
 * for the one field this gate preserves.
 *
 * Fails CLOSED: an unrecognised ref means the whole `user` context is
 * dropped. There is deliberately no fallback id — see the anonymous-session
 * note in the module header for why minting one is worse than being
 * unidentified.
 *
 * Mutates in place and returns nothing, matching the other `scrub*` helpers
 * in this directory.
 *
 * @param event - Any event carrying an optional `user` context.
 */
export function sanitizeEventUser(event: { user?: Record<string, unknown> | null }): void {
  const user = event.user;
  if (!user) {
    return;
  }
  const id = user.id;
  if (!isDiagnosticsRef(id)) {
    // Not an opaque reference of the expected shape — an email, an objid, a
    // random device id, an empty husk. Drop the whole user context rather
    // than forwarding an unrecognised identifier or shipping a husk that
    // Sentry might backfill with an inferred IP.
    delete event.user;
    return;
  }
  event.user = { id, ip_address: null };
}

/**
 * Re-exported so consumers and tests reach the pattern through the boundary
 * that enforces it, without importing the contract module directly.
 */
export { DIAGNOSTICS_REF_PATTERN, isDiagnosticsRef };
