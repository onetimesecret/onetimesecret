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

import { Scope, type BrowserClient } from '@sentry/browser';

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
 * - errorType: human, security, technical (from error classification)
 * - errorSeverity: error severity level (from error classification)
 * - schema: Zod schema name (lowercase)
 * - service: web, api
 * - jurisdiction: region code from bootstrap.regions.current_jurisdiction
 * - planid: plan identifier from bootstrap.organization.planid
 * - role: customer, colonel, recipient, user_deleted_self from bootstrap.cust.role
 *
 * @see https://github.com/onetimesecret/onetimesecret/issues/2964
 */
const TAG_FIELDS = ['errorType', 'errorSeverity', 'schema', 'service', 'jurisdiction', 'planid', 'role'] as const;
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
