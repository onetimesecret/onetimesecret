// scripts/openapi/route-config.ts

// =============================================================================
// Types
// =============================================================================

export interface SpecTarget {
  id: string;
  filename: string;
  title: string;
  description: string;
  apiNames: string[];
  frozen?: boolean;
}


// =============================================================================
// Error Responses
// =============================================================================

/**
 * Shared error response content schema.
 *
 * Matches the server's actual error shape across all API versions:
 *   V1:  FormError#to_h  → { error, message, field }
 *   V2+: error rescue    → { error, message, error_id }
 *
 * Only `message` is required — other fields are version/context dependent.
 */
const errorContent = {
  'application/json': {
    schema: {
      type: 'object',
      properties: {
        error: { type: 'string', description: 'Error type identifier (e.g., "FormError")' },
        message: { type: 'string', description: 'Human-readable error message' },
        field: { type: 'string', description: 'Field that caused the error, if applicable' },
        error_id: { type: 'string', description: 'Unique error tracking identifier' },
      },
      required: ['message'],
    },
  },
};

/**
 * Standardized error responses for reuse across all APIs.
 * Each includes a content schema matching the server's error envelope.
 */
export const standardErrorResponses = {
  400: {
    description: 'Bad Request - Invalid request parameters or body',
    content: errorContent,
  },
  401: {
    description: 'Unauthorized - Authentication required',
    content: errorContent,
  },
  403: {
    description: 'Forbidden - Insufficient permissions',
    content: errorContent,
  },
  404: {
    description: 'Not Found - Resource does not exist',
    content: errorContent,
  },
  422: {
    description: 'Unprocessable Entity - Validation failed',
    content: errorContent,
  },
  429: {
    description: 'Too Many Requests - Rate limit exceeded',
    content: errorContent,
  },
  500: {
    description: 'Internal Server Error - Something went wrong',
    content: errorContent,
  },
};

/**
 * Helper to merge custom responses with standard errors
 */
export function mergeResponses(
  customResponses: Record<string, { description: string }>,
  includeErrors: (keyof typeof standardErrorResponses)[] = [400, 401, 500]
): Record<string, { description: string }> {
  const errorResponses = Object.fromEntries(
    includeErrors.map(code => [code, standardErrorResponses[code]])
  );

  return {
    ...errorResponses,
    ...customResponses
  };
}
