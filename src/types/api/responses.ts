import { baseApiRecordSchema } from '@/schemas/base';
import { feedbackInputSchema } from '@/schemas/models';
import { customerInputSchema } from '@/schemas/models/customer';
import { customDomainInputSchema } from '@/schemas/models/domain';
import { brandSettingsInputSchema, imagePropsSchema } from '@/schemas/models/domain/brand';
import { concealDataSchema, metadataDataSchema } from '@/schemas/models/metadata';
import { secretInputSchema } from '@/schemas/models/secret';
import type { Stripe } from 'stripe';
import { z } from 'zod';

/**
 * @fileoverview API Response type definitions
 *
 * Key Design Decisions:
 * 1. Input schemas handle API -> App transformation
 * 2. App uses single shared type between stores/components
 * 3. No explicit output schemas - serialize when needed
 *
 * Type Flow:
 * API Raw JSON -> Input Schema -> Store/Components -> API Request
 *                 (transforms)     (shared types)     (serialize)
 *
 * These types represent the raw API response structure before transformation.
 * Actual data transformation happens in corresponding input schemas.
 */


// Async Data Result
export const asyncDataResultSchema = <T extends z.ZodType>(dataSchema: T) => z.object({
  data: dataSchema.nullable(),
  error: z.union([z.instanceof(Error), z.string()]).nullable(),
  status: z.number().nullable()
});

export type AsyncDataResult<T> = z.infer<ReturnType<typeof asyncDataResultSchema<z.ZodType<T>>>>;

// API client interface - defines service shape, not data structure
// API response with data schema
export const apiDataResponseSchema = <T extends z.ZodType>(dataSchema: T) =>
  apiBaseResponseSchema.extend({
    data: dataSchema
  });

// Type helper for API responses
export type ApiDataResponse<T> = z.infer<ReturnType<typeof apiDataResponseSchema<z.ZodType<T>>>>;

// Updated API client interface using Zod schemas
export interface ApiClient {
  get<T extends z.ZodType>(
    url: string,
    schema: T
  ): Promise<ApiDataResponse<z.infer<T>>>;

  post<T extends z.ZodType>(
    url: string,
    data: Record<string, unknown>,
    schema: T
  ): Promise<ApiDataResponse<z.infer<T>>>;

  put<T extends z.ZodType>(
    url: string,
    data: Record<string, unknown>,
    schema: T
  ): Promise<ApiDataResponse<z.infer<T>>>;

  delete<T extends z.ZodType>(
    url: string,
    schema: T
  ): Promise<ApiDataResponse<z.infer<T>>>;
}


/**
 * Schema for API record responses
 * Validates and transforms raw API responses
 */

export const apiBaseResponseSchema = z.object({
  success: z.boolean()
});

export const apiRecordResponseSchema = <T extends z.ZodType>(recordSchema: T) =>
  apiBaseResponseSchema.extend({
    record: recordSchema,
    details: z.record(z.string(), z.unknown()).optional()
  });

export const apiRecordsResponseSchema = <T extends z.ZodType>(recordSchema: T) =>
  apiBaseResponseSchema.extend({
    custid: z.string(),
    records: z.array(recordSchema),
    count: z.number(),
    details: z.record(z.string(), z.unknown()).optional()
  });

// Generic response wrappers - used to type raw API responses
export const apiErrorResponseSchema = apiBaseResponseSchema.extend({
  message: z.string(),
  code: z.number(),
  record: z.unknown().nullable(),
  details: z.record(z.string(), z.unknown()).optional()
});


export type ApiRecordsResponse<T> = z.infer<ReturnType<typeof apiRecordsResponseSchema<z.ZodType<T>>>>;
export type ApiRecordResponse<T> = z.infer<ReturnType<typeof apiRecordResponseSchema<z.ZodType<T>>>>;

/**
 * Raw API data structures before transformation
 * These represent the API shape that will be transformed by input schemas
 */
export const colonelDataSchema = baseApiRecordSchema.extend({
  apitoken: z.string(),
  active: z.string().transform(val => val === "1"),
  recent_customers: z.array(customerInputSchema),
  today_feedback: z.array(feedbackInputSchema), // Need to import feedbackInputSchema
  yesterday_feedback: z.array(feedbackInputSchema),
  older_feedback: z.array(feedbackInputSchema),
  redis_info: z.string().transform(Number),
  plans_enabled: z.string().transform(Number),
  counts: z.object({
    session_count: z.string().transform(Number),
    customer_count: z.string().transform(Number),
    recent_customer_count: z.string().transform(Number),
    metadata_count: z.string().transform(Number),
    secret_count: z.string().transform(Number),
    secrets_created: z.string().transform(Number),
    secrets_shared: z.string().transform(Number),
    emails_sent: z.string().transform(Number),
    feedback_count: z.string().transform(Number),
    today_feedback_count: z.string().transform(Number),
    yesterday_feedback_count: z.string().transform(Number),
    older_feedback_count: z.string().transform(Number),
  })
});

// Response schemas using the specific record schemas
export const colonelDataResponseSchema = apiRecordResponseSchema(colonelDataSchema);
export const colonelDataRecordsResponseSchema = apiRecordsResponseSchema(colonelDataSchema);


export const apiTokenSchema = baseApiRecordSchema.extend({
  apitoken: z.string(),
  active: z.string().transform(val => val === "1")
});

export const accountSchema = baseApiRecordSchema.extend({
  cust: customerInputSchema,
  apitoken: z.string().optional(),
  stripe_customer: z.custom<Stripe.Customer>(),
  stripe_subscriptions: z.array(z.custom<Stripe.Subscription>())
});

// Create response schemas for each type
export const apiTokenResponseSchema = apiRecordResponseSchema(apiTokenSchema);
export const customDomainResponseSchema = apiRecordResponseSchema(customDomainInputSchema);
export const customDomainRecordsResponseSchema = apiRecordsResponseSchema(customDomainInputSchema);
export const accountResponseSchema = apiRecordResponseSchema(accountSchema);
export const metadataDataResponseSchema = apiRecordResponseSchema(metadataDataSchema);
export const secretDataResponseSchema = apiRecordResponseSchema(secretInputSchema);
export const concealDataResponseSchema = apiRecordResponseSchema(concealDataSchema);
export const checkAuthDataResponseSchema = apiRecordResponseSchema(customerInputSchema);
export const brandSettingsResponseSchema = apiRecordResponseSchema(brandSettingsInputSchema);
export const imagePropsResponseSchema = apiRecordResponseSchema(imagePropsSchema);

/**
 * Response type exports combining API structure with transformed app types
 * These types represent the shape after schema transformation
 */

// Replace interface-based types with inferred types from schemas
export type ApiTokenApiResponse = z.infer<typeof apiTokenResponseSchema>;
export type CustomDomainApiResponse = z.infer<typeof customDomainResponseSchema>;
export type AccountApiResponse = z.infer<typeof accountResponseSchema>;
export type ColonelDataApiResponse = z.infer<typeof colonelDataResponseSchema>;
export type MetadataDataApiResponse = z.infer<typeof metadataDataResponseSchema>;
export type SecretDataApiResponse = z.infer<typeof secretDataResponseSchema>;
export type ConcealDataApiResponse = z.infer<typeof concealDataResponseSchema>;
export type CheckAuthDataApiResponse = z.infer<typeof checkAuthDataResponseSchema>;
export type BrandSettingsApiResponse = z.infer<typeof brandSettingsResponseSchema>;
export type ImagePropsApiResponse = z.infer<typeof imagePropsResponseSchema>;
export type CustomDomainRecordsApiResponse = z.infer<typeof customDomainRecordsResponseSchema>;
export type UpdateDomainBrandResponse = z.infer<typeof customDomainResponseSchema>;
