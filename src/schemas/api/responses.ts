import { createApiListResponseSchema, createApiResponseSchema } from '@/schemas/api/base';
import {
  accountSchema,
  apiTokenSchema,
  checkAuthDetailsSchema,
} from '@/schemas/api/endpoints/account';
import {
  colonelConfigDetailsSchema,
  colonelInfoDetailsSchema,
} from '@/schemas/api/endpoints/colonel';
import {
  concealDataSchema,
  metadataRecordsDetailsSchema,
  metadataRecordsSchema,
} from '@/schemas/api/endpoints/index';
import {
  customDomainDetailsSchema,
  customDomainSchema,
  customerSchema,
  jurisdictionDetailsSchema,
  jurisdictionSchema,
  secretResponsesSchema,
} from '@/schemas/models';
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
  checkAuth: createApiResponseSchema(customerSchema, checkAuthDetailsSchema),
  colonelInfo: createApiResponseSchema(z.object({}), colonelInfoDetailsSchema),
  colonelConfig: createApiResponseSchema(z.object({}), colonelConfigDetailsSchema),
  concealData: createApiResponseSchema(concealDataSchema),
  customDomain: createApiResponseSchema(customDomainSchema, customDomainDetailsSchema),
  customer: createApiResponseSchema(customerSchema, checkAuthDetailsSchema),
  feedback: createApiResponseSchema(feedbackSchema, feedbackDetailsSchema),
  imageProps: createApiResponseSchema(imagePropsSchema),
  jurisdiction: createApiResponseSchema(jurisdictionSchema, jurisdictionDetailsSchema),
  metadata: createApiResponseSchema(metadataSchema, metadataDetailsSchema),
  secret: createApiResponseSchema(secretSchema, secretDetailsSchema),

  // List responses
  customDomainList: createApiListResponseSchema(customDomainSchema, customDomainDetailsSchema),
  metadataList: createApiListResponseSchema(metadataRecordsSchema, metadataRecordsDetailsSchema),
  secretList: createApiListResponseSchema(secretResponsesSchema),

  // Special responses
  csrf: z.object({
    isValid: z.boolean(),
    shrimp: z.string(),
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
export type ColonelInfoResponse = ResponseTypes['colonelInfo'];
export type ColonelSettingsResponse = ResponseTypes['colonelConfig'];
export type ConcealDataResponse = ResponseTypes['concealData'];
export type CsrfResponse = ResponseTypes['csrf'];
export type CustomDomainListResponse = ResponseTypes['customDomainList'];
export type CustomDomainResponse = ResponseTypes['customDomain'];
export type CustomerResponse = ResponseTypes['customer'];
export type FeedbackResponse = ResponseTypes['feedback'];
export type ImagePropsResponse = ResponseTypes['imageProps'];
export type MetadataListResponse = ResponseTypes['metadataList'];
export type MetadataResponse = ResponseTypes['metadata'];
export type SecretListResponse = ResponseTypes['secretList'];
export type SecretResponse = ResponseTypes['secret'];
