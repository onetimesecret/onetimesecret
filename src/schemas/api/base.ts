import { transforms } from '@/utils/transforms';
import { z } from 'zod';

// Base schema that all API responses extend from
export const apiResponseBaseSchema = z.object({
  success: transforms.fromString.boolean,
  custid: z.string().optional(),
  shrimp: z.string().optional().default(''),
});

// Generic response wrapper for single record endpoints
export const createRecordResponseSchema = <T extends z.ZodTypeAny>(recordSchema: T) =>
  apiResponseBaseSchema.extend({
    record: recordSchema,
    details: z.record(z.string(), z.unknown()).optional(),
  });

// Generic response wrapper for list endpoints
export const createRecordsResponseSchema = <T extends z.ZodTypeAny>(recordSchema: T) =>
  apiResponseBaseSchema.extend({
    records: z.array(recordSchema),
    count: transforms.fromString.number.optional(),
    details: z.record(z.string(), z.unknown()).optional(),
  });

// Common error response schema
export const apiErrorResponseSchema = apiResponseBaseSchema.extend({
  message: z.string(),
  code: transforms.fromString.number,
  record: z.unknown().nullable(),
  details: z.record(z.string(), z.unknown()).optional(),
});

// Type exports for API responses
export type ApiBaseResponse = z.infer<typeof apiResponseBaseSchema>;
export type ApiErrorResponse = z.infer<typeof apiErrorResponseSchema>;
export type ApiRecordResponse<T> = z.infer<ReturnType<typeof createRecordResponseSchema<z.ZodType<T>>>>;
export type ApiRecordsResponse<T> = z.infer<ReturnType<typeof createRecordsResponseSchema<z.ZodType<T>>>>;
