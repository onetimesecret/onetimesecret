import { HTTP_STATUS_CODES } from './constants';
import { applicationErrorSchema, type ApplicationError, type ErrorType } from './types';
import { wrapError } from './wrapper';

// Type guards
export const errorGuards = {
  isApplicationError(error: unknown): error is ApplicationError {
    return (
      error !== null &&
      typeof error === 'object' &&
      'type' in error &&
      'severity' in error &&
      (error as any).name === 'ApplicationError'
    );
  },

  isOfHumanInterest(error: ApplicationError): boolean {
    return error.type === 'human';
  },

  isSecurityIssue(error: ApplicationError): boolean {
    return error.type === 'security';
  },

  /**
   * Type guard to check if an object is an HTTP error (Axios or Fetch)
   * Handles both error types since they share common network error properties
   */
  isHttpError(error: unknown): error is HttpErrorLike {
    return (
      error !== null &&
      typeof error === 'object' &&
      ('isAxiosError' in error ||
        ('status' in error &&
          'statusText' in error &&
          error instanceof Error &&
          'response' in error))
    );
  },
};

interface HttpErrorLike {
  status?: number;
  response?: {
    status?: number;
    data?: {
      message?: string;
    };
  };
  message?: string;
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
export const errorClassifier = {
  classifyByStatusCode(error: HttpErrorLike): ErrorType {
    const status = error.status || error.response?.status;
    if (!status) return 'technical';

    if (HTTP_STATUS_CODES.SECURITY.has(status)) return 'security';
    if (HTTP_STATUS_CODES.HUMAN.has(status)) return 'human';
    return 'technical';
  },

  extractMessage(error: unknown): string {
    if (errorGuards.isHttpError(error)) {
      return error.response?.data?.message || error.message || String(error);
    }
    return error instanceof Error ? error.message : String(error);
  },

  classify(error: unknown): ApplicationError {
    if (errorGuards.isApplicationError(error)) {
      const result = applicationErrorSchema.safeParse(error);
      if (result.success) return error;
    }

    const message = this.extractMessage(error);
    const type = errorGuards.isHttpError(error)
      ? this.classifyByStatusCode(error)
      : 'technical';
    const code = errorGuards.isHttpError(error)
      ? error.status || error.response?.status || 'ERR_HTTP'
      : 'ERR_GENERIC';

    return wrapError(message, type, 'error', error as Error, code);
  },
};

// Convenience function for external use
export function classifyError(error: Error): ApplicationError {
  return errorClassifier.classify(error);
}
