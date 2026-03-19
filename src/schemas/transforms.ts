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

  fromNumber: {
    secondsToDate: z.preprocess((val) => new Date((val as number) * 1000), z.date()),

    /**
     * V3 API timestamp transforms (Wire → Domain):
     *   Wire:   z.number()           validates input (Unix epoch seconds)
     *   Domain: .transform(→ Date)   coerces for Pinia stores & components
     *   Docs:   io:"input"           JSON Schema documents "number", not Date
     *
     * Uses .transform() instead of .preprocess() so that z.toJSONSchema()
     * with io:"input" sees the typed input (number), not unknown.
     *
     * V2 schemas should continue using transforms.fromString.date which
     * handles string-encoded timestamps from the V2 API.
     *
     * Note: V2/V3 refer to Onetime Secret API versions, not Zod versions.
     */
    toDate: z.number().transform((v) => new Date(v * 1000)),
    toDateNullable: z
      .number()
      .nullable()
      .transform((v) => (v === null ? null : new Date(v * 1000))),
    toDateOptional: z
      .number()
      .optional()
      .transform((v) => (v === undefined ? undefined : new Date(v * 1000))),
    /** Accepts number, null, or undefined; normalizes to Date | null.
     *  Collapses undefined → null so consumers get a simpler union. */
    toDateNullish: z
      .number()
      .nullish()
      .transform((v) => (v == null ? null : new Date(v * 1000))),
  },

  fromObject: {
    /**
     * Transforms API nested objects using consistent preprocessing pattern
     */
    nested: <T extends z.ZodType>(schema: T) => z.preprocess(parseNestedObject, schema),
  },
} as const;
