// src/services/diagnostics.service.ts
//
// Module-level diagnostics service for Sentry integration.
// Decoupled from Vue's provide/inject to allow error capture from anywhere.
//
// DIAGNOSTICS, NOT ANALYTICS. Everything captured here exists to make a defect
// traceable to the code and the endpoint that produced it. Nothing on this
// surface counts usage, measures behaviour, or feeds reporting — which is the
// standard a proposed new tag or extra has to meet before it is added below.
//
// Usage:
//   1. Initialize once during app bootstrap: initDiagnostics(client, scope)
//   2. Call captureException() from any module (utils, stores, error handlers)
//
// This fixes #2755 where globalErrorBoundary and schemaValidation had no
// access to Sentry because they couldn't use Vue's inject() mechanism.

import {
  applyActorIdentity,
  parseDiagnosticsActorBlock,
  type IdentityScope,
} from '@/plugins/core/diagnostics/actorIdentity';
import { Scope, getCurrentScope, type BrowserClient } from '@sentry/browser';

interface DiagnosticsClient {
  client: BrowserClient;
  scope: Scope;
}

let diagnosticsClient: DiagnosticsClient | null = null;

/**
 * Tag fields that should be indexed in Sentry for searchability.
 * These are extracted from context and set via setTag() instead of setExtras().
 * All tag values are normalized to lowercase for consistent querying.
 *
 * Tags:
 * - componentName: Vue component name where error occurred (#2966)
 * - errorType: human, security, technical (from error classification)
 * - errorSeverity: error severity level (from error classification)
 * - schema: Zod schema name (lowercase)
 * - schemaField: failing field path(s) for a schema validation error (#3424)
 * - service: web, api
 * - jurisdiction: region code from bootstrap.regions.current_jurisdiction
 * - planid: plan identifier from bootstrap.organization.planid
 * - role: customer, colonel, recipient, user_deleted_self from bootstrap.cust.role
 * - apiRoute: PARAMETERIZED API route the failing payload came from (never the
 *   resolved URL) — see src/utils/diagnostics/apiRouteContext.ts
 * - organization_ref: opaque, server-derived organization pseudonym (16
 *   lowercase hex), emitted ONLY for schemas enrolled in
 *   src/utils/diagnostics/resourceRefRegistry.ts and only after that module has
 *   shape-checked the value. Never an extid, name, email or billing id.
 *
 * ON `organization_ref` BEING A TAG AND NOT AN EXTRA: the ref answers exactly
 * one question — "is one organization failing, or all of them?" — and that is
 * a COUNT over the failing events. Counting requires an indexed dimension;
 * `event.extra` is not indexed, so a ref there would be readable one event at
 * a time and never aggregated, which is the whole value gone. Its cardinality
 * is bounded by the tenant count on an internal/admin surface, not by the
 * request count, and the value carries no meaning outside the keying secret.
 *
 * NOTE FOR ANY FUTURE TAG: the VALUE is lowercased below. A tag whose value
 * is case-significant must be validated before it reaches here, which is why
 * the ref registry refuses uppercase hex instead of normalizing it — otherwise
 * a non-ref value could arrive looking like a ref.
 *
 * ON `apiRoute` BEING A TAG AND NOT AN EXTRA: route-level aggregation is the
 * entire point of emitting it. `event.extra` is not indexed and not
 * searchable, so an `apiRoute` living there could be read one event at a time
 * and never queried — `apiRoute:"/api/colonel/organizations/:org_id"` is the
 * question an operator actually asks when a Colonel response shape drifts.
 * Every route reaching here has been through `sanitizeApiRoute` —
 * parameterize, then scrub, then length-cap, with no way to opt out. For a
 * path whose id sits under a collection named in `PARAM_NAME_BY_COLLECTION`
 * that is a guarantee, and cardinality is bounded by the ROUTE TABLE rather
 * than by the tenant count. Elsewhere the parameterization is a SHAPE
 * heuristic: a short, all-lowercase, digit-free segment under an unmapped
 * parent can still ride out verbatim, with only the scrub nets behind it. See
 * the "WHAT IS GUARANTEED, AND WHAT IS NOT" section in
 * src/utils/diagnostics/apiRouteContext.ts; mapping a new id-bearing
 * collection there is how an endpoint moves from the second case to the first.
 *
 * @see https://github.com/onetimesecret/onetimesecret/issues/2964
 */
const TAG_FIELDS = ['componentName', 'errorType', 'errorSeverity', 'schema', 'schemaField', 'service', 'jurisdiction', 'planid', 'role', 'apiRoute', 'organization_ref'] as const;
type _TagField = (typeof TAG_FIELDS)[number]; // Used for documentation; lookup via Set<string>
const TAG_FIELDS_SET = new Set<string>(TAG_FIELDS);

/**
 * Extracts tag fields from context and applies them to the scope.
 * Returns the remaining context fields for use with setExtras().
 *
 * @param context - The context object containing tags and extras
 * @param eventScope - The Sentry scope to apply tags to
 * @returns The remaining context fields (non-tag fields)
 */
function applyTagsFromContext(
  context: Record<string, unknown>,
  eventScope: Scope
): Record<string, unknown> {
  const extras: Record<string, unknown> = {};

  for (const [key, value] of Object.entries(context)) {
    if (TAG_FIELDS_SET.has(key)) {
      // Tag fields are handled exclusively - set if valid, skip if null/undefined
      if (value !== undefined && value !== null) {
        // Tags must be strings and normalized to lowercase
        const tagValue = String(value).toLowerCase();
        eventScope.setTag(key, tagValue);
      }
    } else {
      extras[key] = value;
    }
  }

  return extras;
}

/**
 * Initialize the diagnostics service with Sentry client and scope.
 * Called once during app startup from enableDiagnostics plugin.
 */
export function initDiagnostics(client: BrowserClient, scope: Scope): void {
  diagnosticsClient = { client, scope };
}

/**
 * Check if diagnostics (Sentry) is initialized.
 */
export function isDiagnosticsEnabled(): boolean {
  return diagnosticsClient !== null;
}

/**
 * Capture an exception to Sentry with optional context.
 * Falls back to console.error if Sentry is not initialized.
 *
 * Tag fields (errorType, schema, service, jurisdiction, planid, role) are
 * extracted and set via setTag() for Sentry indexing. Remaining fields use setExtras().
 *
 * @param error - The error to capture
 * @param context - Optional extra context to attach to the event
 *
 * @example
 * ```typescript
 * captureException(new Error('Schema validation failed'), {
 *   schema: 'SecretResponse',
 *   errorType: 'technical',
 *   service: 'web',
 *   jurisdiction: 'eu',
 *   issues: zodError.issues, // goes to extras
 * });
 * ```
 */
export function captureException(
  error: Error,
  context?: Record<string, unknown>
): void {
  if (diagnosticsClient) {
    const { client, scope: baseScope } = diagnosticsClient;
    const eventScope = baseScope.clone();

    if (context) {
      const extras = applyTagsFromContext(context, eventScope);
      if (Object.keys(extras).length > 0) {
        eventScope.setExtras(extras);
      }
    }

    client.captureException(error, undefined, eventScope);
  } else {
    // Sentry not available, log to console as fallback
    console.error('[Diagnostics] Exception captured (Sentry unavailable):', error);
    if (context) {
      console.error('[Diagnostics] Context:', context);
    }
  }
}

/**
 * Capture a message to Sentry with optional context.
 * Useful for non-exception events that should be tracked.
 *
 * Tag fields (errorType, schema, service, jurisdiction, planid, role) are
 * extracted and set via setTag() for Sentry indexing. Remaining fields use setExtras().
 */
export function captureMessage(
  message: string,
  context?: Record<string, unknown>
): void {
  if (diagnosticsClient) {
    const { client, scope: baseScope } = diagnosticsClient;
    const eventScope = baseScope.clone();

    if (context) {
      const extras = applyTagsFromContext(context, eventScope);
      if (Object.keys(extras).length > 0) {
        eventScope.setExtras(extras);
      }
    }

    client.captureMessage(message, undefined, undefined, eventScope);
  } else {
    console.warn('[Diagnostics] Message captured (Sentry unavailable):', message);
    if (context) {
      console.warn('[Diagnostics] Context:', context);
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// ACTOR IDENTITY — the runtime half of the privacy boundary
// ═══════════════════════════════════════════════════════════════════════════════
//
// `createDiagnostics()` sets actor identity once, at boot, from the bootstrap
// snapshot. Identity is not static after that: it changes on login, on MFA
// completion, on the 15-minute /bootstrap/me refresh (which can report a
// DIFFERENT account after a re-auth in another tab), and on logout.
//
// These two functions are the callable surface for those transitions. They live
// here rather than in enableDiagnostics.ts for three reasons:
//
//   1. This module is already the module-level facade for non-Vue callers
//      (stores, guards, globalErrorBoundary, schemaValidation).
//   2. Callers must be able to invoke them UNCONDITIONALLY. Diagnostics are
//      disabled in most deployments; a store should not have to know that.
//      Both no-op cleanly when `initDiagnostics` never ran.
//   3. Exporting the scopes themselves from enableDiagnostics.ts would let any
//      caller write arbitrary user context, defeating the single-writer
//      property that makes the boundary auditable.

/**
 * The scopes actor identity must be written to.
 *
 * BOTH are required, always:
 *   - `diagnosticsClient.scope` — the isolated scope, cloned per manual capture
 *     in captureException/captureMessage above.
 *   - `getCurrentScope()` — where integration-captured events (unhandled
 *     rejections, browserApiErrors async callbacks, browserTracing
 *     transactions) resolve their context, because `setCurrentClient` bound
 *     the client there.
 *
 * Writing only one leaves half of all events carrying the PREVIOUS actor after
 * an account change — a worse outcome than never identifying, because it
 * mislabels one account's errors as another's.
 *
 * NOTE on clone timing: captureException/captureMessage clone the base scope
 * per capture and never cache the clone, so a later identity change is picked
 * up by the next capture. Do not hoist those clones.
 */
function identityScopes(): IdentityScope[] {
  if (!diagnosticsClient) {
    return [];
  }
  return [diagnosticsClient.scope, getCurrentScope()];
}

/**
 * Sets (or replaces) the Sentry actor from a server-provided `diagnostics_actor` block.
 *
 * The input is UNTRUSTED and is validated against the strict contract before
 * anything is forwarded: an unknown key, a bad `actor_scope`, or a missing
 * `actor_ref` all resolve to null and CLEAR identity rather than partially
 * applying it. Passing null clears identity outright.
 *
 * Emits exactly `user = { id: diagnosticsActor.actor_ref, ip_address: null }` and the
 * `actor_scope` tag. Never an email, name, objid, extid, or IP.
 *
 * Safe to call when diagnostics are disabled — it is a no-op.
 *
 * @param diagnosticsActor - The raw bootstrap `diagnostics_actor` block, or null/undefined for
 *   an anonymous session.
 *
 * @example
 * ```typescript
 * // bootstrapStore.update(), covering login, MFA completion, and refresh
 * setDiagnosticsActor(data.diagnostics_actor);
 * ```
 */
export function setDiagnosticsActor(diagnosticsActor: unknown): void {
  const scopes = identityScopes();
  if (scopes.length === 0) {
    return;
  }
  applyActorIdentity(scopes, parseDiagnosticsActorBlock(diagnosticsActor));
}

/**
 * Clears the Sentry actor: `setUser(null)` plus removal of the `actor_scope`
 * tag, on every scope.
 *
 * Call on LOGOUT and on any account change where the new identity is not yet
 * known. The tag removal matters as much as the user clear — a stale
 * `actor_scope` would let a now-anonymous session be filtered in Sentry as
 * though it were still the previous, identified actor.
 *
 * Only the soft/SPA logout path needs this. Hard logouts navigate with
 * `window.location.href`, which tears down the JS context and the scopes with
 * it; calling it there is harmless but redundant.
 *
 * Safe to call when diagnostics are disabled — it is a no-op.
 */
export function clearDiagnosticsActor(): void {
  const scopes = identityScopes();
  if (scopes.length === 0) {
    return;
  }
  applyActorIdentity(scopes, null);
}
