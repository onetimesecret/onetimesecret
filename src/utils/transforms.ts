import { z, ZodIssue } from 'zod';
import { fromZodError } from 'zod-validation-error';

/**
 * Base schema for all API records
 * Matches BaseApiRecord interface and handles identifier pattern
 *
 * Ruby models use different identifier patterns:
 * - Direct field (e.g. Customer.custid)
 * - Generated (e.g. Secret.generate_id)
 * - Derived (e.g. CustomDomain.derive_id)
 * - Composite (e.g. RateLimit.[fields].sha256)
 *
 * We standardize this in the schema layer by:
 * 1. Always including the identifier field from API
 * 2. Allowing models to specify their identifier source
 * 3. Transforming as needed in model-specific schemas
 */

/**
 * Common transform helpers for API -> App data conversion
 */
export const booleanFromString = z.preprocess((val) => {
  if (typeof val === 'boolean') return val;
  return val === 'true';
}, z.boolean());

export const numberFromString = z.preprocess((val) => {
  if (typeof val === 'number') return val;
  return Number(val);
}, z.number());

export const dateFromSeconds = z.preprocess((val) => {
  if (val instanceof Date) return val;
  if (typeof val !== 'string') throw new Error('Expected string timestamp');
  const timestamp = Number(val);
  if (isNaN(timestamp)) throw new Error('Invalid timestamp');
  return new Date(timestamp * 1000);
}, z.date());

/**
 * Input schema creators for API responses
 */
export const createInputSchema = <T extends z.ZodType>(recordSchema: T) =>
  z.object({
    success: z.boolean(),
    record: recordSchema,
    details: z.any().optional(),
  });

export const createListInputSchema = <T extends z.ZodType>(recordSchema: T) =>
  z.object({
    success: z.boolean(),
    custid: z.string(),
    records: z.array(recordSchema),
    count: z.number(),
    details: z.any().optional(),
  });

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
