import { z } from 'zod';
import { ERROR_SEVERITIES, ERROR_TYPES } from './constants';

/**
 * Derives union types from const arrays using indexed access type [number].
 * This creates a single source of truth for both TypeScript types and Zod enums,
 * where the type becomes a union of all array element literals.
 *
 * Example: (typeof ['a', 'b'])[number] becomes 'a' | 'b'
 */
export type ErrorType = (typeof ERROR_TYPES)[number];
export type ErrorSeverity = (typeof ERROR_SEVERITIES)[number];

/**
 * Application error type definitions using interfaces rather than classes.
 * This approach aligns with Vue 3's composition API patterns and ecosystem by:
 * - Favoring plain objects and composable functions over classes
 * - Maintaining flexibility for API error responses
 * - Matching type patterns used by Vue tooling (Pinia, Router, etc)
 */
export interface ApplicationError extends Error {
  name: 'ApplicationError';
  type: ErrorType;
  severity: ErrorSeverity;
  code: string | number | null;
  original?: Error;
  details?: Record<string, unknown>;
}

export interface HttpErrorLike {
  status?: number;
  response?: {
    status?: number;
    data?: { message?: string };
  };
  message?: string;
}

/**
 * Zod schemas derived from const arrays
 */
export const errorTypeEnum = z.enum(ERROR_TYPES);
export const errorSeverityEnum = z.enum(ERROR_SEVERITIES);

export const applicationErrorSchema = z
  .object({
    name: z.literal('ApplicationError'),
    message: z.string(),
    type: errorTypeEnum,
    severity: errorSeverityEnum,
    code: z.union([z.string(), z.number()]).nullable().default(null),
    original: z.instanceof(Error).optional().nullable().default(null),
    details: z.record(z.unknown()).optional().default({}),
  })
  .strict();
