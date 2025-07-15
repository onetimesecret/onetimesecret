// src/schemas/api/base.ts
import { transforms } from '@/schemas/transforms';
import { z } from 'zod/v4';

const resolveDetailsSchema = <T extends z.ZodTypeAny | undefined>(schema?: T) =>
  schema ?? z.record(z.string(), z.unknown());

/**
 * Base schema patterns for API responses.
 *
 * Design Decisions:
 *
 * 1. Response Structure:
 *    All API responses follow consistent patterns:
 *    - success: boolean flag
 *    - record/records: primary payload
 *    - details: optional metadata
 *
 * 2. Single Record vs List Responses:
 *    We explicitly distinguish between:
 *    - Single record uses `record` field
 *    - List response uses `records` field
 *
 *    Benefits:
 *    - Explicit naming clearly indicates what to expect
 *    - Matches Ruby backend's response format
 *    - Type safety is more precise - compiler enforces correct expectations
 *    - Preferred over generic `data` field for API clarity
 *
 * 3. Type Parameters:
 *    Schemas use TypeScript generics to ensure:
 *    - Type safety for records
 *    - Flexible detail schemas
 *    - Proper type inference
 *
 * 4. Details Handling:
 *    - Optional details object
 *    - Defaults to record<string, unknown>
 *    - Can be extended with specific schemas
 */
const apiResponseBaseSchema = z.object({
  success: transforms.fromString.boolean,
  custid: z.string().optional(),
  shrimp: z.string().optional().default(''),
});

export const createApiResponseSchema = <
  TRecordSchema extends z.ZodTypeAny, // Renamed for clarity
  TDetailsSchema extends z.ZodTypeAny | undefined = undefined, // Renamed for clarity
>(
  recordSchema: TRecordSchema,
  detailsSchema?: TDetailsSchema
) =>
  apiResponseBaseSchema.extend({
    record: recordSchema,
    details: resolveDetailsSchema(detailsSchema).optional(),
  });

export const createApiListResponseSchema = <
  TRecordSchema extends z.ZodTypeAny, // Renamed for clarity
  TDetailsSchema extends z.ZodTypeAny | undefined = undefined, // Renamed for clarity
>(
  recordSchema: TRecordSchema,
  detailsSchema?: TDetailsSchema
) =>
  apiResponseBaseSchema.extend({
    records: z.array(recordSchema),
    details: resolveDetailsSchema(detailsSchema).optional(),
    count: transforms.fromString.number.optional(),
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

export type ApiRecordResponse<
  TRecordData, // The data type for the record
  TDetailsZodSchema extends z.ZodTypeAny | undefined = undefined, // Use Zod schema, or undefined
> = z.infer<ReturnType<typeof createApiResponseSchema<z.ZodType<TRecordData>, TDetailsZodSchema>>>;

export type ApiRecordsResponse<
  TRecordData, // The data type for the records in the array
  TDetailsZodSchema extends z.ZodTypeAny | undefined = undefined, // Use Zod schema, or undefined
> = z.infer<
  ReturnType<typeof createApiListResponseSchema<z.ZodType<TRecordData>, TDetailsZodSchema>>
>;
