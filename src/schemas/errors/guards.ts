// src/schemas/errors/guards.ts

// guards.ts - type guards and validation

import { isNavigationFailure, type NavigationFailure } from 'vue-router';
import {
  applicationErrorSchema,
  ApplicationError,
  HttpErrorLike,
} from './types';
import { ZodError } from 'zod';
import { AxiosError } from 'axios';

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
  isZodError(error: unknown): error is ZodError {
    return error instanceof ZodError;
  },

  isAxiosError(error: unknown): error is AxiosError {
    return error instanceof AxiosError;
  },

  isFetchError(error: unknown): error is TypeError | DOMException {
    return (
      error instanceof TypeError ||
      // For browsers that don't support AbortError
      (error instanceof DOMException && error.name === 'AbortError')
    );
  },

  isRouterError(error: unknown): error is NavigationFailure {
    return isNavigationFailure(error);
  },

  isValidationError(error: unknown): error is ZodError {
    return this.isZodError(error);
  },

  isHttpError(error: unknown): error is HttpErrorLike {
    return this.isAxiosError(error) || this.isFetchError(error);
  },
};
