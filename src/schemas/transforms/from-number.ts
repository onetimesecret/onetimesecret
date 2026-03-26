// src/schemas/transforms/from-number.ts

import { z } from 'zod';

/**
 * Transforms for converting numeric values from V3 API responses.
 *
 * V3 API returns timestamps as Unix epoch numbers (seconds since 1970).
 * These transforms use z.transform() to preserve type information for
 * JSON Schema generation while still converting to Date objects.
 *
 * @category Transforms
 * @see {@link fromString} - For V2 API string-encoded timestamps
 */
export const fromNumber = {
  /**
   * Converts Unix timestamp (seconds) to Date.
   *
   * Uses transform() so that z.toJSONSchema() with io:"input" correctly
   * reports the wire type (number) rather than unknown.
   *
   * @example
   * ```typescript
   * const schema = z.object({ ts: transforms.fromNumber.secondsToDate });
   * schema.parse({ ts: 1609459200 }); // { ts: Date(2021-01-01) }
   * ```
   */
  secondsToDate: z.number().transform((val) => new Date(val * 1000)),

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
} as const;
