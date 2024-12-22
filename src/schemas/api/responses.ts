import {
    apiResponseBaseSchema,
    createRecordResponseSchema,
    createRecordsResponseSchema,
} from '@/schemas/api/base';
import { accountSchema, apiTokenSchema, customerSchema } from '@/schemas/models';
import { colonelDataResponseSchema } from '@/schemas/models/colonel';
import { customDomainSchema } from '@/schemas/models/domain';
import { brandSettingschema, imagePropsSchema } from '@/schemas/models/domain/brand';
import {
    concealDataSchema,
    metadataDetailsSchema,
    metadataRecordsDetailsSchema,
    metadataSchema,
} from '@/schemas/models/metadata';
import { secretDetailsSchema, secretSchema } from '@/schemas/models/secret';
import { z } from 'zod';

export interface AsyncDataResult<T> {
  data: T | null;
  error: string | null;
  status: number | null;
}

// Specific metadata response schema with properly typed details
export const metadataRecordResponseSchema = apiResponseBaseSchema.extend({
  record: metadataSchema,
  details: z
    .discriminatedUnion('type', [metadataRecordsDetailsSchema, metadataDetailsSchema])
    .optional(),
});

// Specialized secret response schema
export const secretRecordResponseSchema = apiResponseBaseSchema.extend({
  record: secretSchema,
  details: secretDetailsSchema.optional(),
});

// Model-specific response schemas
export const apiTokenResponseSchema = createRecordResponseSchema(apiTokenSchema);
export const customDomainResponseSchema = createRecordResponseSchema(customDomainSchema);
export const customDomainRecordsResponseSchema = createRecordsResponseSchema(customDomainSchema);
export const accountResponseSchema = createRecordResponseSchema(accountSchema);
export const concealDataResponseSchema = createRecordResponseSchema(concealDataSchema);
export const checkAuthDataResponseSchema = createRecordResponseSchema(customerSchema);
export const brandSettingsResponseSchema = createRecordResponseSchema(brandSettingschema);
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

// Colonel response types
export type ColonelDataApiResponse = z.infer<typeof colonelDataResponseSchema>;

export const CsrfResponse = z.object({
  isValid: z.boolean(),
  shrimp: z.string().optional(),
});

export type TCsrfResponse = z.infer<typeof CsrfResponse>;
