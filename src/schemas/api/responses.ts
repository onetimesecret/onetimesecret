import { createApiListResponseSchema, createApiResponseSchema } from '@/schemas/api/base';
import {
    accountSchema,
    apiTokenSchema,
    checkAuthDetailsSchema,
} from '@/schemas/api/endpoints/account';
import { colonelDataResponseSchema } from '@/schemas/api/endpoints/colonel';
import { checkAuthDataSchema, concealDataSchema } from '@/schemas/api/endpoints/index';
import { customDomainSchema, customerSchema, secretListSchema } from '@/schemas/models';
import { brandSettingschema, imagePropsSchema } from '@/schemas/models/domain/brand';
import { feedbackDetailsSchema, feedbackSchema } from '@/schemas/models/feedback';
import { metadataDetailsSchema, metadataSchema } from '@/schemas/models/metadata';
import { secretDetailsSchema, secretSchema } from '@/schemas/models/secret';
import { z } from 'zod';

export interface AsyncDataResult<T> {
  data: T | null;
  error: string | null;
  status: number | null;
}

// Single source of truth for response schemas
export const responseSchemas = {
  // Single record responses
  account: createApiResponseSchema(accountSchema),
  apiToken: createApiResponseSchema(apiTokenSchema),
  brandSettings: createApiResponseSchema(brandSettingschema),
  checkAuth: createApiResponseSchema(checkAuthDataSchema),
  colonel: createApiResponseSchema(colonelDataResponseSchema),
  concealData: createApiResponseSchema(concealDataSchema),
  customDomain: createApiResponseSchema(customDomainSchema),
  customer: createApiResponseSchema(customerSchema, checkAuthDetailsSchema),
  imageProps: createApiResponseSchema(imagePropsSchema),
  metadata: createApiResponseSchema(metadataSchema, metadataDetailsSchema),
  secret: createApiResponseSchema(secretSchema, secretDetailsSchema),
  feedback: createApiResponseSchema(feedbackSchema, feedbackDetailsSchema),

  // List responses
  customDomainList: createApiListResponseSchema(customDomainSchema),
  metadataList: createApiListResponseSchema(metadataSchema),
  secretList: createApiListResponseSchema(secretListSchema),

  // Special responses
  csrf: z.object({
    isValid: z.boolean(),
    shrimp: z.string().optional(),
  }),
} as const;

// Single source of truth for response types
export type ResponseTypes = {
  [K in keyof typeof responseSchemas]: z.infer<(typeof responseSchemas)[K]>;
};

// Export specific types
export type AccountResponse = ResponseTypes['account'];
export type ApiTokenResponse = ResponseTypes['apiToken'];
export type BrandSettingsResponse = ResponseTypes['brandSettings'];
export type CheckAuthResponse = ResponseTypes['checkAuth'];
export type ColonelResponse = ResponseTypes['colonel'];
export type ConcealDataResponse = ResponseTypes['concealData'];
export type CustomDomainResponse = ResponseTypes['customDomain'];
export type CustomDomainListResponse = ResponseTypes['customDomainList'];
export type CustomerResponse = ResponseTypes['customer'];
export type ImagePropsResponse = ResponseTypes['imageProps'];
export type MetadataResponse = ResponseTypes['metadata'];
export type MetadataListResponse = ResponseTypes['metadataList'];
export type SecretResponse = ResponseTypes['secret'];
export type SecretListResponse = ResponseTypes['secretList'];
export type CsrfResponse = ResponseTypes['csrf'];
export type FeedbackResponse = ResponseTypes['feedback'];
