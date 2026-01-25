// src/schemas/errors/utils.ts

import { errorGuards } from './guards';

export function extractErrorDetails(error: unknown) {
  return {
    message: extractMessage(error),
    code: extractCode(error),
  };
}

function extractMessage(error: unknown): string {
  if (errorGuards.isHttpError(error)) {
    return error.response?.data?.message || error.message || 'HTTP Error';
  }
  return error instanceof Error ? error.message : String(error);
}

function extractCode(error: unknown): string | number | null {
  if (errorGuards.isHttpError(error)) {
    return error.status || error.response?.status || 'ERR_HTTP';
  }
  return 'ERR_UNKNOWN';
}
