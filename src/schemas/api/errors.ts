// src/schemas/api/errors.ts

import { z } from 'zod';

import { apiErrorResponseSchema } from './base';

/**
* try {
  const data = secretSchema.parse(input);
  return data;
} catch (error) {
  if (error instanceof z.ZodError) {
    throw zodErrorToApiError(error);
  }

  // Handle other errors
  throw createApiError(
    'SERVER',
    'SERVER_ERROR',
    'An unexpected error occurred'
  );
}

// Example for auth errors
const handleAuth = () => {
  if (!authenticated) {
    throw createApiError(
      'AUTH',
      'INVALID_AUTH',
      'Invalid authentication credentials'
    );
  }
}

1. Consistent error structure across the API
2. Type-safe error creation
3. Proper mapping from Zod validation errors
4. Reusable error helpers

When using this in components/stores:

```typescript
try {
  await api.createSecret(data);
} catch (error) {
  if (isApiError(error)) { // Type guard we could add
    // We now have typed error info
    if (error.type === ErrorType.VALIDATION) {
      // Handle validation error
      console.log(`Field ${error.field} invalid: ${error.message}`);
    }
  }
}
```
*/
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

// Domain error schema
export const apiErrorSchema = apiErrorResponseSchema.extend({
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

export type ApiError = z.infer<typeof apiErrorSchema>;

// Helper to convert Zod errors to domain errors
export function isApiError(error: unknown): error is ApiError {
  return error !== null && typeof error === 'object' && 'type' in error && 'code' in error;
}

// Improve zod error handling to preserve context
export const zodErrorToApiError = (error: z.ZodError): ApiError => {
  const firstError = error.errors[0];
  return {
    success: false,
    type: ErrorType.VALIDATION,
    code: ErrorCode.VALIDATION_ERROR,
    message: firstError.message,
    field: firstError.path.join('.'),
    record: null,
    shrimp: '',
    details: {
      errors: error.errors.map((err) => ({
        path: err.path,
        message: err.message,
      })),
    },
  };
};

export const createApiError = (
  type: keyof typeof ErrorType,
  code: keyof typeof ErrorCode,
  message: string,
  field?: string
): ApiError => ({
  success: false,
  type: ErrorType[type],
  code: ErrorCode[code],
  message,
  field,
  record: null,
  shrimp: '', // Add required field
  details: {},
});
