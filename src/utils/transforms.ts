import { z, ZodIssue } from 'zod';
import { fromZodError } from 'zod-validation-error';

/**
 * Core Transformers
 *
 * Centralized string conversion utilities for API boundaries. Data coming from
 * the API is often from Redis which stores everything as strings. These
 * transformers help convert those strings into proper types.
 *
 *
 * About Space Characters
 *
 * We handle space characters (spaces, tabs, newlines, etc.) at the component level
 * rather than in schemas because:
 *
 * 1. Data Fidelity
 *    - Preserves original input in the data model
 *    - Prevents unintended data loss from automatic trimming
 *    - Critical for secrets/sensitive content where spacing may be significant
 *
 * 2. Separation of Concerns
 *    - Schemas validate data structure and constraints
 *    - Components handle user input formatting and display
 *    - Makes space character handling explicit where needed
 *
 * 3. Flexibility
 *    - Different components may need different spacing handling
 *    - Some fields may need to preserve all space characters
 *    - UI can show original vs cleaned versions if needed
 *
 * For form inputs where space cleaning is desired, handle it in the component's
 * input event handler or v-model transformer.
 */
export const transforms = {
  fromString: {
    boolean: z.preprocess((val) => {
      if (typeof val === 'boolean') return val;
      return val === 'true' || val === '1';
    }, z.boolean()),

    number: z.preprocess((val) => {
      if (typeof val === 'number') return val;
      if (val === null || val === undefined || val === '') return null;
      const num = Number(val);
      return isNaN(num) ? null : num;
    }, z.number().nullable()),

    date: z.preprocess((val) => {
      if (val instanceof Date) return val;
      const timestamp = typeof val === 'string' ? parseInt(val, 10) : (val as number);
      if (isNaN(timestamp)) throw new Error('Invalid timestamp');
      return new Date(timestamp * 1000);
    }, z.date()),

    ttlToNaturalLanguage: z.preprocess((val: unknown) => {
      if (val === null || val === undefined) return null;

      const seconds: number = typeof val === 'string' ? parseInt(val, 10) : (val as number);
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

/**
 * Transform error handling
 */
export class TransformError extends Error {
  public details: ZodIssue[] | string;
  public data: unknown;

  constructor(message: string, details: ZodIssue[] | string, data?: unknown) {
    super(message);
    this.name = 'TransformError';
    this.details = details;
    this.data = data;
    Object.setPrototypeOf(this, TransformError.prototype); // Is this necessary in 2024?
  }
}

export function isTransformError(error: unknown): error is TransformError {
  return error instanceof TransformError;
}

/**
 * Main transform functions for API responses
 */
export function transformResponse<T>(schema: z.ZodSchema<T>, data: unknown): T {
  try {
    return schema.parse(data);
  } catch (error) {
    if (error instanceof z.ZodError) {
      console.debug('Schema:', schema);
      console.debug('Failed data:', data);
      console.debug('Validation issues:', error.issues);

      throw new TransformError('Validation failed', fromZodError(error).details);
    } else {
      console.error('Transform failed:', error);
    }

    return data as T;
  }
}
