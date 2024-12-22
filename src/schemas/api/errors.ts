// src/schemas/api/errors.ts
import { z } from 'zod';

import { apiErrorResponseSchema } from '../api/base';

// Domain-specific error codes
export const ErrorCode = {
  INVALID_AUTH: 401,
  NOT_FOUND: 404,
  PERMISSION_DENIED: 403,
  VALIDATION_ERROR: 422,
  SERVER_ERROR: 500,
} as const;

// Domain-specific error types
export const ErrorType = {
  AUTH: 'auth_error',
  NOT_FOUND: 'not_found',
  PERMISSION: 'permission_error',
  VALIDATION: 'validation_error',
  SERVER: 'server_error',
} as const;

// Extended error schema with domain specifics
export const domainErrorSchema = apiErrorResponseSchema.extend({
  type: z.enum([
    ErrorType.AUTH,
    ErrorType.NOT_FOUND,
    ErrorType.PERMISSION,
    ErrorType.VALIDATION,
    ErrorType.SERVER,
  ]),
  code: z.nativeEnum(ErrorCode),
  field: z.string().optional(),
});

export type DomainError = z.infer<typeof domainErrorSchema>;
