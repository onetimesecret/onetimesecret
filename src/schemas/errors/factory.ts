// schemas/errors/factory.ts
import type { ApplicationError, ErrorSeverity, ErrorType } from './index';

// export const ErrorFactory = {
//   technical: createTechnicalError,
//   human: createBusinessError,
//   security: createSecurityError,
// };

// Separated out from index.ts so that we can avoid circular dependencies

/**
 * * Creates a structured ApplicationError with consistent typing and metadata
 *
 * Usage example:
 *   throw createTechnicalError(`Failed to fetch secret: ${response.statusText}`, {
 *     status: response.status,
 *     key
 *   });
 *
 *
 * @param message
 * @param type
 * @param severity
 * @param details
 * @returns
 *
 */
export function createError(
  message: string,
  type: ErrorType = 'technical',
  severity: ErrorSeverity = 'error',
  details?: Record<string, unknown>
): ApplicationError {
  const error = new Error(message) as ApplicationError;
  error.type = type;
  error.severity = severity;
  error.details = details;
  return error;
}
