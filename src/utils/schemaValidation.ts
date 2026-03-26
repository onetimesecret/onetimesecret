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
 * - Production: loggingService.error (Sentry integration tracked in #2755)
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

  const errorMessage = `Schema validation failed${context ? ` for ${context}` : ''}`;

  if (isDevOrTest()) {
    console.error(errorMessage, result.error.issues);
  } else {
    loggingService.error(
      Object.assign(new Error(errorMessage), {
        cause: result.error,
        issues: result.error.issues,
      })
    );
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
