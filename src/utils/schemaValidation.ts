// src/utils/schemaValidation.ts
//
// Schema validation with uniform control flow.
// Always returns ParseResult — callers decide the degradation strategy:
//   - List fetches: degrade to empty state
//   - Mutations: throw clean Error for the user
//   - Identity/config: degrade to defaults
//
// Reporting is environment-aware (loud in dev, logged in prod) but control
// flow is identical everywhere, so fallback paths are testable.
//
// Stores are error producers, not handlers. They validate at the API boundary
// and throw clean errors upward. Composables and components handle those errors
// — typically via `wrap` from useAsyncHandler — to classify, log, and present
// them to users. gracefulParse translates raw ZodErrors (schema internals)
// into ParseResult the store can act on, keeping validation details from
// leaking to consuming code.

import { z } from 'zod';
import { captureException } from '@/services/diagnostics.service';
import { loggingService } from '@/services/logging.service';

/**
 * Discriminated union for parse results.
 * Avoids ambiguity when null could be a valid domain value.
 */
export type ParseResult<T> =
  | { ok: true; data: T }
  | { ok: false; error: z.ZodError | null };

/**
 * Determines if we're in a development or test environment.
 */
function isDevOrTest(): boolean {
  // Vite dev mode
  if (typeof import.meta !== 'undefined' && import.meta.env?.DEV) {
    return true;
  }
  // Node test environment
  if (typeof process !== 'undefined' && process.env?.NODE_ENV === 'test') {
    return true;
  }
  return false;
}

/**
 * Parse data with a Zod schema, returning a discriminated result.
 *
 * Always returns ParseResult — never throws. Callers decide what to do
 * with { ok: false } based on context (throw, degrade, ignore).
 *
 * Error reporting is environment-aware:
 * - Dev/test: console.error for immediate visibility
 * - Production: captureException sends to Sentry with schema context
 *
 * @example
 * ```typescript
 * const result = gracefulParse(responseSchemas.secret, response.data, 'SecretResponse');
 * if (!result.ok) {
 *   throw new Error('Unable to load secret. Please try again.');
 * }
 * // result.data is now type-safe and guaranteed valid
 * record.value = result.data.record;
 * ```
 */
export function gracefulParse<T>(
  schema: z.ZodType<T>,
  data: unknown,
  context?: string
): ParseResult<T> {
  const result = schema.safeParse(data);

  if (result.success) {
    return { ok: true, data: result.data };
  }

  // #3424: surface the field(s) that actually failed. Three fixes missed this
  // bug because production discarded the failing field — the generic message
  // reached the local log while the precise `issues[].path` lived only in
  // non-searchable Sentry extras. We now build the message FROM the issues and
  // expose the failing paths as a searchable `schemaField` tag, so the next
  // "no longer available" report names its own cause instead of being inferred.
  //
  // Only field paths, issue codes, and Zod's type-level messages are logged —
  // never the offending values — so this stays safe for secret payloads.
  const issues = result.error.issues;
  const fieldPaths = [...new Set(issues.map((i) => i.path.join('.') || '(root)'))];
  const fieldSummary = issues
    .map((i) => `${i.path.join('.') || '(root)'}: ${i.code} (${i.message})`)
    .join('; ');
  const errorMessage =
    `Schema validation failed${context ? ` for ${context}` : ''}` +
    ` — ${issues.length} issue(s) [${fieldPaths.join(', ')}]: ${fieldSummary}`;

  if (isDevOrTest()) {
    console.error(errorMessage, issues);
  } else {
    // Log locally (message now carries the fields) and send to Sentry with the
    // failing paths promoted to a searchable tag, not just buried in extras.
    const schemaError = new Error(errorMessage);
    loggingService.error(schemaError);
    captureException(schemaError, {
      schema: context,
      schemaField: fieldPaths.join(',').slice(0, 200),
      issues,
      issueCount: issues.length,
    });
  }

  return { ok: false, error: result.error };
}

/**
 * Strict parse that always throws on validation failure.
 * Use for critical paths where invalid data should halt execution.
 */
export function strictParse<T>(schema: z.ZodType<T>, data: unknown): T {
  return schema.parse(data);
}
