import type {
  ApiRecordsResponse,
  BaseApiRecord,
  BaseApiResponse
} from '@/types/api/responses';
import { z } from 'zod';
import { fromZodError } from 'zod-validation-error';

// Match BaseApiRecord interface
export const baseApiRecordSchema = z.object({
  identifier: z.string(),
  created: z.string(),
  updated: z.string()
}) satisfies z.ZodType<BaseApiRecord>;

// Match BaseApiResponse interface
export const baseApiResponseSchema = z.object({
  success: z.boolean()
}) satisfies z.ZodType<BaseApiResponse>;

/**
 * Response wrapper schemas with flexible details handling
 */
export const apiRecordResponseSchema = <T extends z.ZodType<BaseApiRecord>>(recordSchema: T) =>
  baseApiResponseSchema.extend({
    record: recordSchema,
    details: z.any().optional()
  });

export const apiRecordsResponseSchema = <T extends z.ZodType<BaseApiRecord>>(recordSchema: T) =>
  baseApiResponseSchema.extend({
    custid: z.string(),
    records: z.array(recordSchema),
    count: z.number(),
    details: z.any().optional()
  });

/**
 * Common type coercion helpers
 */
export const booleanFromString = z.preprocess((val) => {
  if (typeof val === 'boolean') return val;
  return val === 'true';
}, z.boolean());

export const numberFromString = z.preprocess((val) => {
  if (typeof val === 'number') return val;
  return Number(val);
}, z.number());

/**
 * Custom error for transform/validation failures
 */
export class TransformError extends Error {
  details?: unknown;

  constructor(
    message: string,
    options?: {
      cause?: Error | undefined,
      details?: unknown
    }
  ) {
    super(message, { cause: options?.cause });
    this.name = 'TransformError';
    this.details = options?.details;
  }
}


// src/utils/transforms.ts
/**
 * Helper to detect if error is from transform validation
 * Used for better error handling in stores
 */
export function isTransformError(error: unknown): error is TransformError {
  return error instanceof TransformError && error.details !== undefined
}

/**
 * Transform single record API response
 * @throws TransformError if validation fails
 */
export function transformResponse<T extends z.ZodType>(
  schema: T,
  data: unknown
): z.infer<T> {
  try {
    return schema.parse(data)
  } catch (error) {
    throw new TransformError('Transform failed', {
      cause: error instanceof Error ? error : new Error(String(error)),
      details: error instanceof z.ZodError ? error.issues : undefined
    })
  }
}
/**
 * Transform and validate multi-record API response data.
 */
export function transformRecordsResponse<T extends z.ZodType<BaseApiRecord>>(
  schema: ReturnType<typeof apiRecordsResponseSchema<T>>,
  data: unknown
): ApiRecordsResponse<z.infer<T>> {
  try {
    const result = schema.safeParse(data);

    if (!result.success) {
      const validationError = fromZodError(result.error);
      throw new TransformError('Data validation failed', {
        cause: validationError,
        details: validationError.details
      });
    }

    return result.data as ApiRecordsResponse<z.infer<T>>;
  } catch (error) {
    if (error instanceof TransformError) {
      throw error;
    }
    throw new TransformError('Transform failed', {
      cause: error instanceof Error ? error : new Error(String(error))
    });
  }
}
