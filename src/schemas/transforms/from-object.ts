// src/schemas/transforms/from-object.ts

import { parseNestedObject } from '@/utils/parse/index';
import { z } from 'zod';

/**
 * Transforms for handling nested object structures in API responses.
 *
 * @category Transforms
 */
export const fromObject = {
  /**
   * Preprocesses nested objects with fallback to empty object.
   *
   * Handles cases where API returns null/undefined for optional nested objects.
   * Ensures the schema always receives a valid object to parse.
   *
   * @typeParam T - The Zod schema type for the nested object
   * @param schema - The Zod schema to apply after preprocessing
   * @returns A preprocessed schema that handles null/undefined gracefully
   *
   * @example
   * ```typescript
   * const userSchema = z.object({
   *   name: z.string(),
   *   settings: transforms.fromObject.nested(
   *     z.object({
   *       theme: z.string().default('light'),
   *       notifications: z.boolean().default(true),
   *     })
   *   ),
   * });
   *
   * // Works with nested object
   * userSchema.parse({ name: 'Alice', settings: { theme: 'dark' } });
   *
   * // Falls back to empty object (defaults apply)
   * userSchema.parse({ name: 'Bob', settings: null });
   * // Result: { name: 'Bob', settings: { theme: 'light', notifications: true } }
   * ```
   */
  nested: <T extends z.ZodType>(schema: T) => z.preprocess(parseNestedObject, schema),
} as const;
