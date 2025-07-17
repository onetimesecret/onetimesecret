// src/schemas/transforms.ts

import { ttlToNaturalLanguage } from '@/utils/format/index';
import { parseBoolean, parseDateValue, parseNumber, parseNestedObject } from '@/utils/parse/index';
import { z } from 'zod/v4';

/**
 * Core string transformers for API/Redis data conversion
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
 */

export const transforms = {
  fromString: {
    dateNullable: z.preprocess(parseDateValue, z.date().nullable()),
    date: z.preprocess(
      parseDateValue,
      z.date().refine((val) => val !== null, {
        message: 'Valid date is required',
      })
    ),
    number: z.preprocess(parseNumber, z.number().nullable()),
    boolean: z.preprocess(parseBoolean, z.boolean()),
    ttlToNaturalLanguage: z.preprocess(ttlToNaturalLanguage, z.string().nullable()),

    /**
     * Transforms empty strings to undefined for optional email fields
     * Input: "" -> undefined
     * Input: "test@example.com" -> "test@example.com"
     * Input: "invalid" -> ZodError
     */
    optionalEmail: z.preprocess((val) => (val === '' ? undefined : val), z.email().optional()),
  },

  fromNumber: {
    secondsToDate: z.preprocess((val) => new Date((val as number) * 1000), z.date()),
  },

  fromObject: {
    /**
     * Transforms API nested objects using consistent preprocessing pattern
     */
    nested: <T extends z.ZodType>(schema: T) => z.preprocess(parseNestedObject, schema),
  },
} as const;
