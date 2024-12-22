import { transforms } from '@/utils/transforms';
import { z } from 'zod';

const resolveDetailsSchema = <T extends z.ZodTypeAny | undefined>(schema?: T) =>
  schema ?? z.record(z.string(), z.unknown());

// Base schema that all API responses extend from
const apiResponseBaseSchema = z.object({
  success: transforms.fromString.boolean,
  custid: z.string().optional(),
  shrimp: z.string().optional().default(''),
});

// Base response schema with more flexible type inference.
//
// NOTE: This is a more flexible version of the original createApiResponseSchema
// that allows for more complex record and details schemas. We only use this
// when we need to define a custom details schema which is only in a handful
// of places, but when we do it's important to have the type safety.
//
// was: createApiResponseSchema
export const createApiResponseSchema = <
  TRecord extends z.ZodTypeAny,
  TDetails extends z.ZodTypeAny | undefined = undefined,
>(
  recordSchema: TRecord,
  detailsSchema?: TDetails
) => {
  return apiResponseBaseSchema.extend({
    record: recordSchema,
    details: resolveDetailsSchema(detailsSchema).optional(),
  });
};

// was: createRecordsResponseSchema
export const createApiListResponseSchema = <TRecord extends z.ZodTypeAny>(
  recordSchema: TRecord
) => {
  return apiResponseBaseSchema.extend({
    records: z.array(recordSchema),
    details: z.record(z.string(), z.unknown()).optional(),
    count: transforms.fromString.number.optional(),
  });
};

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
export type ApiRecordResponse<T> = z.infer<
  ReturnType<typeof createApiResponseSchema<z.ZodType<T>>>
>;
export type ApiRecordsResponse<T> = z.infer<
  ReturnType<typeof createApiListResponseSchema<z.ZodType<T>>>
>;
