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
  backupStatusResponseSchema,
  brandDiagnosticsResponseSchema,
  colonelCheckoutLinkResponseSchema,
  colonelCustomDomainsResponseSchema,
  colonelInfoResponseSchema,
  colonelOrganizationsResponseSchema,
  colonelSecretsResponseSchema,
  colonelStatsResponseSchema,
  colonelUserDetailResponseSchema,
  colonelUserMutationResponseSchema,
  colonelUsersResponseSchema,
  databaseMetricsResponseSchema,
  investigateOrganizationResponseSchema,
  queueMetricsResponseSchema,
  redisMetricsResponseSchema,
  systemSettingsResponseSchema,
  usageExportResponseSchema,
} from './colonel';

// Colonel (admin) per-resource ack schemas — Phase-2 screens (tickets #30-33)
import {
  colonelDomainConfigDeleteResponseSchema,
  colonelDomainConfigsEnsureResponseSchema,
  colonelDomainConfigsResponseSchema,
  colonelDomainConfigUpsertResponseSchema,
} from './colonel-domain-configs';
import { colonelDomainVerifyResponseSchema } from './colonel-domains';
import {
  colonelDeleteOrganizationResponseSchema,
  colonelEntitlementOverrideResponseSchema,
  colonelMembershipEntitlementOverrideResponseSchema,
  colonelOrganizationDetailResponseSchema,
  colonelReconcileOrganizationResponseSchema,
  colonelTransferOrganizationOwnershipResponseSchema,
  colonelUpdateOrganizationPlanResponseSchema,
} from './colonel-organizations';
import {
  colonelSecretDeleteResponseSchema,
  colonelSecretReceiptResponseSchema,
} from './colonel-secrets';

// Colonel (admin) per-resource schemas — Phase-3 screens (tickets #40-45).
// The rate-limit inspect/reset UI was removed by design review; its envelopes
// stay registry-only as the OpenAPI contract for the still-live endpoints. The
// DLQ console, removed by the same review, returned inside the Jobs screen
// (#4343) alongside the scheduler read-out and chore triggers.
import { colonelAccountDiagnosticsResponseSchema } from './colonel-account-diagnostics';
import {
  colonelBannerClearResponseSchema,
  colonelBannerResponseSchema,
  colonelBannerSetResponseSchema,
} from './colonel-banner';
import {
  colonelBillingCatalogResponseSchema,
  colonelPendingFederatedSubscriptionsResponseSchema,
  colonelStripeOrganizationsResponseSchema,
  colonelWebhookEventDetailResponseSchema,
  colonelWebhookEventsResponseSchema,
} from './colonel-billing';
import {
  colonelCustomerSessionRevokeAllResponseSchema,
  colonelCustomerSessionRevokeResponseSchema,
  colonelCustomerSessionsResponseSchema,
} from './colonel-customer-sessions';
import {
  colonelEmailDeliverabilityEventsResponseSchema,
  colonelEmailDeliverabilityIngestResponseSchema,
  colonelEmailDeliverabilityResponseSchema,
  colonelEmailDeliverabilitySyncResponseSchema,
  colonelEmailMessagesResponseSchema,
  colonelEmailProviderStatusResponseSchema,
  colonelEmailRecipientLookupResponseSchema,
  colonelEmailSuppressionAddResponseSchema,
  colonelEmailSuppressionRemoveResponseSchema,
  colonelEmailSuppressionsResponseSchema,
} from './colonel-deliverability';
import {
  colonelDomainProbeResponseSchema,
  colonelDomainRepairResponseSchema,
  colonelDomainsOrphanedResponseSchema,
  colonelDomainTransferResponseSchema,
} from './colonel-domaintoolbox';
import {
  colonelEmailConfigResponseSchema,
  colonelEmailPreviewResponseSchema,
  colonelEmailTemplatesResponseSchema,
  colonelEmailTestResponseSchema,
  colonelRateLimitersResponseSchema,
  colonelRateLimitInspectResponseSchema,
  colonelRateLimitResetResponseSchema,
} from './colonel-emailtools';
import {
  colonelChoreRunResponseSchema,
  colonelChoresResponseSchema,
  colonelJobsResponseSchema,
} from './colonel-jobs';
import {
  colonelDlqListResponseSchema,
  colonelDlqMessageDetailResponseSchema,
  colonelDlqMessageDiscardResponseSchema,
  colonelDlqMessageReplayResponseSchema,
  colonelDlqMessagesResponseSchema,
  colonelDlqPurgeResponseSchema,
  colonelDlqReplayResponseSchema,
} from './colonel-queue';
import {
  colonelSessionDeleteResponseSchema,
  colonelSessionDetailResponseSchema,
  colonelSessionsResponseSchema,
} from './colonel-sessions';

// Colonel (admin) observability — audit trail reader + overview trends
import { colonelAuditEventsResponseSchema } from './colonel-audit';
import { colonelTrendsResponseSchema } from './colonel-trends';

// Organization schemas — internal-only
import {
  memberDeleteResponseSchema,
  memberResponseSchema,
  membersResponseSchema,
  organizationResponseSchema,
  organizationsResponseSchema,
  orgDeleteResponseSchema,
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
  customDomainListResponseSchema,
  customDomainResponseSchema,
  imagePropsResponseSchema,
  jurisdictionResponseSchema,
} from '@/schemas/api/v3/responses/domains';

// Auth schemas (shared with V2/V3)
import {
  createAccountResponseSchema,
  loginResponseSchema,
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
  colonelCheckoutLink: colonelCheckoutLinkResponseSchema,
  colonelSecrets: colonelSecretsResponseSchema,
  colonelSecretReceipt: colonelSecretReceiptResponseSchema,
  colonelSecretDelete: colonelSecretDeleteResponseSchema,
  customDomains: colonelCustomDomainsResponseSchema,
  colonelDomainVerify: colonelDomainVerifyResponseSchema,
  colonelDomainConfigs: colonelDomainConfigsResponseSchema,
  colonelDomainConfigUpsert: colonelDomainConfigUpsertResponseSchema,
  colonelDomainConfigDelete: colonelDomainConfigDeleteResponseSchema,
  colonelDomainConfigsEnsure: colonelDomainConfigsEnsureResponseSchema,
  colonelOrganizations: colonelOrganizationsResponseSchema,
  colonelOrganizationDetail: colonelOrganizationDetailResponseSchema,
  investigateOrganization: investigateOrganizationResponseSchema,
  colonelReconcileOrganization: colonelReconcileOrganizationResponseSchema,
  colonelTransferOrganizationOwnership: colonelTransferOrganizationOwnershipResponseSchema,
  colonelUpdateOrganizationPlan: colonelUpdateOrganizationPlanResponseSchema,
  colonelDeleteOrganization: colonelDeleteOrganizationResponseSchema,
  colonelEntitlementOverride: colonelEntitlementOverrideResponseSchema,
  colonelMembershipEntitlementOverride: colonelMembershipEntitlementOverrideResponseSchema,
  databaseMetrics: databaseMetricsResponseSchema,
  backupStatus: backupStatusResponseSchema,
  brandDiagnostics: brandDiagnosticsResponseSchema,
  redisMetrics: redisMetricsResponseSchema,
  usageExport: usageExportResponseSchema,
  queueMetrics: queueMetricsResponseSchema,
  systemSettings: systemSettingsResponseSchema,

  // Colonel / admin — Phase-3 screens (tickets #40-45)
  colonelSessions: colonelSessionsResponseSchema,
  colonelSessionDetail: colonelSessionDetailResponseSchema,
  colonelSessionDelete: colonelSessionDeleteResponseSchema,
  colonelCustomerSessions: colonelCustomerSessionsResponseSchema,
  colonelCustomerSessionRevoke: colonelCustomerSessionRevokeResponseSchema,
  colonelCustomerSessionRevokeAll: colonelCustomerSessionRevokeAllResponseSchema,
  colonelAccountDiagnostics: colonelAccountDiagnosticsResponseSchema,
  colonelBanner: colonelBannerResponseSchema,
  colonelBannerSet: colonelBannerSetResponseSchema,
  colonelBannerClear: colonelBannerClearResponseSchema,
  colonelDlqList: colonelDlqListResponseSchema,
  colonelDlqMessages: colonelDlqMessagesResponseSchema,
  colonelDlqReplay: colonelDlqReplayResponseSchema,
  colonelDlqPurge: colonelDlqPurgeResponseSchema,
  // #4343 jobs operability: per-message DLQ ops, scheduler read-out, chores
  colonelDlqMessageDetail: colonelDlqMessageDetailResponseSchema,
  colonelDlqMessageReplay: colonelDlqMessageReplayResponseSchema,
  colonelDlqMessageDiscard: colonelDlqMessageDiscardResponseSchema,
  colonelJobs: colonelJobsResponseSchema,
  colonelChores: colonelChoresResponseSchema,
  colonelChoreRun: colonelChoreRunResponseSchema,
  colonelDomainsOrphaned: colonelDomainsOrphanedResponseSchema,
  colonelDomainProbe: colonelDomainProbeResponseSchema,
  colonelDomainRepair: colonelDomainRepairResponseSchema,
  colonelDomainTransfer: colonelDomainTransferResponseSchema,
  colonelEmailConfig: colonelEmailConfigResponseSchema,
  colonelEmailTemplates: colonelEmailTemplatesResponseSchema,
  colonelEmailPreview: colonelEmailPreviewResponseSchema,
  colonelEmailTest: colonelEmailTestResponseSchema,
  colonelRateLimiters: colonelRateLimitersResponseSchema,
  colonelRateLimitInspect: colonelRateLimitInspectResponseSchema,
  colonelRateLimitReset: colonelRateLimitResetResponseSchema,
  colonelEmailDeliverability: colonelEmailDeliverabilityResponseSchema,
  colonelEmailSuppressions: colonelEmailSuppressionsResponseSchema,
  colonelEmailSuppressionRemove: colonelEmailSuppressionRemoveResponseSchema,
  colonelEmailSuppressionAdd: colonelEmailSuppressionAddResponseSchema,
  colonelEmailDeliverabilityEvents: colonelEmailDeliverabilityEventsResponseSchema,
  colonelEmailDeliverabilityIngest: colonelEmailDeliverabilityIngestResponseSchema,
  colonelEmailDeliverabilitySync: colonelEmailDeliverabilitySyncResponseSchema,
  colonelEmailProviderStatus: colonelEmailProviderStatusResponseSchema,
  colonelEmailRecipientLookup: colonelEmailRecipientLookupResponseSchema,
  colonelEmailMessages: colonelEmailMessagesResponseSchema,
  colonelBillingCatalog: colonelBillingCatalogResponseSchema,
  colonelStripeOrganizations: colonelStripeOrganizationsResponseSchema,
  colonelWebhookEvents: colonelWebhookEventsResponseSchema,
  colonelWebhookEventDetail: colonelWebhookEventDetailResponseSchema,
  colonelPendingFederatedSubscriptions: colonelPendingFederatedSubscriptionsResponseSchema,

  // Colonel / admin — observability (audit reader + trends)
  colonelAuditEvents: colonelAuditEventsResponseSchema,
  colonelTrends: colonelTrendsResponseSchema,

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
