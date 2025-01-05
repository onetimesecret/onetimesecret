import {
  createApplicationError,
  type ApplicationError,
  type ErrorSeverity,
  type ErrorType,
} from './types';

// HTTP status codes categorized by error type
const SECURITY_STATUS_CODES = new Set([
  401, // Unauthorized
  403, // Forbidden
  429, // Too Many Requests
  407, // Proxy Authentication Required
  423, // Locked
]);

const HUMAN_STATUS_CODES = new Set([
  404, // Not Found
  409, // Conflict
  400, // Bad Request
  405, // Method Not Allowed
  410, // Gone
]);

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
  severity: ErrorSeverity = 'error'
): ApplicationError {
  const error = createApplicationError(message, type, severity);
  Error.captureStackTrace(error, createError);
  return error;
}

/**
 * Classifies errors into application-specific categories based on their properties.
 *
 * Error Type Classification:
 * - Security: Status codes in SECURITY_STATUS_CODES (auth/rate-limit issues)
 * - Human: Status codes in HUMAN_STATUS_CODES (user-facing resource issues)
 * - Technical: System errors and unclassified status codes
 *
 * @param error - The error to classify
 * @returns ApplicationError with appropriate type and severity
 */
export function classifyError(error: unknown): ApplicationError {
  if (isApplicationError(error)) return error;

  const message = error instanceof Error ? error.message : String(error);
  let type: ErrorType = 'technical';

  if (isApiError(error) && error.status) {
    if (SECURITY_STATUS_CODES.has(error.status)) {
      type = 'security';
    } else if (HUMAN_STATUS_CODES.has(error.status)) {
      type = 'human';
    }
  }

  const classified = createError(message, type, 'error');
  Error.captureStackTrace(classified, classifyError);
  return classified;
}

/**
 * Type guard to check if an error is already classified as an ApplicationError
 */
export function isApplicationError(error: unknown): error is ApplicationError {
  return (
    error instanceof Error &&
    'type' in error &&
    'severity' in error &&
    error.name === 'ApplicationError'
  );
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
