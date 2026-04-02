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
 * @param error - The error to capture
 * @param context - Optional extra context to attach to the event
 *
 * @example
 * ```typescript
 * captureException(new Error('Schema validation failed'), {
 *   schema: 'SecretResponse',
 *   issues: zodError.issues,
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
      eventScope.setExtras(context);
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
 */
export function captureMessage(
  message: string,
  context?: Record<string, unknown>
): void {
  if (diagnosticsClient) {
    const { client, scope: baseScope } = diagnosticsClient;
    const eventScope = baseScope.clone();

    if (context) {
      eventScope.setExtras(context);
    }

    client.captureMessage(message, undefined, undefined, eventScope);
  } else {
    console.warn('[Diagnostics] Message captured (Sentry unavailable):', message);
    if (context) {
      console.warn('[Diagnostics] Context:', context);
    }
  }
}
