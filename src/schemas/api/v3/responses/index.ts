// src/schemas/api/v3/responses/index.ts
//
// V3 response schema registry and barrel exports.
//
// V3 schemas use JSON-native input types (booleans, numbers, strings) that
// match what the V3 API sends over the wire. Timestamp fields use
// transforms.fromNumber.toDate to convert Unix epoch seconds into Date
// objects at parse time. This works with io:"input" in z.toJSONSchema()
// so OpenAPI still documents the wire type (number), not the output (Date).
//
// Unlike V2 schemas, V3 does NOT use z.preprocess() or transforms.fromString.*
// because the V3 backend sends properly typed JSON (not Redis string encodings).

import { z } from 'zod';

// Domain modules
import {
  accountResponseSchema,
  apiTokenResponseSchema,
  checkAuthResponseSchema,
  customerResponseSchema,
} from './account';
import {
  loginResponseSchema,
  createAccountResponseSchema,
  logoutResponseSchema,
  resetPasswordRequestResponseSchema,
  resetPasswordResponseSchema,
} from './auth';
import {
  colonelInfoResponseSchema,
  colonelStatsResponseSchema,
  colonelUsersResponseSchema,
  colonelSecretsResponseSchema,
  colonelCustomDomainsResponseSchema,
  colonelOrganizationsResponseSchema,
  investigateOrganizationResponseSchema,
  databaseMetricsResponseSchema,
  redisMetricsResponseSchema,
  bannedIPsResponseSchema,
  usageExportResponseSchema,
  queueMetricsResponseSchema,
  systemSettingsResponseSchema,
} from './colonel';
import { csrfResponseSchema } from './csrf';
import {
  brandSettingsResponseSchema,
  customDomainResponseSchema,
  customDomainListResponseSchema,
  imagePropsResponseSchema,
  jurisdictionResponseSchema,
} from './domains';
import { feedbackResponseSchema } from './feedback';
import {
  systemStatusResponseSchema,
  systemVersionResponseSchema,
  supportedLocalesResponseSchema,
} from './meta';
import {
  incomingConfigResponseSchema,
  incomingSecretResponseSchema,
  validateRecipientEnvelopeSchema,
} from './incoming';
import {
  organizationResponseSchema,
  organizationsResponseSchema,
  orgDeleteResponseSchema,
  membersResponseSchema,
  memberResponseSchema,
  memberDeleteResponseSchema,
} from './organizations';
import { receiptResponseSchema, receiptListResponseSchema } from './receipts';
import {
  concealDataResponseSchema,
  secretResponseSchema,
  secretListResponseSchema,
} from './secrets';

// V1-specific response schemas (registered here for scanner validation)
import { v1ResponseSchemas } from '../../v1/responses';

// ─────────────────────────────────────────────────────────────────────────────
// Response schema registry
// ─────────────────────────────────────────────────────────────────────────────

/** Keyed lookup of all V3 response schemas. Used by the OpenAPI generator
 *  and Pinia stores for runtime Zod parsing. */
export const responseSchemas = {
  // Account
  account: accountResponseSchema,
  apiToken: apiTokenResponseSchema,
  checkAuth: checkAuthResponseSchema,
  customer: customerResponseSchema,

  // Colonel / admin
  colonelInfo: colonelInfoResponseSchema,
  colonelStats: colonelStatsResponseSchema,
  colonelUsers: colonelUsersResponseSchema,
  colonelSecrets: colonelSecretsResponseSchema,
  customDomains: colonelCustomDomainsResponseSchema,
  colonelOrganizations: colonelOrganizationsResponseSchema,
  investigateOrganization: investigateOrganizationResponseSchema,
  databaseMetrics: databaseMetricsResponseSchema,
  redisMetrics: redisMetricsResponseSchema,
  bannedIPs: bannedIPsResponseSchema,
  usageExport: usageExportResponseSchema,
  queueMetrics: queueMetricsResponseSchema,
  systemSettings: systemSettingsResponseSchema,

  // Secrets
  concealData: concealDataResponseSchema,
  secret: secretResponseSchema,
  secretList: secretListResponseSchema,

  // Domains / brand
  brandSettings: brandSettingsResponseSchema,
  customDomain: customDomainResponseSchema,
  customDomainList: customDomainListResponseSchema,
  imageProps: imagePropsResponseSchema,
  jurisdiction: jurisdictionResponseSchema,

  // Receipts
  receipt: receiptResponseSchema,
  receiptList: receiptListResponseSchema,

  // Organizations
  organization: organizationResponseSchema,
  organizationList: organizationsResponseSchema,
  organizationDelete: orgDeleteResponseSchema,
  memberList: membersResponseSchema,
  member: memberResponseSchema,
  memberDelete: memberDeleteResponseSchema,

  // Incoming
  incomingConfig: incomingConfigResponseSchema,
  incomingSecret: incomingSecretResponseSchema,
  validateRecipient: validateRecipientEnvelopeSchema,

  // Meta
  systemStatus: systemStatusResponseSchema,
  systemVersion: systemVersionResponseSchema,
  supportedLocales: supportedLocalesResponseSchema,

  // Feedback
  feedback: feedbackResponseSchema,

  // CSRF
  csrf: csrfResponseSchema,

  // Authentication (Rodauth-compatible)
  login: loginResponseSchema,
  createAccount: createAccountResponseSchema,
  logout: logoutResponseSchema,
  resetPasswordRequest: resetPasswordRequestResponseSchema,
  resetPassword: resetPasswordResponseSchema,

  // V1 legacy API
  ...v1ResponseSchemas,
} as const;

// ─────────────────────────────────────────────────────────────────────────────
// Mapped types
// ─────────────────────────────────────────────────────────────────────────────

export type ResponseTypes = {
  [K in keyof typeof responseSchemas]: z.infer<(typeof responseSchemas)[K]>;
};

// ─────────────────────────────────────────────────────────────────────────────
// Re-export all types from domain modules
// ─────────────────────────────────────────────────────────────────────────────

export type { AccountResponse, ApiTokenResponse, CheckAuthResponse, CustomerResponse } from './account';
export type { LoginResponse, CreateAccountResponse, LogoutResponse, ResetPasswordRequestResponse, ResetPasswordResponse } from './auth';
export type { ColonelInfoResponse, ColonelStatsResponse, ColonelUsersResponse, ColonelSecretsResponse, CustomDomainsResponse, ColonelOrganizationsResponse, InvestigateOrganizationResponse, DatabaseMetricsResponse, RedisMetricsResponse, BannedIPsResponse, UsageExportResponse, QueueMetricsResponse, SystemSettingsResponse } from './colonel';
export type { CsrfResponse } from './csrf';
export type { BrandSettingsResponse, CustomDomainDetails, CustomDomainResponse, CustomDomainListResponse, ImagePropsResponse, JurisdictionResponse } from './domains';
export type { FeedbackResponse } from './feedback';
export type { IncomingConfigResponse, IncomingSecretResponse, ValidateRecipientResponse } from './incoming';
export type { OrganizationResponse, OrganizationListResponse, OrganizationDeleteResponse, MemberListResponse, MemberResponse, MemberDeleteResponse } from './organizations';
export type { ReceiptResponse, ReceiptListResponse } from './receipts';
export type { ConcealDataResponse, SecretResponse, SecretListResponse } from './secrets';
export type { SystemStatusResponse, SystemVersionResponse, SupportedLocalesResponse } from './meta';
