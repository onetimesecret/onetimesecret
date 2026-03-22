// src/schemas/shapes/v2/base.ts

/**
 * V2 API base model schemas and factory functions.
 *
 * These schemas handle V2 API wire format where timestamps and other
 * values are encoded as strings (Redis serialization format). The
 * transforms convert these strings to proper TypeScript types.
 *
 * @module shapes/v2/base
 * @category Shapes
 * @see {@link transforms} - String-to-type conversion utilities
 */

import { transforms } from '@/schemas/transforms';
import { z } from 'zod';

/**
 * Base model schema for V2 API records.
 *
 * Maps to Ruby's base model class and defines common model attributes.
 * V2 API sends timestamps as string-encoded Unix timestamps which are
 * transformed to Date objects.
 *
 * Design Decisions:
 *
 * 1. Common Fields:
 *    All models share:
 *    - identifier: unique ID
 *    - created/updated: timestamps
 *    These match Ruby model conventions
 *
 * 2. Model Creation Pattern:
 *    - createModelSchema helper enforces consistent model structure
 *    - Ensures all models extend base fields
 *    - Maintains type safety with Ruby models
 *
 * 3. Type Conversion:
 *    - Handles Redis string -> proper type conversion
 *    - Uses consistent transform patterns
 *    - Maintains type safety across boundaries
 *
 * @category Shapes
 *
 * @example
 * ```typescript
 * // Parse V2 API response with string timestamps
 * const record = baseModelSchema.parse({
 *   identifier: 'abc123',
 *   created: '1609459200',  // String Unix timestamp
 *   updated: '1609545600',
 * });
 *
 * console.log(record.created instanceof Date);  // true
 * console.log(record.created.toISOString());    // "2021-01-01T00:00:00.000Z"
 *
 * type BaseModel = z.infer<typeof baseModelSchema>;
 * ```
 */
export const baseModelSchema = z.object({
  identifier: z.string(),
  created: transforms.fromString.date,
  updated: transforms.fromString.date,
});

/** TypeScript type for base model fields. */
export type BaseModel = z.infer<typeof baseModelSchema>;

/**
 * Factory function to create V2 model schemas extending the base.
 *
 * Takes a ZodRawShape following Zod's builder pattern conventions.
 * All created schemas automatically include identifier, created, and
 * updated fields with appropriate V2 string transforms.
 *
 * @typeParam T - Shape of additional fields to add to the base model
 * @param fields - Zod field definitions to extend the base model with
 * @returns A Zod object schema with base model fields plus custom fields
 *
 * @category Shapes
 *
 * @example
 * ```typescript
 * // Create a user schema with base model fields
 * export const userSchema = createModelSchema({
 *   name: z.string(),
 *   email: z.email(),
 *   role: z.enum(['admin', 'user']),
 * });
 *
 * // Parse API response
 * const user = userSchema.parse({
 *   identifier: 'user123',
 *   created: '1609459200',
 *   updated: '1609459200',
 *   name: 'Alice',
 *   email: 'alice@example.com',
 *   role: 'admin',
 * });
 *
 * // Derive TypeScript type
 * type User = z.infer<typeof userSchema>;
 * // { identifier: string; created: Date; updated: Date; name: string; email: string; role: 'admin' | 'user' }
 * ```
 */
export const createModelSchema = <T extends z.ZodRawShape>(fields: T) =>
  baseModelSchema.extend(fields);
