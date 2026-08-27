// src/services/diagnostics.service.ts
//
// Module-level diagnostics service for Sentry integration.
// Decoupled from Vue's provide/inject to allow error capture from anywhere.
//
// Usage:
//   1. Initialize once during app bootstrap: initDiagnostics(client, scope)
//   2. Call captureException() from any module (utils, stores, error handlers)
//
// This fixes #2755 where globalErrorBoundary and schemaValidation had no
// access to Sentry because they couldn't use Vue's inject() mechanism.

import {
  applyActorContext,
  parseDiagnosticsRefBlock,
  type ActorContextScope,
} from '@/plugins/core/diagnostics/actorContext';
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
 * - role: a customerRoleValues member (schemas/contracts/customer.ts) from bootstrap.cust.role
 *
 * @see https://github.com/onetimesecret/onetimesecret/issues/2964
 */
const TAG_FIELDS = [
  'componentName',
  'errorType',
  'errorSeverity',
  'schema',
  'schemaField',
  'service',
  'jurisdiction',
  'planid',
  'role',
] as const;
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
export function captureException(error: Error, context?: Record<string, unknown>): void {
  if (diagnosticsClient) {
    const { client, scope: baseScope } = diagnosticsClient;
    const eventScope = baseScope.clone();

    if (context) {
      const extras = applyTagsFromContext(context, eventScope);
      if (Object.keys(extras).length > 0) {
        eventScope.setExtras(extras);
      }
    }

    // HINT — hand the client the same hint Sentry's own `Scope.captureException`
    // builds. `Client.captureException` does NOT build one: it stamps an
    // `event_id` onto whatever it is given and passes that straight to
    // `beforeSend`. Calling the client directly (which this facade must, to
    // capture against an isolated scope) therefore delivered a hint with no
    // `originalException` — so every beforeSend rule that reads it was inert
    // for every capture the app itself makes:
    //   - the expected-transport-outcome drop (#4286) never dropped anything;
    //   - the api-error grouping (#4287) never fingerprinted anything, leaving
    //     axios failures to fragment on minified stack frames — one new issue
    //     per call site per deploy.
    // The synthetic exception is the other half: it is what gives a non-Error
    // input a usable stack instead of a bare, unfingerprintable `Error`.
    client.captureException(
      error,
      { originalException: error, syntheticException: new Error('Sentry syntheticException') },
      eventScope
    );
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
export function captureMessage(message: string, context?: Record<string, unknown>): void {
  if (diagnosticsClient) {
    const { client, scope: baseScope } = diagnosticsClient;
    const eventScope = baseScope.clone();

    if (context) {
      const extras = applyTagsFromContext(context, eventScope);
      if (Object.keys(extras).length > 0) {
        eventScope.setExtras(extras);
      }
    }

    // Same hint contract as captureException above; see the note there.
    client.captureMessage(
      message,
      undefined,
      {
        originalException: message,
        syntheticException: new Error('Sentry syntheticException'),
      },
      eventScope
    );
  } else {
    console.warn('[Diagnostics] Message captured (Sentry unavailable):', message);
    if (context) {
      console.warn('[Diagnostics] Context:', context);
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// USER CONTEXT — the runtime half of the pseudonymous-reference boundary
// ═══════════════════════════════════════════════════════════════════════════════
//
// `createDiagnostics()` sets user context once, at boot, from the bootstrap
// snapshot. It is not static after that: it changes on login, on MFA
// completion, on the 15-minute /bootstrap/me refresh (which can report a
// DIFFERENT account after a re-auth in another tab), and on logout.
//
// These two functions are the callable surface for those transitions. They
// live here rather than in enableDiagnostics.ts for three reasons:
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
 * The scopes user context must be written to.
 *
 * BOTH are required, always:
 *   - `diagnosticsClient.scope` — the isolated scope, cloned per manual
 *     capture in captureException/captureMessage above.
 *   - `getCurrentScope()` — where integration-captured events (unhandled
 *     rejections, browserApiErrors async callbacks, browserTracing
 *     transactions) resolve their context, because `setCurrentClient` bound
 *     the client there.
 *
 * Writing only one leaves half of all events carrying the PREVIOUS reference
 * after an account change — a worse outcome than never identifying, because
 * it mislabels one account's errors as another's.
 *
 * NOTE on clone timing: captureException/captureMessage clone the base scope
 * per capture and never cache the clone, so a later context change is picked
 * up by the next capture. Do not hoist those clones.
 */
function actorContextScopes(): ActorContextScope[] {
  if (!diagnosticsClient) {
    return [];
  }
  return [diagnosticsClient.scope, getCurrentScope()];
}

/**
 * Sets (or replaces) the Sentry user context from a server-provided
 * `diagnostics_ref` block.
 *
 * The input is UNTRUSTED and is validated against the strict contract before
 * anything is forwarded: an unknown key, a malformed ref, or a missing ref all
 * resolve to null and CLEAR the context rather than partially applying it.
 * Passing null clears it outright.
 *
 * Emits exactly `user = { id: <ref>, ip_address: null }` — no tags. Never an
 * email, name, objid, extid, or IP.
 *
 * Safe to call when diagnostics are disabled — it is a no-op.
 *
 * @param block - The raw bootstrap `diagnostics_ref` block, or null/undefined
 *   for an anonymous session.
 *
 * @example
 * ```typescript
 * // bootstrapStore.update(), covering login, MFA completion, and refresh
 * setDiagnosticsActorContext(data.diagnostics_ref);
 * ```
 */
export function setDiagnosticsActorContext(block: unknown): void {
  const scopes = actorContextScopes();
  if (scopes.length === 0) {
    return;
  }
  applyActorContext(scopes, parseDiagnosticsRefBlock(block));
}

/**
 * Clears the Sentry user context: `setUser(null)` on every scope.
 *
 * Call on LOGOUT and on any account change where the new session's ref is not
 * yet known. User context is the only dimension the actor boundary writes, so
 * this is a complete eviction — without it, a now-anonymous session would keep
 * reporting under the previous, identified session's ref.
 *
 * Only the soft/SPA logout path needs this. Hard logouts navigate with
 * `window.location.href`, which tears down the JS context and the scopes with
 * it; calling it there is harmless but redundant.
 *
 * Safe to call when diagnostics are disabled — it is a no-op.
 */
export function clearDiagnosticsActorContext(): void {
  const scopes = actorContextScopes();
  if (scopes.length === 0) {
    return;
  }
  applyActorContext(scopes, null);
}
