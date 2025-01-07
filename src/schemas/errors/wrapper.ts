import type { ApplicationError, ErrorSeverity, ErrorType } from './types';

export function wrapError(
  message: string,
  type: ErrorType,
  severity: ErrorSeverity,
  original: Error,
  code?: string | number | null,
  details?: Record<string, unknown>
): ApplicationError {
  const error = new Error(message) as ApplicationError;
  // error.stack is created automatically when `new Error()` is called

  // captureStackTrace customizes the stack trace to:
  // 1. Hide wrapError function from the trace
  // 2. Start trace from caller's location
  Error.captureStackTrace(error, wrapError);

  // Preserve original error's stack if available
  // if (original?.stack) {
  //   error.stack = `${error.stack}\nCaused by: ${original.stack}`;
  // }

  error.name = 'ApplicationError' as const;
  error.type = type;
  error.severity = severity;
  error.original = original;
  error.code = code;
  error.details = details;

  return error;
}

export function createError(
  message: string,
  type: ErrorType,
  severity: ErrorSeverity,
  details?: Record<string, unknown>
): ApplicationError {
  return wrapError(message, type, severity, new Error(message), null, details);
}
