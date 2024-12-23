import { z } from 'zod';

// TODO: Find for isTransformError, replace with Zod's built-in error handling (if (error instanceof z.ZodError))

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
 */
export const transforms = {
  fromString: {
    boolean: z.preprocess((val) => {
      if (val === null || val === undefined || val === '') return false;
      if (typeof val === 'boolean') return val;
      return val === 'true' || val === '1';
    }, z.boolean()),

    number: z.preprocess((val) => {
      if (val === null || val === undefined || val === '') return null;
      if (typeof val === 'number') return val;
      const num = Number(val);
      return isNaN(num) ? null : num;
    }, z.number().nullable()),

    date: z.preprocess((val) => {
      if (val === null || val === undefined || val === '') return null;
      if (val instanceof Date) return val;

      const timestamp = typeof val === 'string' ? parseInt(val, 10) : (val as number);
      if (isNaN(timestamp)) {
        throw new z.ZodError([
          {
            code: z.ZodIssueCode.invalid_date,
            path: [],
            message: `Invalid timestamp value: "${val}" (type: ${typeof val})`,
          },
        ]);
      }
      return new Date(timestamp * 1000);
    }, z.date().nullable()),

    ttlToNaturalLanguage: z.preprocess((val: unknown) => {
      if (val === null || val === undefined) return null;

      const seconds: number =
        typeof val === 'string' ? parseInt(val, 10) : (val as number);
      if (isNaN(seconds) || seconds < 0) return null;

      const intervals = [
        { label: 'year', seconds: 31536000 },
        { label: 'month', seconds: 2592000 },
        { label: 'week', seconds: 604800 },
        { label: 'day', seconds: 86400 },
        { label: 'hour', seconds: 3600 },
        { label: 'minute', seconds: 60 },
        { label: 'second', seconds: 1 },
      ];

      for (const interval of intervals) {
        const count = Math.floor(seconds / interval.seconds);
        if (count >= 1) {
          return count === 1
            ? `1 ${interval.label} from now`
            : `${count} ${interval.label}s from now`;
        }
      }
      return 'a few seconds from now';
    }, z.string().nullable().optional()),
  },
} as const;
