// src/schemas/transforms/from-string.ts

import { ttlToNaturalLanguage } from '@/utils/format/index';
import { parseDateValue } from '@/utils/parse/index';
import { z } from 'zod';

/**
 * Transforms for converting string-encoded values from V2 API responses.
 *
 * V2 API returns most values as strings (timestamps, numbers, booleans).
 * These transforms use z.string().transform() to convert after type validation.
 *
 * @category Transforms
 */
export const fromString = {
  /**
   * Parses string timestamps to Date, allowing null.
   *
   * Handles Unix timestamps (seconds or milliseconds) and ISO date strings.
   * Returns null for empty strings or null input.
   *
   * Uses transform() instead of preprocess() so that z.toJSONSchema() with
   * io:"input" correctly reports the wire type (string) rather than unknown.
   *
   * @example
   * ```typescript
   * const schema = z.object({ updated: transforms.fromString.dateNullable });
   * schema.parse({ updated: "1609459200" });  // { updated: Date }
   * schema.parse({ updated: "" });            // { updated: null }
   * schema.parse({ updated: null });          // { updated: null }
   * ```
   */
  dateNullable: z
    .string()
    .nullable()
    .transform((val): Date | null => {
      if (val === null || val === '') return null;
      return parseDateValue(val) as Date | null;
    }),

  /**
   * Parses string timestamps to Date, requiring a valid date.
   *
   * Handles Unix timestamps (seconds or milliseconds) and ISO date strings.
   * Throws ZodError if the value cannot be parsed to a valid Date.
   *
   * Uses transform() instead of preprocess() so that z.toJSONSchema() with
   * io:"input" correctly reports the wire type (string) rather than unknown.
   *
   * @example
   * ```typescript
   * const schema = z.object({ created: transforms.fromString.date });
   * schema.parse({ created: "1609459200" });           // { created: Date }
   * schema.parse({ created: "2021-01-01T00:00:00Z" }); // { created: Date }
   * schema.parse({ created: "" });                     // throws ZodError
   * ```
   */
  date: z
    .string()
    .transform((val): Date => {
      const date = parseDateValue(val);
      if (!date) throw new Error('Valid date is required');
      return date;
    }),

  /**
   * Parses string numbers to number, allowing null.
   *
   * Returns null for empty strings or unparseable values.
   *
   * Uses transform() instead of preprocess() so that z.toJSONSchema() with
   * io:"input" correctly reports the wire type (string) rather than unknown.
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
  number: z
    .string()
    .nullable()
    .transform((val): number | null => {
      if (val === null || val === '') return null;
      const num = Number(val);
      return isNaN(num) ? null : num;
    }),

  /**
   * Parses string booleans from Redis/API formats.
   *
   * Truthy: "true", "1"
   * Falsy: "false", "0", "", null, undefined
   *
   * Uses transform() instead of preprocess() so that z.toJSONSchema() with
   * io:"input" correctly reports the wire type (string) rather than unknown.
   *
   * @example
   * ```typescript
   * const schema = z.object({ active: transforms.fromString.boolean });
   * schema.parse({ active: "true" });  // { active: true }
   * schema.parse({ active: "1" });     // { active: true }
   * schema.parse({ active: "false" }); // { active: false }
   * schema.parse({ active: "0" });     // { active: false }
   * schema.parse({ active: "" });      // { active: false }
   * schema.parse({ active: null });    // { active: false }
   * schema.parse({ active: undefined });// { active: false }
   * ```
   */
  boolean: z
    .string()
    .nullish()
    .transform((val): boolean => val === 'true' || val === '1'),

  /**
   * Converts TTL seconds to human-readable duration string.
   *
   * Input is TTL in seconds as a string; output is formatted like "2 hours from now".
   * Returns null for empty strings or invalid values.
   *
   * Uses transform() instead of preprocess() so that z.toJSONSchema() with
   * io:"input" correctly reports the wire type (string) rather than unknown.
   *
   * @example
   * ```typescript
   * const schema = z.object({ expiresIn: transforms.fromString.ttlToNaturalLanguage });
   * schema.parse({ expiresIn: "3600" });   // { expiresIn: "1 hour from now" }
   * schema.parse({ expiresIn: "86400" });  // { expiresIn: "1 day from now" }
   * schema.parse({ expiresIn: "-1" });     // { expiresIn: null }
   * ```
   */
  ttlToNaturalLanguage: z
    .string()
    .nullable()
    .transform((val): string | null => {
      if (val === null || val === '') return null;
      return ttlToNaturalLanguage(val);
    }),

  /**
   * Transforms empty strings to undefined for optional email fields.
   *
   * Useful for form inputs where an empty string should mean "no email"
   * rather than failing email validation.
   *
   * Uses transform() instead of preprocess() so that z.toJSONSchema() with
   * io:"input" correctly reports the wire type (string) rather than unknown.
   *
   * @example
   * ```typescript
   * const schema = z.object({ email: transforms.fromString.optionalEmail });
   * schema.parse({ email: "test@example.com" }); // { email: "test@example.com" }
   * schema.parse({ email: "" });                 // { email: undefined }
   * schema.parse({ email: "invalid" });          // validates as email
   * ```
   */
  optionalEmail: z
    .string()
    .optional()
    .transform((val) => (val === '' ? undefined : val))
    .pipe(z.email().optional()),
} as const;
