// src/utils/schemaValidation.ts
//
// Environment-aware schema validation utilities.
// Dev/Test: Throws validation errors immediately for fast feedback
// Production: Logs errors and returns failure result for graceful degradation

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
 * Parse data with a Zod schema, handling errors differently by environment.
 *
 * In development/test:
 * - Throws ZodError immediately for fast feedback
 *
 * In production:
 * - Logs error to console (integrate with Sentry via loggingService)
 * - Returns { ok: false } for explicit failure handling
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

  // In dev/test, throw for immediate feedback
  if (isDevOrTest()) {
    throw result.error;
  }

  // In production, log and return failure
  const errorMessage = `Schema validation failed${context ? ` for ${context}` : ''}`;
  loggingService.error(
    Object.assign(new Error(errorMessage), {
      cause: result.error,
      issues: result.error.issues,
    })
  );

  return { ok: false, error: result.error };
}

/**
 * Strict parse that always throws on validation failure.
 * Use for critical paths where invalid data should halt execution.
 */
export function strictParse<T>(schema: z.ZodType<T>, data: unknown): T {
  return schema.parse(data);
}
