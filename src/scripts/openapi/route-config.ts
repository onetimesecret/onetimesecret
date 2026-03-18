// src/scripts/openapi/route-config.ts

// =============================================================================
// Spec Targets
// =============================================================================

export interface SpecTarget {
  id: string;
  filename: string;
  title: string;
  description: string;
  apiNames: string[];
  frozen?: boolean;
}

export const SPEC_TARGETS: SpecTarget[] = [
  {
    id: 'v1',
    filename: 'openapi.v1.json',
    title: 'API v1 (Legacy)',
    description:
      'Our legacy REST API, which is now frozen and in maintenance mode. Originally designed in the 2010s, requests are form encoded and responses are JSON with a simple, flat structure. Not recommended for new integrations. Receives only critical bug fixes and security patches.',
    apiNames: ['v1'],
    frozen: true,
  },
  {
    id: 'v2',
    filename: 'openapi.v2.json',
    title: 'API v2',
    description:
      'Our current stable API. JSON-based, with improved consistency and new endpoints compared to v1. Actively maintained and recommended for production use. Receives new features and updates, but breaking changes are avoided or properly deprecated.',
    apiNames: ['v2'],
  },
  {
    id: 'v3',
    filename: 'openapi.v3.json',
    title: 'API v3 (alpha)',
    description:
      'Our next-generation, work-in-progress API. Similar to v2 with JSON types and new endpoints, but still evolving. Although we use the v3 API to power our UI, it is not recommended for production use externally until we reach stable status. Subject to change without deprecation.',
    apiNames: ['v3'],
  },
  {
    id: 'internal',
    filename: 'openapi.internal.json',
    title: 'Internal API',
    description: 'Internal API consumed by the Vue frontend',
    apiNames: ['account', 'colonel', 'domains', 'organizations', 'invite'],
  },
];

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
