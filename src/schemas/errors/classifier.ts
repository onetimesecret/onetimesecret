// src/schemas/errors/classifier.ts

import { NavigationFailure, NavigationFailureType } from 'vue-router';

import type {
  ApplicationError,
  ErrorType,
  ErrorSeverity,
  HttpErrorLike,
} from './types';
import { errorGuards } from './guards';
import { wrapError } from './wrapper';
import { HTTP_STATUS_CODES } from './constants';
import { ZodError } from 'zod';

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
export const errorClassifier = {
  classify(error: unknown): ApplicationError {
    if (errorGuards.isApplicationError(error)) return error;

    if (errorGuards.isHttpError(error)) {
      return this.classifyHttp(error);
    }

    if (errorGuards.isRouterError(error)) {
      return this.classifyRouter(error);
    }

    if (errorGuards.isValidationError(error)) {
      return this.classifyValidation(error);
    }

    return wrapError(
      error instanceof Error ? error.message : String(error),
      'technical',
      'error',
      error instanceof Error ? error : null
    );
  },

  classifyHttp(error: HttpErrorLike): ApplicationError {
    if (!error.response) {
      return wrapError(
        error.message || 'Network Error',
        'technical',
        'error',
        error as Error,
        error.status // there may not be a status
      );
    }

    const status = error.status || error.response?.status;
    const type = status ? this.getTypeFromStatus(status) : 'technical';
    const details = error.response?.data || {};

    return wrapError(
      details.message || error.message || 'HTTP Error',
      type,
      'error',
      error as Error,
      status,
      details // include the response payload
    );
  },

  classifyRouter(error: NavigationFailure): ApplicationError {
    return wrapError(
      error.message || 'Navigation Error',
      'human',
      'error',
      error,
      NavigationFailureType[error.type] || 'NAVIGATION_ERROR'
    );
  },

  classifyValidation(error: ZodError): ApplicationError {
    // Get a more user-friendly message from the ZodError
    const formattedMessage = this.formatZodError(error);

    return wrapError(
      formattedMessage,
      'human',
      'error',
      error
    );
  },

  formatZodError(error: ZodError): string {
    if (!error.errors || error.errors.length === 0) {
      return 'Validation Error';
    }

    // Get the first error message
    const firstError = error.errors[0];

    if (firstError.code === 'invalid_type') {
      // Format the invalid_type error nicely
      const expected = firstError.expected;
      const received = firstError.received;
      return `Invalid data received. Expected ${expected} but got ${received}.`;
    }

    // Default to the error message
    return firstError.message || 'Validation Error';
  },

  getTypeFromStatus(status: number): ErrorType {
    if (HTTP_STATUS_CODES.SECURITY.has(status)) return 'security';
    if (HTTP_STATUS_CODES.HUMAN.has(status)) return 'human';
    return 'technical';
  },
};

// Convenience function for external use
export function classifyError(error: unknown): ApplicationError {
  return errorClassifier.classify(error as Error);
}

export function createError(
  message: string,
  type: ErrorType,
  severity: ErrorSeverity = 'error',
  details?: Record<string, unknown>
): ApplicationError {
  return wrapError(message, type, severity, null, null, details);
}
