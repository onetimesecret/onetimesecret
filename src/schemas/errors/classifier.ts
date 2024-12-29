import type { ApplicationError, ErrorSeverity, ErrorType } from './index';

/**
 * Classifies errors into application-specific categories based on their properties.
 *
 * HTTP Status Code Classification:
 * - 403 Forbidden -> Security Error (authentication/authorization issues)
 * - 404 Not Found -> Human Error (user-facing navigation/resource issues)
 * - Others -> Technical Error (system/infrastructure issues)
 *
 * @param error - The error to classify
 * @returns ApplicationError with appropriate type and severity
 */
export function classifyError(error: unknown): ApplicationError {
  if (isApplicationError(error)) return error;

  if (isApiError(error)) {
    // Security-related HTTP status codes
    if (error.status === 403) {
      return createError(error.message, 'security', 'error');
    }

    // User-facing HTTP status codes
    const isHumanError = error.status && [404].includes(error.status);
    return createError(error.message, isHumanError ? 'human' : 'technical', 'error');
  }

  if (error instanceof Error) {
    return createError(error.message);
  }

  return createError(String(error));
}

/**
 * Type guard to check if an error is already classified as an ApplicationError
 */
export function isApplicationError(error: unknown): error is ApplicationError {
  return error instanceof Error && 'type' in error && 'severity' in error;
}

/**
 * Type guard to check if an error is human-facing
 */
export function isOfHumanInterest(error: ApplicationError): boolean {
  return error.type === 'human';
}

/**
 * Type guard to check if an error is security-related
 */
export function isSecurityIssue(error: ApplicationError): boolean {
  return error.type === 'security';
}

/**
 * Type guard to check if an object is an API error with status code
 */
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
