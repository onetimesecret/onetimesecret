// schemas/api/errors.ts

import { AxiosError } from 'axios';
import { z } from 'zod';

// First, let's define our base error class
export class ApiError extends Error {
  constructor(
    public code: number,
    message: string,
    public details?: unknown
  ) {
    super(message);
    this.name = this.constructor.name;
  }
}

export const ErrorCode = {
  INVALID_AUTH: 401,
  NOT_FOUND: 404,
  PERMISSION_DENIED: 403,
  VALIDATION_ERROR: 422,
  SERVER_ERROR: 500,
} as const;

export const ErrorType = {
  AUTH: 'auth_error',
  NOT_FOUND: 'not_found',
  PERMISSION: 'permission_error',
  VALIDATION: 'validation_error',
  SERVER: 'server_error',
} as const;

// Unified error handler
export function handleError(error: unknown): ApiError {
  // Zod validation errors
  if (error instanceof z.ZodError) {
    const firstError = error.errors[0];
    return new ApiError(ErrorCode.VALIDATION_ERROR, firstError.message, {
      type: ErrorType.VALIDATION,
      field: firstError.path.join('.'),
      details: error.errors.map((err) => ({
        path: err.path,
        message: err.message,
      })),
    });
  }

  // API errors
  if (error instanceof AxiosError) {
    const status = error.response?.status || ErrorCode.SERVER_ERROR;
    return new ApiError(status, error.message);
  }

  // Already handled errors
  if (error instanceof ApiError) {
    return error;
  }

  // Unexpected errors
  return new ApiError(
    ErrorCode.SERVER_ERROR,
    error instanceof Error ? error.message : 'An unexpected error occurred'
  );
}
