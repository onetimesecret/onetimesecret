// src/schemas/errors/guards.ts

// guards.ts - type guards and validation

import { isNavigationFailure, type NavigationFailure } from 'vue-router';
import { applicationErrorSchema, ApplicationError, HttpErrorLike } from './types';

export const errorGuards = {
  isApplicationError(error: unknown): error is ApplicationError {
    return applicationErrorSchema.safeParse(error).success;
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
      ('isAxiosError' in error || ('status' in error && 'response' in error))
    );
  },

  isRouterError(error: unknown): error is NavigationFailure {
    return isNavigationFailure(error);
  },
};
