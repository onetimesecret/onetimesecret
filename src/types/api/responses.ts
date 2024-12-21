import { apiResponseBaseSchema, createRecordResponseSchema, createRecordsResponseSchema } from '@/schemas/api/base';
import { accountSchema, apiTokenSchema, customerSchema } from '@/schemas/models';
import { customDomainInputSchema } from '@/schemas/models/domain';
import { brandSettingsInputSchema, imagePropsSchema } from '@/schemas/models/domain/brand';
import {
  concealDataSchema,
  metadataDetailsInputSchema,
  metadataRecordsDetailsSchema,
  metadataSchema,
} from '@/schemas/models/metadata';
import { secretDetailsInputSchema, secretInputSchema } from '@/schemas/models/secret';
import { z } from 'zod';

export interface AsyncDataResult<T> {
  data: T | null;
  error: string | null;
  status: number | null;
}

// Specific metadata response schema with properly typed details
export const metadataRecordResponseSchema = apiResponseBaseSchema.extend({
  record: metadataSchema,
  details: z.discriminatedUnion('type', [
    metadataRecordsDetailsSchema,
    metadataDetailsInputSchema,
  ]).optional(),
});

// Specialized secret response schema
export const secretRecordResponseSchema = apiResponseBaseSchema.extend({
  record: secretInputSchema,
  details: secretDetailsInputSchema.optional(),
});

// Model-specific response schemas
export const apiTokenResponseSchema = createRecordResponseSchema(apiTokenSchema);
export const customDomainResponseSchema = createRecordResponseSchema(customDomainInputSchema);
export const customDomainRecordsResponseSchema = createRecordsResponseSchema(customDomainInputSchema);
export const accountResponseSchema = createRecordResponseSchema(accountSchema);
export const concealDataResponseSchema = createRecordResponseSchema(concealDataSchema);
export const checkAuthDataResponseSchema = createRecordResponseSchema(customerSchema);
export const brandSettingsResponseSchema = createRecordResponseSchema(brandSettingsInputSchema);
export const imagePropsResponseSchema = createRecordResponseSchema(imagePropsSchema);

/**
 * Response type exports combining API structure with transformed app types
 * These types represent the shape after schema transformation
 */
export type ApiTokenApiResponse = z.infer<typeof apiTokenResponseSchema>;
export type CustomDomainApiResponse = z.infer<typeof customDomainResponseSchema>;
export type AccountApiResponse = z.infer<typeof accountResponseSchema>;
export type MetadataRecordApiResponse = z.infer<typeof metadataRecordResponseSchema>;
export type SecretRecordApiResponse = z.infer<typeof secretRecordResponseSchema>;
export type ConcealDataApiResponse = z.infer<typeof concealDataResponseSchema>;
export type CheckAuthDataApiResponse = z.infer<typeof checkAuthDataResponseSchema>;
export type BrandSettingsApiResponse = z.infer<typeof brandSettingsResponseSchema>;
export type ImagePropsApiResponse = z.infer<typeof imagePropsResponseSchema>;
export type CustomDomainRecordsApiResponse = z.infer<typeof customDomainRecordsResponseSchema>;
export type UpdateDomainBrandResponse = z.infer<typeof customDomainResponseSchema>;
