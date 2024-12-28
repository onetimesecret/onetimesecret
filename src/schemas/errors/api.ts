// schemas/errors/api.ts

import { AxiosError } from 'axios';
import { z } from 'zod';
import { DomainError } from './domain';

export class TechnicalError extends Error {
  constructor(
    public code: number,
    message: string,
    public userMessage: string,
    public retryable: boolean = false,
    public details?: unknown
  ) {
    super(message);
    this.name = this.constructor.name;
  }
}

export class ApiError extends TechnicalError {
  static readonly CODES = {
    INVALID_AUTH: 401,
    NOT_FOUND: 404,
    PERMISSION_DENIED: 403,
    VALIDATION_ERROR: 422,
    RATE_LIMIT: 429,
    SERVER_ERROR: 500,
    GATEWAY_ERROR: 502,
    SERVICE_UNAVAILABLE: 503,
  } as const;

  constructor(
    code: number,
    message: string,
    userMessage: string,
    retryable: boolean = false,
    details?: unknown
  ) {
    super(code, message, userMessage, retryable, details);
  }

  static fromStatus(status: number, message?: string): ApiError {
    switch (status) {
      case this.CODES.INVALID_AUTH:
        return new ApiError(
          status,
          message || 'Authentication failed',
          'Please sign in again to continue',
          false
        );
      case this.CODES.NOT_FOUND:
        return new ApiError(
          status,
          message || 'Resource not found',
          'The requested item could not be found',
          false
        );
      case this.CODES.PERMISSION_DENIED:
        return new ApiError(
          status,
          message || 'Permission denied',
          "You don't have permission to perform this action",
          false
        );
      case this.CODES.RATE_LIMIT:
        return new ApiError(
          status,
          message || 'Too many requests',
          'Please wait a moment before trying again',
          true
        );
      case this.CODES.VALIDATION_ERROR:
        return new ApiError(
          status,
          message || 'Validation failed',
          'Please check your input and try again',
          false
        );
      default:
        return new ApiError(
          status,
          message || 'Server error occurred',
          'Something went wrong. Please try again later.',
          status >= 500
        );
    }
  }
}

export class NetworkError extends TechnicalError {
  constructor(message: string, details?: unknown) {
    super(
      0,
      message,
      'Unable to connect to the server. Please check your connection.',
      true,
      details
    );
  }
}

export class ValidationError extends TechnicalError {
  constructor(errors: z.ZodError) {
    const details = errors.errors.map((err) => ({
      path: err.path,
      message: err.message,
    }));

    super(
      422,
      'Validation failed',
      'Please check your input and try again',
      false,
      details
    );
  }
}

// Type guard helpers
export function isTechnicalError(error: unknown): error is TechnicalError {
  return error instanceof TechnicalError;
}

export function isNetworkError(error: unknown): error is NetworkError {
  return error instanceof NetworkError;
}

// Enhanced error handler
export function handleError(error: unknown): TechnicalError | DomainError {
  // Handle Zod validation errors
  if (error instanceof z.ZodError) {
    return new ValidationError(error);
  }

  // Handle Axios errors
  if (error instanceof AxiosError) {
    if (!error.response) {
      return new NetworkError(error.message);
    }
    return ApiError.fromStatus(error.response.status, error.message);
  }

  // Pass through domain errors
  if (error instanceof DomainError) {
    return error;
  }

  // Handle technical errors
  if (error instanceof TechnicalError) {
    return error;
  }

  // Default error handling
  return new ApiError(
    500,
    error instanceof Error ? error.message : 'An unexpected error occurred',
    'Something went wrong. Please try again later.',
    true
  );
}
