// src/schemas/errors/wrapper.ts

import type { ApplicationError, ErrorSeverity, ErrorType } from './types';
import { applicationErrorSchema } from './types';

export function wrapError(
  message: string,
  type: ErrorType,
  severity: ErrorSeverity,
  original: Error | null,
  code?: string | number | null,
  details?: Record<string, unknown>
): ApplicationError {
  // const error = new Error(message) as ApplicationError;
  // // error.stack is created automatically when `new Error()` is called

  // // captureStackTrace customizes the stack trace to:
  // // 1. Hide wrapError function from the trace
  // // 2. Start trace from caller's location
  // Error.captureStackTrace(error, wrapError);

  // Preserve original error's stack if available
  // if (original?.stack) {
  //   error.stack = `${error.stack}\nCaused by: ${original.stack}`;
  // }

  const error = {
    name: 'ApplicationError' as const,
    message,
    type,
    severity,
    code,
    original,
    details,
  };

  return applicationErrorSchema.parse(error);
}
