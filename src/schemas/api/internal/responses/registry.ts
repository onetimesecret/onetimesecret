// src/schemas/api/internal/responses/registry.ts
//
// Assembles response schemas for internal APIs (account, colonel, domains,
// organizations, invite). These are consumed by the Vue frontend, not
// exposed publicly.
//
// Separated from V2/V3 registries to keep public API schemas clean.

import { z } from 'zod';

// Colonel (admin) schemas
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
} from '@/schemas/api/v2/responses/colonel';

// Organization schemas
import {
  organizationResponseSchema,
  organizationsResponseSchema,
  orgDeleteResponseSchema,
  membersResponseSchema,
  memberResponseSchema,
  memberDeleteResponseSchema,
} from '@/schemas/api/v2/responses/organizations';

// Account schemas (shared with V2/V3 public APIs)
import {
  accountResponseSchema,
  apiTokenResponseSchema,
  checkAuthResponseSchema,
  customerResponseSchema,
} from '@/schemas/api/v2/responses/account';

// Domain schemas (shared with V2/V3 public APIs)
import {
  brandSettingsResponseSchema,
  customDomainResponseSchema,
  customDomainListResponseSchema,
  imagePropsResponseSchema,
  jurisdictionResponseSchema,
} from '@/schemas/api/v2/responses/domains';

// Auth schemas (shared with V2/V3)
import {
  loginResponseSchema,
  createAccountResponseSchema,
  logoutResponseSchema,
  resetPasswordRequestResponseSchema,
  resetPasswordResponseSchema,
} from '@/schemas/api/v2/responses/auth';

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
