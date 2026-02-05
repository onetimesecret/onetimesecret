// src/schemas/utils/identifiers.ts

/**
 * Zod schemas for identifier validation at API boundaries
 *
 * These schemas validate and brand raw strings as ObjId or ExtId types,
 * ensuring type safety when parsing API responses.
 *
 * @see src/types/identifiers.ts for branded types and utility functions
 */

import { z } from 'zod';

// Note: We define local versions of these functions to avoid circular dependency
// with @/types/identifiers which re-exports from this file.

/**
 * ExtId format patterns by entity type (duplicated from types for independence)
 */
const EXTID_PREFIXES = {
  organization: 'on',
  domain: 'cd',
  customer: 'ur',
  secret: 'se',
  metadata: 'md',
} as const;

/**
 * Check if a string looks like a valid ExtId
 */
function looksLikeExtId(value: string): boolean {
  if (!value || typeof value !== 'string') return false;
  const prefixes = Object.values(EXTID_PREFIXES);
  return prefixes.some((prefix) => value.startsWith(prefix) && value.length > prefix.length);
}

// Branded type symbols (must match types/identifiers.ts)
declare const ObjIdBrand: unique symbol;
declare const ExtIdBrand: unique symbol;

type ObjId = string & { readonly [ObjIdBrand]: never };
type ExtId = string & { readonly [ExtIdBrand]: never };

function toObjId(raw: string): ObjId {
  return raw as ObjId;
}

function toExtId(raw: string): ExtId {
  return raw as ExtId;
}

// =============================================================================
// Zod Schemas for API Boundaries
// =============================================================================

/**
 * Strict ObjId schema - validates format and brands output
 *
 * Use when you need to ensure the ID is actually an internal ID format.
 * Fails on strings that look like ExtIds.
 */
export const objIdSchema = z
  .string()
  .refine((val) => !looksLikeExtId(val), {
    message: 'Expected internal ID format, got external ID',
  })
  .transform((val) => toObjId(val));

/**
 * Strict ExtId schema - validates format and brands output
 *
 * Use when you need to ensure the ID is actually an external ID format.
 * Fails on strings that look like internal UUIDs.
 */
export const extIdSchema = z
  .string()
  .refine((val) => looksLikeExtId(val), {
    message: 'Expected external ID format (e.g., on8a7b9c)',
  })
  .transform((val) => toExtId(val));

/**
 * Lenient ObjId schema - accepts any string, brands output
 *
 * Use during migration phase when strict validation would break existing code.
 * Accepts any string but outputs branded ObjId type.
 *
 * @migration Phase 1 - will be replaced with strict schema in Phase 3
 */
export const lenientObjIdSchema = z.string().transform((val) => toObjId(val));

/**
 * Lenient ExtId schema - accepts any string, brands output
 *
 * Use during migration phase when strict validation would break existing code.
 * Accepts any string but outputs branded ExtId type.
 *
 * @migration Phase 1 - will be replaced with strict schema in Phase 3
 */
export const lenientExtIdSchema = z.string().transform((val) => toExtId(val));

// =============================================================================
// Type Inference Helpers
// =============================================================================

/**
 * Inferred types from Zod schemas
 */
export type ZodObjId = z.infer<typeof objIdSchema>;
export type ZodExtId = z.infer<typeof extIdSchema>;
export type ZodLenientObjId = z.infer<typeof lenientObjIdSchema>;
export type ZodLenientExtId = z.infer<typeof lenientExtIdSchema>;
