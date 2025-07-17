// src/schemas/errors/classifier.ts

import { NavigationFailure, NavigationFailureType } from 'vue-router';
import { globalComposer } from '@/i18n';

import type { ApplicationError, ErrorType, ErrorSeverity, HttpErrorLike } from './types';
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

      // Include the original issues in the details for debugging
      const details = {
        validationErrors: error.issues.map(issue => ({
          field: issue.path.join('.'),
          code: issue.code,
          message: issue.message,
          // expected and received are not guaranteed properties on ZodIssue,
          // so include them only if they exist
          expected: 'expected' in issue ? issue.expected : undefined,
          received: 'received' in issue ? issue.received : undefined,
        }))
      };

      return wrapError(formattedMessage, 'human', 'error', error, null, details);
    },

  formatZodError(error: ZodError): string {
    if (!error.issues || error.issues.length === 0) {
      return globalComposer.t('web.COMMON.form_validation.form_invalid');
    }

    // Create user-friendly field messages
    const fieldMessages = error.issues.map(issue => {
      const fieldPath = issue.path.length > 0 ? issue.path.join('.') : 'form';
      return this.getFieldErrorMessage(fieldPath, issue);
    });

    // If multiple fields, provide a general message
    if (fieldMessages.length > 1) {
      return globalComposer.t('web.COMMON.form_validation.form_invalid');
    }

    return fieldMessages[0];
  },

  getFieldErrorMessage(field: string, issue: any): string {
    const { t } = globalComposer;

    // Handle specific validation types with i18n
    switch (field) {
      case 'secret':
        if (issue.code === 'too_small') {
          return t('web.COMMON.form_validation.secret_required');
        }
        break;
      case 'ttl':
        return t('web.COMMON.form_validation.ttl_required');
      case 'share_domain':
        if (issue.code === 'invalid_type') {
          return t('web.COMMON.form_validation.share_domain_invalid');
        }
        break;
      case 'passphrase':
        if (issue.code === 'too_small') {
          return t('web.COMMON.form_validation.passphrase_too_short');
        }
        break;
      case 'recipient':
        if (issue.code === 'invalid_string') {
          return t('web.COMMON.form_validation.recipient_invalid');
        }
        break;
    }

    // Use i18n fallback or the original issue message
    return issue.message || t('web.COMMON.unexpected_error');
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
