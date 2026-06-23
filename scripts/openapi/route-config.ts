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
 * Error shapes vary across API versions, so no single field is universally
 * present — `required` is intentionally omitted to avoid rejecting valid
 * responses:
 *   V1 (frozen):  FormError#to_h → { error, message, field } (message is the text)
 *   V2+ (ADR-013): typed handlers → { error, error_type, request_id, ... }
 *                  (error is the user-facing text; no `message`)
 * See ADR-013 (API 4xx/5xx Error Response Wire Format).
 */
const errorContent = {
  'application/json': {
    schema: {
      type: 'object',
      properties: {
        error: { type: 'string', description: 'ADR-013: user-facing message (V2+). On frozen V1 this is the error type identifier.' },
        error_type: { type: 'string', description: 'Machine-readable error class the client branches on (ADR-013, e.g., "RecordNotFound")' },
        message: { type: 'string', description: 'Human-readable error message (legacy/V1 shape)' },
        field: { type: 'string', description: 'Field that caused the error, if applicable' },
        error_id: { type: 'string', description: 'Unique error tracking identifier' },
        request_id: { type: 'string', description: 'Request correlation id; mirrors the x-request-id response header and appears in the server request log. Quote this when reporting an error.' },
      },
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
