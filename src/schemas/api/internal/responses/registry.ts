// src/schemas/api/internal/responses/registry.ts
//
// Assembles response schemas for internal APIs (account, colonel, domains,
// organizations, invite). These are consumed by the Vue frontend, not
// exposed publicly.
//
// Separated from V2/V3 registries to keep public API schemas clean.

import { z } from 'zod';

// Colonel (admin) schemas — internal-only
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
  colonelUserDetailResponseSchema,
  colonelUserMutationResponseSchema,
} from './colonel';

// Colonel (admin) per-resource ack schemas — Phase-2 screens (tickets #30-33)
import {
  colonelSecretReceiptResponseSchema,
  colonelSecretDeleteResponseSchema,
} from './colonel-secrets';
import { colonelDomainVerifyResponseSchema } from './colonel-domains';
import { colonelEntitlementOverrideResponseSchema } from './colonel-organizations';
import {
  colonelBanIpResponseSchema,
  colonelUnbanIpResponseSchema,
} from './colonel-bannedips';

// Colonel (admin) per-resource schemas — Phase-3 screens (tickets #40-45).
// The DLQ console and the rate-limit inspect/reset UI were removed by design
// review; their envelopes stay registry-only as the OpenAPI contract for the
// still-live endpoints (list_dlqs.rb declares `response: 'colonelDlqList'`).
import {
  colonelSessionsResponseSchema,
  colonelSessionDetailResponseSchema,
  colonelSessionDeleteResponseSchema,
} from './colonel-sessions';
import {
  colonelBannerResponseSchema,
  colonelBannerSetResponseSchema,
  colonelBannerClearResponseSchema,
} from './colonel-banner';
import {
  colonelDlqListResponseSchema,
  colonelDlqMessagesResponseSchema,
  colonelDlqReplayResponseSchema,
  colonelDlqPurgeResponseSchema,
} from './colonel-queue';
import {
  colonelDomainsOrphanedResponseSchema,
  colonelDomainProbeResponseSchema,
  colonelDomainRepairResponseSchema,
  colonelDomainTransferResponseSchema,
} from './colonel-domaintoolbox';
import {
  colonelEmailTemplatesResponseSchema,
  colonelEmailPreviewResponseSchema,
  colonelEmailTestResponseSchema,
  colonelRateLimitersResponseSchema,
  colonelRateLimitInspectResponseSchema,
  colonelRateLimitResetResponseSchema,
} from './colonel-emailtools';
import { colonelBillingCatalogResponseSchema } from './colonel-billing';

// Organization schemas — internal-only
import {
  organizationResponseSchema,
  organizationsResponseSchema,
  orgDeleteResponseSchema,
  membersResponseSchema,
  memberResponseSchema,
  memberDeleteResponseSchema,
} from './organizations';

// Account schemas (shared with V2/V3 public APIs)
import {
  accountResponseSchema,
  apiTokenResponseSchema,
  checkAuthResponseSchema,
  customerResponseSchema,
} from '@/schemas/api/v3/responses/account';

// Domain schemas (shared with V2/V3 public APIs)
import {
  brandSettingsResponseSchema,
  customDomainResponseSchema,
  customDomainListResponseSchema,
  imagePropsResponseSchema,
  jurisdictionResponseSchema,
} from '@/schemas/api/v3/responses/domains';

// Auth schemas (shared with V2/V3)
import {
  loginResponseSchema,
  createAccountResponseSchema,
  logoutResponseSchema,
  resetPasswordRequestResponseSchema,
  resetPasswordResponseSchema,
} from '@/schemas/api/v3/responses/auth';

// ─────────────────────────────────────────────────────────────────────────────
// Response schema registry
// ─────────────────────────────────────────────────────────────────────────────

/** Internal API response schemas. Keyed lookup for OpenAPI generation. */
export const responseSchemas = {
  // Account
  account: accountResponseSchema,
  apiToken: apiTokenResponseSchema,
  checkAuth: checkAuthResponseSchema,
  customer: customerResponseSchema,

  // Colonel / admin (internal-only)
  colonelInfo: colonelInfoResponseSchema,
  colonelStats: colonelStatsResponseSchema,
  colonelUsers: colonelUsersResponseSchema,
  colonelUserDetail: colonelUserDetailResponseSchema,
  colonelUserMutation: colonelUserMutationResponseSchema,
  colonelSecrets: colonelSecretsResponseSchema,
  colonelSecretReceipt: colonelSecretReceiptResponseSchema,
  colonelSecretDelete: colonelSecretDeleteResponseSchema,
  customDomains: colonelCustomDomainsResponseSchema,
  colonelDomainVerify: colonelDomainVerifyResponseSchema,
  colonelOrganizations: colonelOrganizationsResponseSchema,
  investigateOrganization: investigateOrganizationResponseSchema,
  colonelEntitlementOverride: colonelEntitlementOverrideResponseSchema,
  databaseMetrics: databaseMetricsResponseSchema,
  redisMetrics: redisMetricsResponseSchema,
  bannedIPs: bannedIPsResponseSchema,
  colonelBanIp: colonelBanIpResponseSchema,
  colonelUnbanIp: colonelUnbanIpResponseSchema,
  usageExport: usageExportResponseSchema,
  queueMetrics: queueMetricsResponseSchema,
  systemSettings: systemSettingsResponseSchema,

  // Colonel / admin — Phase-3 screens (tickets #40-45)
  colonelSessions: colonelSessionsResponseSchema,
  colonelSessionDetail: colonelSessionDetailResponseSchema,
  colonelSessionDelete: colonelSessionDeleteResponseSchema,
  colonelBanner: colonelBannerResponseSchema,
  colonelBannerSet: colonelBannerSetResponseSchema,
  colonelBannerClear: colonelBannerClearResponseSchema,
  colonelDlqList: colonelDlqListResponseSchema,
  colonelDlqMessages: colonelDlqMessagesResponseSchema,
  colonelDlqReplay: colonelDlqReplayResponseSchema,
  colonelDlqPurge: colonelDlqPurgeResponseSchema,
  colonelDomainsOrphaned: colonelDomainsOrphanedResponseSchema,
  colonelDomainProbe: colonelDomainProbeResponseSchema,
  colonelDomainRepair: colonelDomainRepairResponseSchema,
  colonelDomainTransfer: colonelDomainTransferResponseSchema,
  colonelEmailTemplates: colonelEmailTemplatesResponseSchema,
  colonelEmailPreview: colonelEmailPreviewResponseSchema,
  colonelEmailTest: colonelEmailTestResponseSchema,
  colonelRateLimiters: colonelRateLimitersResponseSchema,
  colonelRateLimitInspect: colonelRateLimitInspectResponseSchema,
  colonelRateLimitReset: colonelRateLimitResetResponseSchema,
  colonelBillingCatalog: colonelBillingCatalogResponseSchema,

  // Organizations (internal-only)
  organization: organizationResponseSchema,
  organizationList: organizationsResponseSchema,
  organizationDelete: orgDeleteResponseSchema,
  memberList: membersResponseSchema,
  member: memberResponseSchema,
  memberDelete: memberDeleteResponseSchema,

  // Domains / brand
  brandSettings: brandSettingsResponseSchema,
  customDomain: customDomainResponseSchema,
  customDomainList: customDomainListResponseSchema,
  imageProps: imagePropsResponseSchema,
  jurisdiction: jurisdictionResponseSchema,

  // Authentication
  // NOTE: These auth schemas are not referenced by any internal API routes
  // (auth routes live in apps/web/core/routes.txt). They are included here
  // because the Vue frontend (useAuth.ts) imports them for runtime Zod parsing.
  login: loginResponseSchema,
  createAccount: createAccountResponseSchema,
  logout: logoutResponseSchema,
  resetPasswordRequest: resetPasswordRequestResponseSchema,
  resetPassword: resetPasswordResponseSchema,
} as const;

// Alias for consistency with other registry exports
export const internalResponseSchemas = responseSchemas;

// ─────────────────────────────────────────────────────────────────────────────
// Mapped types
// ─────────────────────────────────────────────────────────────────────────────

export type ResponseTypes = {
  [K in keyof typeof responseSchemas]: z.infer<(typeof responseSchemas)[K]>;
};
