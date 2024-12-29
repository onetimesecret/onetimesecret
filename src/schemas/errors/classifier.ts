// schemas/errors/classifier.ts
import { createError } from './factory';
import type { ApplicationError } from './index';

export function classifyError(error: unknown): ApplicationError {
  if (isApplicationError(error)) return error;

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
