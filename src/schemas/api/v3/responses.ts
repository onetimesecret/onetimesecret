// src/schemas/api/v3/responses.ts

import {
  accountSchema,
  apiTokenSchema,
  checkAuthDetailsSchema,
} from '@/schemas/api/account/endpoints/account';
import {
  systemSettingsDetailsSchema,
  colonelInfoDetailsSchema,
  colonelStatsDetailsSchema,
  colonelUsersDetailsSchema,
  colonelSecretsDetailsSchema,
  databaseMetricsDetailsSchema,
  redisMetricsDetailsSchema,
  bannedIPsDetailsSchema,
  usageExportDetailsSchema,
  colonelCustomDomainsDetailsSchema,
  colonelOrganizationsDetailsSchema,
  investigateOrganizationResultSchema,
  queueMetricsDetailsSchema,
} from '@/schemas/api/account/endpoints/colonel';
import {
  receiptRecordsDetailsSchema,
  receiptRecordsSchema,
} from '@/schemas/api/account/endpoints/recent';
import {
  loginResponseSchema,
  createAccountResponseSchema,
  logoutResponseSchema,
  resetPasswordRequestResponseSchema,
  resetPasswordResponseSchema,
} from '@/schemas/api/auth/endpoints/auth';
import { createApiListResponseSchema, createApiResponseSchema } from '@/schemas/api/v3/base';
import {
  concealDataSchema,
} from '@/schemas/api/v3/endpoints';
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
import { receiptDetailsSchema, receiptSchema } from '@/schemas/models/receipt';
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
  colonelStats: createApiResponseSchema(z.object({}), colonelStatsDetailsSchema),
  colonelUsers: createApiResponseSchema(z.object({}), colonelUsersDetailsSchema),
  colonelSecrets: createApiResponseSchema(z.object({}), colonelSecretsDetailsSchema),
  customDomains: createApiResponseSchema(z.object({}), colonelCustomDomainsDetailsSchema),
  colonelOrganizations: createApiResponseSchema(z.object({}), colonelOrganizationsDetailsSchema),
  investigateOrganization: createApiResponseSchema(investigateOrganizationResultSchema),
  databaseMetrics: createApiResponseSchema(z.object({}), databaseMetricsDetailsSchema),
  redisMetrics: createApiResponseSchema(z.object({}), redisMetricsDetailsSchema),
  bannedIPs: createApiResponseSchema(z.object({}), bannedIPsDetailsSchema),
  usageExport: createApiResponseSchema(z.object({}), usageExportDetailsSchema),
  queueMetrics: createApiResponseSchema(z.object({}), queueMetricsDetailsSchema),
  systemSettings: createApiResponseSchema(z.object({}), systemSettingsDetailsSchema),
  concealData: createApiResponseSchema(concealDataSchema),
  customDomain: createApiResponseSchema(customDomainSchema, customDomainDetailsSchema),
  customer: createApiResponseSchema(customerSchema, checkAuthDetailsSchema),
  feedback: createApiResponseSchema(feedbackSchema, feedbackDetailsSchema),
  imageProps: createApiResponseSchema(imagePropsSchema),
  jurisdiction: createApiResponseSchema(jurisdictionSchema, jurisdictionDetailsSchema),
  receipt: createApiResponseSchema(receiptSchema, receiptDetailsSchema),
  secret: createApiResponseSchema(secretSchema, secretDetailsSchema),

  // List responses
  customDomainList: createApiListResponseSchema(customDomainSchema, customDomainDetailsSchema),
  receiptList: createApiListResponseSchema(receiptRecordsSchema, receiptRecordsDetailsSchema),
  secretList: createApiListResponseSchema(secretResponsesSchema),

  // Special responses
  csrf: z.object({
    isValid: z.boolean(),
    shrimp: z.string(),
  }),

  // Authentication responses (Rodauth-compatible format)
  login: loginResponseSchema,
  createAccount: createAccountResponseSchema,
  logout: logoutResponseSchema,
  resetPasswordRequest: resetPasswordRequestResponseSchema,
  resetPassword: resetPasswordResponseSchema,
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
export type ColonelStatsResponse = ResponseTypes['colonelStats'];
export type ColonelUsersResponse = ResponseTypes['colonelUsers'];
export type ColonelSecretsResponse = ResponseTypes['colonelSecrets'];
export type CustomDomainsResponse = ResponseTypes['customDomains'];
export type ColonelOrganizationsResponse = ResponseTypes['colonelOrganizations'];
export type InvestigateOrganizationResponse = ResponseTypes['investigateOrganization'];
export type DatabaseMetricsResponse = ResponseTypes['databaseMetrics'];
export type RedisMetricsResponse = ResponseTypes['redisMetrics'];
export type BannedIPsResponse = ResponseTypes['bannedIPs'];
export type UsageExportResponse = ResponseTypes['usageExport'];
export type SystemSettingsResponse = ResponseTypes['systemSettings'];
export type ConcealDataResponse = ResponseTypes['concealData'];
export type CsrfResponse = ResponseTypes['csrf'];
export type CustomDomainListResponse = ResponseTypes['customDomainList'];
export type CustomDomainResponse = ResponseTypes['customDomain'];
export type CustomerResponse = ResponseTypes['customer'];
export type FeedbackResponse = ResponseTypes['feedback'];
export type ImagePropsResponse = ResponseTypes['imageProps'];
export type ReceiptListResponse = ResponseTypes['receiptList'];
export type ReceiptResponse = ResponseTypes['receipt'];
export type SecretListResponse = ResponseTypes['secretList'];
export type SecretResponse = ResponseTypes['secret'];
export type LoginResponse = ResponseTypes['login'];
export type CreateAccountResponse = ResponseTypes['createAccount'];
export type LogoutResponse = ResponseTypes['logout'];
export type ResetPasswordRequestResponse = ResponseTypes['resetPasswordRequest'];
export type ResetPasswordResponse = ResponseTypes['resetPassword'];
