// schemas/errors/classifier.ts
import { createError } from './index';

import { type ApplicationError, isApplicationError } from './index';

export function classifyError(error: unknown): ApplicationError {
  if (isApplicationError(error)) return error;

  if (error instanceof TypeError || error instanceof ReferenceError) {
    return createError(error.message, {
      originalError: error.name,
    });
  }

  if (error instanceof Error) {
    return createError(error.message);
  }

  return createError(String(error));
}

// interface-based approach is better for Vue 3 apps. If type checking is needed, we can use type predicates:
export function isApplicationError(error: unknown): error is ApplicationError {
  return error instanceof Error && 'type' in error && 'severity' in error;
}
