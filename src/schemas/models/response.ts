import { z } from 'zod';

/**
 * Single Record Response Schema
 * Matches API response format: { success: true, record: T, details: D }
 */
export const createResponseSchema = <T extends z.ZodTypeAny, D extends z.ZodTypeAny>(
  recordSchema: T,
  detailsSchema: D
) =>
  z.object({
    success: z.boolean(),
    record: recordSchema,
    details: detailsSchema,
  });

/**
 * List Response Schema
 * Matches API response format for collections
 */
export const createListResponseSchema = <T extends z.ZodTypeAny>(recordSchema: T) =>
  z.object({
    success: z.boolean(),
    records: z.array(recordSchema),
  });

// Type helpers
export type SingleResponse<T, D> = z.infer<ReturnType<typeof createResponseSchema<z.ZodType<T>, z.ZodType<D>>>>;
export type ListResponse<T> = z.infer<ReturnType<typeof createListResponseSchema<z.ZodType<T>>>>;
