// src/scripts/openapi/route-config.ts

/**
 * Standardized error responses for reuse across all APIs
 */
export const standardErrorResponses = {
  400: {
    description: 'Bad Request - Invalid request parameters or body'
  },
  401: {
    description: 'Unauthorized - Authentication required'
  },
  403: {
    description: 'Forbidden - Insufficient permissions'
  },
  404: {
    description: 'Not Found - Resource does not exist'
  },
  429: {
    description: 'Too Many Requests - Rate limit exceeded'
  },
  500: {
    description: 'Internal Server Error - Something went wrong'
  }
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
