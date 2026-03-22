// src/schemas/transforms.ts

import { ttlToNaturalLanguage } from '@/utils/format/index';
import { parseBoolean, parseDateValue, parseNumber, parseNestedObject } from '@/utils/parse/index';
import { z } from 'zod';

/**
 * Core string transformers for API/Redis data conversion.
 *
 * These transforms handle the conversion of wire-format data (strings from APIs/Redis)
 * into typed domain values (Date, number, boolean) for use in Vue components and Pinia stores.
 *
 * Uses z.preprocess() over z.coerce() because:
 *
 * 1. Explicit handling of null/undefined/empty strings
 * 2. Support for Redis bool formats ("0"/"1", "true"/"false")
 * 3. Unix timestamp string conversion to JS dates
 *
 * Space characters (spaces, tabs, newlines) are handled in UI components:
 * - Preserves data fidelity
 * - Keeps schema validation separate from display formatting
 * - Allows field-specific space handling
 *
 * Note: This level of detail is standard practice for large apps.
 * It centralizes conversions, handles edge cases, and ensures
 * consistency across the codebase.
 *
 * @category Transforms
 * @see {@link parseBoolean} - Boolean parsing utility
 * @see {@link parseDateValue} - Date parsing utility
 * @see {@link parseNumber} - Number parsing utility
 *
 * @example
 * ```typescript
 * import { transforms } from '@/schemas/transforms';
 * import { z } from 'zod';
 *
 * // Use in a schema definition
 * const mySchema = z.object({
 *   created: transforms.fromString.date,
 *   count: transforms.fromString.number,
 *   isActive: transforms.fromString.boolean,
 * });
 *
 * // Parse API response
 * const data = mySchema.parse({
 *   created: "1609459200",  // Unix timestamp string
 *   count: "42",
 *   isActive: "true",
 * });
 * // Result: { created: Date, count: 42, isActive: true }
 * ```
 */

export const transforms = {
  /**
   * Transforms for converting string-encoded values from V2 API responses.
   *
   * V2 API returns most values as strings (timestamps, numbers, booleans).
   * These transforms use z.preprocess() to convert before validation.
   *
   * @category Transforms
   */
  fromString: {
    /**
     * Parses string timestamps to Date, allowing null.
     *
     * Handles Unix timestamps (seconds or milliseconds) and ISO date strings.
     * Returns null for empty strings, null, or undefined input.
     *
     * @example
     * ```typescript
     * const schema = z.object({ updated: transforms.fromString.dateNullable });
     * schema.parse({ updated: "1609459200" });  // { updated: Date }
     * schema.parse({ updated: "" });            // { updated: null }
     * schema.parse({ updated: null });          // { updated: null }
     * ```
     */
    dateNullable: z.preprocess(parseDateValue, z.date().nullable()),

    /**
     * Parses string timestamps to Date, requiring a valid date.
     *
     * Handles Unix timestamps (seconds or milliseconds) and ISO date strings.
     * Throws ZodError if the value cannot be parsed to a valid Date.
     *
     * @example
     * ```typescript
     * const schema = z.object({ created: transforms.fromString.date });
     * schema.parse({ created: "1609459200" });           // { created: Date }
     * schema.parse({ created: "2021-01-01T00:00:00Z" }); // { created: Date }
     * schema.parse({ created: "" });                     // throws ZodError
     * ```
     */
    date: z.preprocess(
      parseDateValue,
      z.date().refine((val): val is Date => val !== null, 'Valid date is required')
    ),

    /**
     * Parses string numbers to number, allowing null.
     *
     * Returns null for empty strings, null, undefined, or NaN results.
     *
     * @example
     * ```typescript
     * const schema = z.object({ count: transforms.fromString.number });
     * schema.parse({ count: "42" });    // { count: 42 }
     * schema.parse({ count: "3.14" });  // { count: 3.14 }
     * schema.parse({ count: "" });      // { count: null }
     * schema.parse({ count: "abc" });   // { count: null }
     * ```
     */
    number: z.preprocess(parseNumber, z.number().nullable()),

    /**
     * Parses string booleans from Redis/API formats.
     *
     * Truthy: "true", "1"
     * Falsy: "false", "0", "", null, undefined
     *
     * @example
     * ```typescript
     * const schema = z.object({ active: transforms.fromString.boolean });
     * schema.parse({ active: "true" });  // { active: true }
     * schema.parse({ active: "1" });     // { active: true }
     * schema.parse({ active: "false" }); // { active: false }
     * schema.parse({ active: "0" });     // { active: false }
     * schema.parse({ active: "" });      // { active: false }
     * ```
     */
    boolean: z.preprocess(parseBoolean, z.boolean()),

    /**
     * Converts TTL seconds to human-readable duration string.
     *
     * Input is TTL in seconds; output is formatted like "2 hours from now".
     * Preserves pre-formatted strings that contain non-numeric characters.
     *
     * @example
     * ```typescript
     * const schema = z.object({ expiresIn: transforms.fromString.ttlToNaturalLanguage });
     * schema.parse({ expiresIn: 3600 });   // { expiresIn: "1 hour from now" }
     * schema.parse({ expiresIn: 86400 });  // { expiresIn: "1 day from now" }
     * schema.parse({ expiresIn: -1 });     // { expiresIn: null }
     * ```
     */
    ttlToNaturalLanguage: z.preprocess(ttlToNaturalLanguage, z.string().nullable()),

    /**
     * Transforms empty strings to undefined for optional email fields.
     *
     * Useful for form inputs where an empty string should mean "no email"
     * rather than failing email validation.
     *
     * @example
     * ```typescript
     * const schema = z.object({ email: transforms.fromString.optionalEmail });
     * schema.parse({ email: "test@example.com" }); // { email: "test@example.com" }
     * schema.parse({ email: "" });                 // { email: undefined }
     * schema.parse({ email: "invalid" });          // throws ZodError
     * ```
     */
    optionalEmail: z.preprocess((val) => (val === '' ? undefined : val), z.email().optional()),
  },

  /**
   * Transforms for converting numeric values from V3 API responses.
   *
   * V3 API returns timestamps as Unix epoch numbers (seconds since 1970).
   * These transforms use z.transform() to preserve type information for
   * JSON Schema generation while still converting to Date objects.
   *
   * @category Transforms
   * @see {@link transforms.fromString} - For V2 API string-encoded timestamps
   */
  fromNumber: {
    /**
     * Converts Unix timestamp (seconds) to Date using preprocess.
     *
     * @deprecated Prefer `toDate` which uses transform() for better JSON Schema support.
     *
     * @example
     * ```typescript
     * const schema = z.object({ ts: transforms.fromNumber.secondsToDate });
     * schema.parse({ ts: 1609459200 }); // { ts: Date(2021-01-01) }
     * ```
     */
    secondsToDate: z.preprocess((val) => new Date((val as number) * 1000), z.date()),

    /**
     * Converts Unix timestamp (seconds) to Date, requiring a valid number.
     *
     * V3 API timestamp transform (Wire to Domain):
     * - Wire: z.number() validates input (Unix epoch seconds)
     * - Domain: .transform() coerces to Date for Pinia stores and components
     * - Docs: io:"input" makes JSON Schema document "number", not Date
     *
     * Uses .transform() instead of .preprocess() so that z.toJSONSchema()
     * with io:"input" sees the typed input (number), not unknown.
     *
     * @example
     * ```typescript
     * const schema = z.object({ created: transforms.fromNumber.toDate });
     * schema.parse({ created: 1609459200 }); // { created: Date(2021-01-01) }
     *
     * type Created = z.infer<typeof schema>; // { created: Date }
     * ```
     */
    toDate: z.number().transform((v) => new Date(v * 1000)),

    /**
     * Converts Unix timestamp to Date, allowing null.
     *
     * @example
     * ```typescript
     * const schema = z.object({ updated: transforms.fromNumber.toDateNullable });
     * schema.parse({ updated: 1609459200 }); // { updated: Date }
     * schema.parse({ updated: null });       // { updated: null }
     *
     * type Updated = z.infer<typeof schema>; // { updated: Date | null }
     * ```
     */
    toDateNullable: z
      .number()
      .nullable()
      .transform((v) => (v === null ? null : new Date(v * 1000))),

    /**
     * Converts Unix timestamp to Date, allowing undefined.
     *
     * @example
     * ```typescript
     * const schema = z.object({ deleted: transforms.fromNumber.toDateOptional });
     * schema.parse({ deleted: 1609459200 }); // { deleted: Date }
     * schema.parse({ deleted: undefined });  // { deleted: undefined }
     * schema.parse({});                      // { deleted: undefined }
     *
     * type Deleted = z.infer<typeof schema>; // { deleted?: Date | undefined }
     * ```
     */
    toDateOptional: z
      .number()
      .optional()
      .transform((v) => (v === undefined ? undefined : new Date(v * 1000))),

    /**
     * Converts Unix timestamp to Date, accepting null or undefined.
     *
     * Collapses undefined to null so consumers get a simpler union (Date | null)
     * instead of (Date | null | undefined).
     *
     * @example
     * ```typescript
     * const schema = z.object({ viewed: transforms.fromNumber.toDateNullish });
     * schema.parse({ viewed: 1609459200 }); // { viewed: Date }
     * schema.parse({ viewed: null });       // { viewed: null }
     * schema.parse({ viewed: undefined });  // { viewed: null }
     *
     * type Viewed = z.infer<typeof schema>; // { viewed: Date | null }
     * ```
     */
    toDateNullish: z
      .number()
      .nullish()
      .transform((v) => (v == null ? null : new Date(v * 1000))),
  },

  /**
   * Transforms for handling nested object structures in API responses.
   *
   * @category Transforms
   */
  fromObject: {
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
  },
} as const;
