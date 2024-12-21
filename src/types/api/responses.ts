import { apiTokenSchema, customerSchema, feedbackInputSchema } from '@/schemas/models';
import { baseRecordSchema } from '@/schemas/models/base';
import { customDomainInputSchema } from '@/schemas/models/domain';
import { brandSettingsInputSchema, imagePropsSchema } from '@/schemas/models/domain/brand';
import {
  concealDataInputSchema,
  metadataDetailsInputSchema,
  metadataListItemDetailsInputSchema,
  metadataSchema,
} from '@/schemas/models/metadata';
import { secretDetailsInputSchema, secretInputSchema } from '@/schemas/models/secret';
import type { Stripe } from 'stripe';
import { z } from 'zod';

export interface AsyncDataResult<T> {
  data: T | null;
  error: string | null;
  status: number | null;
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
//export type ColonelDataApiResponse = z.infer<typeof colonelDataResponseSchema>;
export type MetadataRecordApiResponse = z.infer<typeof metadataRecordResponseSchema>;
export type SecretRecordApiResponse = z.infer<typeof secretRecordResponseSchema>;
export type ConcealDataApiResponse = z.infer<typeof concealDataResponseSchema>;
export type CheckAuthDataApiResponse = z.infer<typeof checkAuthDataResponseSchema>;
export type BrandSettingsApiResponse = z.infer<typeof brandSettingsResponseSchema>;
export type ImagePropsApiResponse = z.infer<typeof imagePropsResponseSchema>;
export type CustomDomainRecordsApiResponse = z.infer<typeof customDomainRecordsResponseSchema>;
export type UpdateDomainBrandResponse = z.infer<typeof customDomainResponseSchema>;
export type ApiErrorResponse = z.infer<typeof apiErrorResponseSchema>;
//export type ColonelData = z.infer<typeof colonelDataSchema>;
