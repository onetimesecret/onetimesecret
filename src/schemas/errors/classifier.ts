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
        error.status
      );
    }

    const status = error.status || error.response?.status;
    const details = error.response?.data || {};
    const userMessage = this.extractUserMessage(details, error);
    const type = this.determineHttpErrorType(status, details);

    return wrapError(
      userMessage,
      type,
      'error',
      error as Error,
      status,
      details
    );
  },

  extractUserMessage(details: any, error: HttpErrorLike): string {
    // Check both 'error' (Rodauth format) and 'message' (standard format)
    return details.error || details.message || error.message || 'HTTP Error';
  },

  determineHttpErrorType(status: number | undefined, details: any): ErrorType {
    if (!status) return 'technical';

    // If backend provides field-level errors, it's always a human error (form validation)
    if (details['field-error']) {
      return 'human';
    }

    // Heuristic: If backend sends a user-friendly message for a client error (4xx),
    // it's signaling that this error is user-actionable, regardless of status code.
    // The backend controls classification by choosing to include a friendly message.
    const hasUserMessage = Boolean(details.error || details.message);
    const isClientError = status >= 400 && status < 500;

    if (hasUserMessage && isClientError) {
      // Exception: Rate limiting is always a security concern even with a message
      if (status === 429) return 'security';

      // All other 4xx with friendly messages are user-actionable
      return 'human';
    }

    // Fall back to status-based classification
    return this.getTypeFromStatus(status);
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
    if (!error.issues || error.issues.length === 0) {
      return 'Validation Error';
    }

    // Get the first error message
    const firstError = error.issues[0];

    if (firstError.code === 'invalid_type') {
      // Format the invalid_type error nicely
      const expected = (firstError as any).expected;
      const received = (firstError as any).received;
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
