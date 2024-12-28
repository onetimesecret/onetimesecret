// schemas/errors/classifier.ts

import { type ApplicationError, isApplicationError } from './index';

export function classifyError(error: unknown): ApplicationError {
  if (isApplicationError(error)) return error;

  return {
    name: 'UnknownError',
    message: error instanceof Error ? error.message : String(error),
    type: 'technical',
    severity: 'error',
  };
}
