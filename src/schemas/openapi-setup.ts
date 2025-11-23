// src/schemas/openapi-setup.ts

/**
 * OpenAPI Setup for Zod Schemas
 *
 * This file extends Zod with OpenAPI support and re-exports it.
 * All schema files should import { z } from this file instead of directly from 'zod'.
 *
 * Usage in schema files:
 *   // Before:
 *   import { z } from 'zod';
 *
 *   // After:
 *   import { z } from '@/schemas/openapi-setup';
 *
 * Benefits:
 * - All schemas automatically get .openapi() method
 * - Can add OpenAPI metadata incrementally
 * - Enables automatic OpenAPI document generation
 * - No breaking changes to existing schemas
 *
 * Migration Strategy:
 * 1. Schemas work immediately without .openapi() metadata
 * 2. Add metadata incrementally for better documentation
 * 3. OpenAPI generator works with or without metadata
 */

import { extendZodWithOpenApi } from '@asteasolutions/zod-to-openapi';
import { z as zodOriginal } from 'zod';

// Extend Zod with OpenAPI capabilities
extendZodWithOpenApi(zodOriginal);

// Re-export extended Zod
export const z = zodOriginal;

// Re-export common Zod types for convenience
export type {
  ZodType,
  ZodTypeAny,
  ZodObject,
  ZodString,
  ZodNumber,
  ZodBoolean,
  ZodArray,
  ZodEnum,
  ZodUnion,
  ZodLiteral,
  ZodNullable,
  ZodOptional,
} from 'zod';

/**
 * Type Inference Usage:
 * For type inference from Zod schemas, use the built-in z.infer utility:
 *
 * Example:
 *   const userSchema = z.object({ name: z.string() });
 *   type User = z.infer<typeof userSchema>;
 */
