// schemas/errors/classifier.ts
import type { ApplicationError, ErrorSeverity, ErrorType } from './index';

export function classifyError(error: unknown): ApplicationError {
  if (isApplicationError(error)) return error;

  if (isApiError(error)) {
    // HTTP 404, 403, etc are typically human-facing errors
    const isHumanError = error.status && [403, 404].includes(error.status);
    return createError(error.message, isHumanError ? 'human' : 'technical', 'error');
  }

  if (error instanceof Error) {
    return createError(error.message);
  }

  return createError(String(error));
}

export function isApplicationError(error: unknown): error is ApplicationError {
  return error instanceof Error && 'type' in error && 'severity' in error;
}

export function isOfHumanInterest(error: ApplicationError): boolean {
  return error.type === 'human';
}

export function isApiError(
  error: unknown
): error is { message: string; status?: number } {
  return typeof error === 'object' && error !== null && 'message' in error;
}

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
