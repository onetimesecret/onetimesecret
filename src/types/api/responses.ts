import { baseRecordSchema } from '@/schemas/base';
import { feedbackInputSchema } from '@/schemas/models';
import { customerSchema } from '@/schemas/models/customer';
import { customDomainInputSchema } from '@/schemas/models/domain';
import { brandSettingsInputSchema, imagePropsSchema } from '@/schemas/models/domain/brand';
import {
  concealDataInputSchema,
  metadataDetailsInputSchema,
  metadataSchema,
  metadataListItemDetailsInputSchema,
} from '@/schemas/models/metadata';
import { secretDetailsInputSchema, secretInputSchema } from '@/schemas/models/secret';
import { booleanFromString } from '@/utils/transforms';
import type { Stripe } from 'stripe';
import { z } from 'zod';

export interface AsyncDataResult<T> {
  data: T | null;
  error: string | null;
  status: number | null;
}

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

// API response with data schema
export const apiDataResponseSchema = <T extends z.ZodType>(schema: T) => schema;

// Type helper for API responses - constrain T to be a ZodType
export type ApiDataResponse<T extends z.ZodType> = z.infer<T>;

// Updated API client interface remains the same but will now return the direct schema type
export interface ApiClient {
  get<T extends z.ZodType>(url: string, schema: T): Promise<z.infer<T>>;
  post<T extends z.ZodType>(
    url: string,
    data: Record<string, unknown>,
    schema: T
  ): Promise<z.infer<T>>;
  put<T extends z.ZodType>(
    url: string,
    data: Record<string, unknown>,
    schema: T
  ): Promise<z.infer<T>>;
  delete<T extends z.ZodType>(url: string, schema: T): Promise<z.infer<T>>;
}

/**
 * Schema for API record responses
 * Validates and transforms raw API responses
 */

export const apiBaseResponseSchema = z.object({
  success: z.boolean(),
  custid: z.string().optional(),
  shrimp: z.string().optional().default(''),
});

export const apiRecordResponseSchema = <T extends z.ZodType>(recordSchema: T) =>
  apiBaseResponseSchema.extend({
    record: recordSchema,
    details: z.record(z.string(), z.unknown()).optional(),
  });

export const apiRecordsResponseSchema = <T extends z.ZodType>(recordSchema: T) =>
  apiBaseResponseSchema.extend({
    records: z.array(recordSchema),
    count: z.number(),
    details: z.discriminatedUnion('type', [
      metadataListItemDetailsInputSchema,
      metadataDetailsInputSchema,
    ]).optional(),
  });

// Generic response wrappers - used to type raw API responses
export const apiErrorResponseSchema = apiBaseResponseSchema.extend({
  message: z.string(),
  code: z.number(),
  record: z.unknown().nullable(),
  details: z.record(z.string(), z.unknown()).optional(),
});

// Specific metadata response schema with properly typed details
export const metadataRecordResponseSchema = apiBaseResponseSchema.extend({
  record: metadataSchema,
  details: z.discriminatedUnion('type', [
    metadataListItemDetailsInputSchema,
    metadataDetailsInputSchema,
  ]).optional(),
});

// Ditto for secrets
export const secretRecordResponseSchema = apiBaseResponseSchema.extend({
  record: secretInputSchema,
  details: secretDetailsInputSchema.optional(),
});

export type ApiRecordsResponse<T> = z.infer<
  ReturnType<typeof apiRecordsResponseSchema<z.ZodType<T>>>
>;
export type ApiRecordResponse<T> = z.infer<
  ReturnType<typeof apiRecordResponseSchema<z.ZodType<T>>>
>;

/**
 * Raw API data structures before transformation
 * These represent the API shape that will be transformed by input schemas
 */
export const colonelDataSchema = baseRecordSchema.extend({
  apitoken: z.string(),
  active: z.string().transform((val) => val === '1'),
  recent_customers: z.array(customerSchema),
  today_feedback: z.array(feedbackInputSchema),
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
  }),
});

// Response schemas using the specific record schemas
export const colonelDataResponseSchema = apiRecordResponseSchema(colonelDataSchema);
export const colonelDataRecordsResponseSchema = apiRecordsResponseSchema(colonelDataSchema);

// API Token response has only two fields - apitoken and active (and not the usual created/updated/identifier)
export const apiTokenSchema = z.object({
  apitoken: z.string(),
  active: booleanFromString,
});

export const accountSchema = baseRecordSchema.extend({
  cust: customerSchema,
  apitoken: z.string().optional(),
  stripe_customer: z.custom<Stripe.Customer>(),
  stripe_subscriptions: z.array(z.custom<Stripe.Subscription>()),
});

// Create response schemas for each type
export const apiTokenResponseSchema = apiRecordResponseSchema(apiTokenSchema);
export const customDomainResponseSchema = apiRecordResponseSchema(customDomainInputSchema);
export const customDomainRecordsResponseSchema = apiRecordsResponseSchema(customDomainInputSchema);
export const accountResponseSchema = apiRecordResponseSchema(accountSchema);
export const concealDataResponseSchema = apiRecordResponseSchema(concealDataInputSchema);
export const checkAuthDataResponseSchema = apiRecordResponseSchema(customerSchema);
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
export type MetadataRecordApiResponse = z.infer<typeof metadataRecordResponseSchema>;
export type SecretRecordApiResponse = z.infer<typeof secretRecordResponseSchema>;
export type ConcealDataApiResponse = z.infer<typeof concealDataResponseSchema>;
export type CheckAuthDataApiResponse = z.infer<typeof checkAuthDataResponseSchema>;
export type BrandSettingsApiResponse = z.infer<typeof brandSettingsResponseSchema>;
export type ImagePropsApiResponse = z.infer<typeof imagePropsResponseSchema>;
export type CustomDomainRecordsApiResponse = z.infer<typeof customDomainRecordsResponseSchema>;
export type UpdateDomainBrandResponse = z.infer<typeof customDomainResponseSchema>;
export type ApiErrorResponse = z.infer<typeof apiErrorResponseSchema>;
export type ColonelData = z.infer<typeof colonelDataSchema>;
