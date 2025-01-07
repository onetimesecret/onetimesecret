// src/schemas/errors/constants.ts

export const ERROR_TYPES = ['technical', 'security', 'human'] as const;
export const ERROR_SEVERITIES = ['error', 'warning', 'info'] as const;

export const HTTP_STATUS_CODES = {
  SECURITY: new Set([
    401, // Unauthorized
    403, // Forbidden
    429, // Too Many Requests
    407, // Proxy Authentication Required
    423, // Locked
  ]),

  HUMAN: new Set([
    404, // Not Found
    409, // Conflict
    400, // Bad Request
    405, // Method Not Allowed
    410, // Gone
    422, // Unprocessable Entity
  ]),

  TECHNICAL: new Set([
    500, // Internal Server Error
    502, // Bad Gateway
    503, // Service Unavailable
    504, // Gateway Timeout
  ]),
};
