// src/schemas/api/internal/responses/colonel.ts

/**
 * Colonel (Admin) API Endpoint Schemas
 *
 * This file contains schemas for the colonel/admin API endpoints.
 * Config-related schemas are imported from @/schemas/contracts/config/config.ts
 */

import { feedbackSchema } from '@/schemas/shapes/v3/feedback';
import { transforms } from '@/schemas/transforms';
import { createApiResponseSchema } from '@/schemas/api/base';
import { z } from 'zod';

// Import system settings schemas from config
import {
  systemSettingsDetailsSchema,
  systemSettingsSchema,
} from '@/schemas/contracts/config/config';

// Re-export for backward compatibility
export { systemSettingsDetailsSchema, systemSettingsSchema };
// SystemSettingsDetails type already exported from config/config.ts

// ============================================================================
// Colonel API Response Schemas
// ============================================================================

/**
 * An abridged customer record used in the recent list.
 */
export const recentCustomerSchema = z.object({
  custid: z.string(), // Not always an email address (e.g. GLOBAL for new installs)
  colonel: z.boolean(),
  secrets_created: z.number(),
  secrets_shared: z.number(),
  emails_sent: z.number(),
  verified: z.boolean(),
  stamp: z.string(),
});

/**
 * Full user record from /api/colonel/users endpoint
 */
export const colonelUserSchema = z.object({
  user_id: z.string(),
  extid: z.string(),
  email: z.string(),
  role: z.string(),
  verified: z.boolean(),
  // Reversible trust & safety pause (customer-support features). Optional
  // with a default so pre-suspension payloads/fixtures keep parsing.
  suspended: z.boolean().optional().default(false),
  created: transforms.fromNumber.toDate,
  last_login: transforms.fromNumber.toDateNullable,
  planid: z.string().nullable(),
  secrets_count: z.number(),
  secrets_created: z.number(),
  secrets_shared: z.number(),
});

/**
 * Pagination metadata for list endpoints
 */
export const paginationSchema = z.object({
  page: z.number(),
  per_page: z.number(),
  total_count: z.number(),
  total_pages: z.number(),
  role_filter: z.string().nullable().optional(),
  /** Server echo of the email search term (users list). */
  search: z.string().nullable().optional(),
});

/**
 * Users list response details
 */
export const colonelUsersDetailsSchema = z.object({
  users: z.array(colonelUserSchema),
  pagination: paginationSchema,
});

/**
 * Secret record from /api/colonel/secrets endpoint
 */
export const colonelSecretSchema = z.object({
  secret_id: z.string(),
  shortid: z.string(),
  owner_id: z.string().nullable(),
  state: z.string(),
  created: transforms.fromNumber.toDate,
  expiration: transforms.fromNumber.toDateNullable,
  lifespan: z.number().nullable(),
  receipt_id: z.string().nullable(),
  age: z.number(),
  has_ciphertext: z.boolean(),
});

/**
 * Secrets list response details
 */
export const colonelSecretsDetailsSchema = z.object({
  secrets: z.array(colonelSecretSchema),
  pagination: paginationSchema,
});

/**
 * Database metrics response details
 */
export const databaseMetricsDetailsSchema = z.object({
  redis_info: z.object({
    redis_version: z.string(),
    valkey_version: z.string().nullish(),
    server_name: z.string().nullish(),
    redis_mode: z.string().nullable(),
    os: z.string(),
    uptime_in_seconds: z.number(),
    uptime_in_days: z.number(),
    connected_clients: z.number(),
    total_commands_processed: z.number(),
    instantaneous_ops_per_sec: z.number(),
  }),
  database_sizes: z.record(
    z.string(),
    z.union([
      z.object({
        keys: z.number(),
        expires: z.number(),
        avg_ttl: z.number(),
      }),
      z.string(), // Sometimes Redis INFO returns string format
    ])
  ),
  total_keys: z.number(),
  memory_stats: z.object({
    used_memory: z.number(),
    used_memory_human: z.string(),
    used_memory_rss: z.number(),
    used_memory_rss_human: z.string(),
    used_memory_peak: z.number(),
    used_memory_peak_human: z.string(),
    mem_fragmentation_ratio: z.number(),
  }),
  model_counts: z.object({
    customers: z.number(),
    secrets: z.number(),
    receipts: z.number(),
  }),
});

/**
 * Redis metrics response details (full Redis INFO)
 */
export const redisMetricsDetailsSchema = z.object({
  redis_info: z.record(z.string(), z.string()),
  timestamp: transforms.fromNumber.toDate,
});

/**
 * Banned IP record
 */
export const bannedIPSchema = z.object({
  id: z.string(),
  ip_address: z.string(),
  reason: z.string().nullable(),
  banned_by: z.string().nullable(),
  banned_at: z.number(),
});

/**
 * Banned IPs list response details
 */
export const bannedIPsDetailsSchema = z.object({
  current_ip: z.string().default('unknown'),
  banned_ips: z.array(bannedIPSchema),
  total_count: z.number(),
});

/**
 * Usage export response details
 */
export const usageExportDetailsSchema = z.object({
  date_range: z.object({
    start_date: transforms.fromNumber.toDate,
    end_date: transforms.fromNumber.toDate,
    days: z.number(),
  }),
  usage_data: z.object({
    total_secrets: z.number(),
    total_new_users: z.number(),
    secrets_by_state: z.record(z.string(), z.number()),
    avg_secrets_per_day: z.number(),
    avg_users_per_day: z.number(),
  }),
  secrets_by_day: z.record(z.string(), z.number()),
  users_by_day: z.record(z.string(), z.number()),
});

/**
 * Custom domain schema for colonel/admin API
 * (Different from models/domain customDomainSchema - this is the admin list view)
 */
export const colonelCustomDomainSchema = z.object({
  domain_id: z.string(),
  extid: z.string(),
  display_domain: z.string(),
  base_domain: z.string(),
  subdomain: z.string(),
  status: z.string().nullable(),
  verified: z.boolean(),
  resolving: z.boolean(),
  verification_state: z.string(),
  ready: z.boolean(),
  created: transforms.fromNumber.toDate,
  updated: transforms.fromNumber.toDateNullable,
  org_id: z.string(),
  org_name: z.string(),
  brand: z.object({
    name: z.string().nullable(),
    tagline: z.string().nullable(),
    homepage_url: z.string().nullable(),
  }),
  // Per-domain feature toggles emitted as their own blocks (#3026); both are
  // nullable so the admin list can still render when a HomepageConfig /
  // ApiConfig record is missing (data drift surfaces as a null block rather
  // than a crashed list).
  homepage_config: z
    .object({
      domain_id: z.string(),
      enabled: z.boolean(),
      /** Which experience the enabled homepage presents ('create' | 'incoming'). */
      secrets_mode: z.string().optional(),
      created_at: z.number().nullable(),
      updated_at: z.number().nullable(),
    })
    .nullable(),
  api_config: z
    .object({
      domain_id: z.string(),
      enabled: z.boolean(),
      created_at: z.number().nullable(),
      updated_at: z.number().nullable(),
    })
    .nullable(),
  has_logo: z.boolean(),
  has_icon: z.boolean(),
  logo_url: z.string().nullable(),
  icon_url: z.string().nullable(),
});

export const colonelCustomDomainsDetailsSchema = z.object({
  domains: z.array(colonelCustomDomainSchema),
  pagination: paginationSchema,
});

/**
 * Lightweight stats schema for dashboard display
 */
export const colonelStatsDetailsSchema = z.object({
  counts: z.object({
    customer_count: z.number(),
    emails_sent: z.number(),
    receipt_count: z.number(),
    secret_count: z.number(),
    secrets_created: z.number(),
    secrets_shared: z.number(),
    session_count: z.number(),
  }),
});

export const colonelInfoDetailsSchema = z.object({
  recent_customers: z.array(recentCustomerSchema).default([]),
  today_feedback: z.array(feedbackSchema).default([]),
  yesterday_feedback: z.array(feedbackSchema).default([]),
  older_feedback: z.array(feedbackSchema).nullable().default(null),
  dbclient_info: z.string().optional().default(''),
  billing_enabled: z.boolean().optional().default(false),
  counts: z.object({
    customer_count: z.number(),
    emails_sent: z.number(),
    feedback_count: z.number(),
    receipt_count: z.number(),
    older_feedback_count: z.number(),
    recent_customer_count: z.number(),
    secret_count: z.number(),
    secrets_created: z.number(),
    secrets_shared: z.number(),
    session_count: z.number(),
    today_feedback_count: z.number(),
    yesterday_feedback_count: z.number(),
  }),
});

// ============================================================================
// Type Exports
// ============================================================================

export type ColonelStatsDetails = z.infer<typeof colonelStatsDetailsSchema>;
export type ColonelInfoDetails = z.infer<typeof colonelInfoDetailsSchema>;
export type RecentCustomer = z.infer<typeof recentCustomerSchema>;
export type ColonelUser = z.infer<typeof colonelUserSchema>;
export type ColonelUsersDetails = z.infer<typeof colonelUsersDetailsSchema>;
export type Pagination = z.infer<typeof paginationSchema>;
export type ColonelSecret = z.infer<typeof colonelSecretSchema>;
export type ColonelSecretsDetails = z.infer<typeof colonelSecretsDetailsSchema>;
export type DatabaseMetricsDetails = z.infer<typeof databaseMetricsDetailsSchema>;
export type RedisMetricsDetails = z.infer<typeof redisMetricsDetailsSchema>;
export type BannedIP = z.infer<typeof bannedIPSchema>;
export type BannedIPsDetails = z.infer<typeof bannedIPsDetailsSchema>;
export type UsageExportDetails = z.infer<typeof usageExportDetailsSchema>;
export type ColonelCustomDomain = z.infer<typeof colonelCustomDomainSchema>;
export type ColonelCustomDomainsDetails = z.infer<typeof colonelCustomDomainsDetailsSchema>;

/**
 * Queue metrics schema
 */
export const queueMetricSchema = z.object({
  name: z.string(),
  pending_messages: z.number(),
  consumers: z.number(),
  rate: z.number().optional(),
});

export const queueMetricsDetailsSchema = z.object({
  connection: z.object({
    connected: z.boolean(),
    host: z.string().optional(),
  }),
  worker_health: z.object({
    status: z.enum(['healthy', 'degraded', 'unhealthy', 'unknown']),
    active_workers: z.number().optional(),
  }),
  queues: z.array(queueMetricSchema),
});

export type QueueMetric = z.infer<typeof queueMetricSchema>;
export type QueueMetrics = z.infer<typeof queueMetricsDetailsSchema>;

/**
 * Organization schema for colonel/admin API
 * Includes billing sync health detection for admin monitoring
 */
export const colonelOrganizationSchema = z.object({
  org_id: z.string(),
  extid: z.string(),
  display_name: z.string().nullable(),
  contact_email: z.string().nullable(),
  owner_id: z.string().nullable(),
  owner_email: z.string().nullable(),
  member_count: z.number(),
  domain_count: z.number(),
  is_default: z.boolean(),
  created: transforms.fromNumber.toDate,
  updated: transforms.fromNumber.toDateNullable,
  // Billing fields
  planid: z.string().nullable(),
  stripe_customer_id: z.string().nullable(),
  stripe_subscription_id: z.string().nullable(),
  subscription_status: z.string().nullable(),
  subscription_period_end: z.string().nullable(),
  billing_email: z.string().nullable(),
  // Sync health detection
  sync_status: z.enum(['synced', 'potentially_stale', 'unknown']),
  sync_status_reason: z.string().nullable(),
});

/**
 * Organizations filters schema
 */
export const colonelOrganizationsFiltersSchema = z.object({
  status: z.string().nullable(),
  sync_status: z.string().nullable(),
});

/**
 * Organizations list response details
 */
export const colonelOrganizationsDetailsSchema = z.object({
  organizations: z.array(colonelOrganizationSchema),
  pagination: paginationSchema,
  filters: colonelOrganizationsFiltersSchema,
});

export type ColonelOrganization = z.infer<typeof colonelOrganizationSchema>;
export type ColonelOrganizationsDetails = z.infer<typeof colonelOrganizationsDetailsSchema>;
export type ColonelOrganizationsFilters = z.infer<typeof colonelOrganizationsFiltersSchema>;

/**
 * Organization billing investigation - local state
 */
export const investigateLocalStateSchema = z.object({
  planid: z.string().nullable(),
  stripe_customer_id: z.string().nullable(),
  stripe_subscription_id: z.string().nullable(),
  subscription_status: z.string().nullable(),
  subscription_period_end: z.string().nullable(),
});

/**
 * Organization billing investigation - Stripe subscription data
 */
export const investigateStripeSubscriptionSchema = z.object({
  id: z.string(),
  status: z.string(),
  current_period_end: z.number().nullable(),
  price_id: z.string().nullable(),
  price_nickname: z.string().nullable(),
  product_id: z.string().nullable(),
  product_name: z.string().nullable(),
  subscription_metadata_plan_id: z.string().nullable(),
  price_metadata_plan_id: z.string().nullable(),
  resolved_plan_id: z.string().nullable(),
});

/**
 * Organization billing investigation - Stripe state
 */
export const investigateStripeStateSchema = z.object({
  available: z.boolean(),
  reason: z.string().nullable(),
  subscription: investigateStripeSubscriptionSchema.nullable(),
});

/**
 * Organization billing investigation - comparison issue
 */
export const investigateIssueSchema = z.object({
  field: z.string(),
  local: z.string(),
  stripe: z.string(),
  severity: z.enum(['critical', 'high', 'medium', 'low']),
});

/**
 * Organization billing investigation - comparison result
 */
export const investigateComparisonSchema = z.object({
  match: z.boolean().nullable(),
  verdict: z.enum(['synced', 'mismatch_detected', 'unable_to_compare']),
  details: z.string().optional(),
  issues: z.array(investigateIssueSchema).optional(),
});

/**
 * Organization billing investigation result
 */
export const investigateOrganizationResultSchema = z.object({
  org_id: z.string(),
  extid: z.string(),
  investigated_at: z.string(),
  local: investigateLocalStateSchema,
  stripe: investigateStripeStateSchema,
  comparison: investigateComparisonSchema,
});

export type InvestigateLocalState = z.infer<typeof investigateLocalStateSchema>;
export type InvestigateStripeSubscription = z.infer<typeof investigateStripeSubscriptionSchema>;
export type InvestigateStripeState = z.infer<typeof investigateStripeStateSchema>;
export type InvestigateIssue = z.infer<typeof investigateIssueSchema>;
export type InvestigateComparison = z.infer<typeof investigateComparisonSchema>;
export type InvestigateOrganizationResult = z.infer<typeof investigateOrganizationResultSchema>;

// ============================================================================
// Colonel customer DETAIL + mutation schemas (ticket #22)
//
// New schemas only — the existing colonel contracts above are frozen (the Zod
// tripwire, epic non-goal). These describe the SHAPE the Slice-2 endpoints
// already return; verified against the live logic classes:
//   - GetUserDetails         → GET    /api/colonel/users/:user_id
//   - SetUserRole            → POST   /api/colonel/users/:user_id/role
//   - Verify / UnverifyUser  → POST   /api/colonel/users/:user_id/{,un}verify
//   - PurgeUser              → DELETE /api/colonel/users/:user_id
// ============================================================================

/**
 * The core customer record on the detail page (GetUserDetails `record`).
 * `email` is the OBSCURED email (`obscure_email`); never the raw address.
 * Timestamps arrive as Unix-epoch numbers (seconds, sometimes fractional) and
 * are transformed to Date, mirroring {@link colonelUserSchema}.
 */
export const colonelUserDetailRecordSchema = z.object({
  extid: z.string(),
  email: z.string(),
  role: z.string(),
  verified: z.boolean(),
  // Reversible trust & safety pause. All four fields are optional so
  // pre-suspension payloads keep parsing; the *_at/_by/_reason trio is
  // nil server-side whenever the account is not suspended.
  suspended: z.boolean().optional().default(false),
  suspended_at: transforms.fromNumber.toDateNullable.optional(),
  suspended_by: z.string().nullable().optional(),
  suspended_reason: z.string().nullable().optional(),
  created: transforms.fromNumber.toDate,
  updated: transforms.fromNumber.toDateNullable,
  last_login: transforms.fromNumber.toDateNullable,
  planid: z.string().nullable(),
  locale: z.string().nullable(),
});

/** One secret owned by the customer (GetUserDetails `details.secrets.items`). */
export const colonelUserDetailSecretSchema = z.object({
  secret_id: z.string(),
  shortid: z.string(),
  state: z.string(),
  created: transforms.fromNumber.toDate,
  expiration: transforms.fromNumber.toDateNullable,
});

/** One receipt owned by the customer (GetUserDetails `details.receipts.items`). */
export const colonelUserDetailReceiptSchema = z.object({
  receipt_id: z.string(),
  shortid: z.string(),
  state: z.string(),
  created: transforms.fromNumber.toDate,
});

/** One organization the customer participates in. */
export const colonelUserDetailOrganizationSchema = z.object({
  organization_id: z.string(),
  extid: z.string(),
  display_name: z.string().nullable(),
  is_default: z.boolean(),
});

/** Lifetime counters coerced to Integer server-side (never opaque Counters). */
export const colonelUserDetailStatsSchema = z.object({
  secrets_created: z.number(),
  secrets_shared: z.number(),
  emails_sent: z.number(),
});

/**
 * Live Stripe read-out on the customer detail page. `available: false` is the
 * graceful-degradation shape (billing disabled, no Stripe identity, or Stripe
 * unreachable) — the server NEVER fails the detail page over Stripe; it
 * degrades to this with a human-readable `reason`.
 */
export const colonelUserBillingStripeSchema = z.object({
  available: z.boolean(),
  reason: z.string().nullable(),
  customer_id: z.string().nullable(),
  /** Deep link to the customer in the Stripe dashboard (mode-aware). */
  dashboard_url: z.string().nullable(),
  subscription: z
    .object({
      id: z.string(),
      status: z.string(),
      current_period_end: z.number().nullable(),
    })
    .nullable(),
  latest_invoice: z
    .object({
      id: z.string().nullable(),
      number: z.string().nullable(),
      status: z.string().nullable(),
      currency: z.string().nullable(),
      /** Smallest currency unit (e.g. cents). */
      total: z.number().nullable(),
      created: transforms.fromNumber.toDateNullable,
      hosted_invoice_url: z.string().nullable(),
    })
    .nullable(),
});

/**
 * Billing summary on the customer detail page ("why was I charged" support).
 * `plan_id` comes from the customer model so the card renders even when every
 * Stripe path degrades; `organization` is the customer's billing org (Stripe
 * identifiers live on Organization, not Customer).
 */
export const colonelUserBillingSchema = z.object({
  enabled: z.boolean(),
  plan_id: z.string().nullable(),
  organization: z
    .object({
      extid: z.string(),
      display_name: z.string().nullable(),
      planid: z.string().nullable(),
      subscription_status: z.string().nullable(),
      /** Unix timestamp stored as a string on Organization; may be empty. */
      subscription_period_end: z.string().nullable(),
    })
    .nullable(),
  stripe: colonelUserBillingStripeSchema,
});

/**
 * The `details` payload of GetUserDetails: everything a support agent needs to
 * read out a customer without SSH — secrets (count + items), receipts, orgs,
 * billing and lifetime stats. `count` is authoritative and equals
 * `items.length` (the endpoint sources it from the same bounded SCAN, not the
 * drifting counter). `billing` is optional so pre-billing payloads keep parsing.
 */
export const colonelUserDetailsSchema = z.object({
  secrets: z.object({
    count: z.number(),
    items: z.array(colonelUserDetailSecretSchema),
  }),
  receipts: z.object({
    count: z.number(),
    items: z.array(colonelUserDetailReceiptSchema),
  }),
  organizations: z.array(colonelUserDetailOrganizationSchema),
  billing: colonelUserBillingSchema.optional(),
  stats: colonelUserDetailStatsSchema,
});

/**
 * Shared mutation-ack record for the guarded customer actions. The endpoints
 * return structurally different records, so the fields that only SOME emit are
 * optional — this one schema validates every ack:
 *   - set-role  → old_role, new_role, email, updated
 *   - set-plan  → old_planid, new_planid, email, updated
 *   - verify/unverify → verified, email, updated
 *   - suspend/unsuspend → suspended, email, updated
 *   - purge     → deleted (email/updated omitted)
 *
 * `user_id` here is the customer's OBJID (server-internal); the UI keys off
 * `extid` (the public id) and refreshes the resource rather than trusting the
 * ack, so the differing `user_id` semantics never leak into routing.
 */
export const colonelUserMutationRecordSchema = z.object({
  user_id: z.string(),
  extid: z.string(),
  email: z.string().optional(),
  old_role: z.string().optional(),
  new_role: z.string().optional(),
  old_planid: z.string().nullable().optional(),
  new_planid: z.string().nullable().optional(),
  verified: z.boolean().optional(),
  suspended: z.boolean().optional(),
  deleted: z.boolean().optional(),
  updated: transforms.fromNumber.toDateNullable.optional(),
});

/** Shared `details` ack: `changed` present on toggles, absent on purge. */
export const colonelUserMutationDetailsSchema = z.object({
  changed: z.boolean().optional(),
  /** Suspend only: how many readable sessions the sweep revoked. */
  sessions_revoked: z.number().optional(),
  message: z.string(),
});

export type ColonelUserDetailRecord = z.infer<typeof colonelUserDetailRecordSchema>;
export type ColonelUserDetailSecret = z.infer<typeof colonelUserDetailSecretSchema>;
export type ColonelUserDetailReceipt = z.infer<typeof colonelUserDetailReceiptSchema>;
export type ColonelUserDetailOrganization = z.infer<typeof colonelUserDetailOrganizationSchema>;
export type ColonelUserDetailStats = z.infer<typeof colonelUserDetailStatsSchema>;
export type ColonelUserBillingStripe = z.infer<typeof colonelUserBillingStripeSchema>;
export type ColonelUserBilling = z.infer<typeof colonelUserBillingSchema>;
export type ColonelUserDetails = z.infer<typeof colonelUserDetailsSchema>;
export type ColonelUserMutationRecord = z.infer<typeof colonelUserMutationRecordSchema>;
export type ColonelUserMutationDetails = z.infer<typeof colonelUserMutationDetailsSchema>;

// ---- Available plans (GET /api/colonel/available-plans) --------------------
// NOTE: this endpoint (ColonelAPI::Logic::Colonel::GetAvailablePlans) returns a
// BARE `{ plans, source }` body — it overrides `process` directly instead of
// `success_data`, so there is NO `{ record, details }` envelope. Do NOT wrap
// this in createApiResponseSchema. The customer-detail plan selector and the
// entitlement-preview modal both read `response.data.plans` / `.source`.

/** One selectable plan. Only the fields the admin UI consumes are required. */
export const colonelAvailablePlanSchema = z.object({
  planid: z.string(),
  name: z.string(),
  tier: z.string().nullable().optional(),
  display_order: z.number().optional(),
  show_on_plans_page: z.boolean().optional(),
});

/**
 * Bare available-plans payload. `source` flags whether plans came from the
 * Stripe-synced cache or the local billing.yaml fallback (dev / no Stripe) —
 * the UI warns on `local_config` per the endpoint's own guidance.
 */
export const colonelAvailablePlansResponseSchema = z.object({
  plans: z.array(colonelAvailablePlanSchema),
  source: z.enum(['stripe', 'local_config']),
});

export type ColonelAvailablePlan = z.infer<typeof colonelAvailablePlanSchema>;
export type ColonelAvailablePlansResponse = z.infer<
  typeof colonelAvailablePlansResponseSchema
>;

// ============================================================================
// Wrapped response envelopes ({ record, details } across the API envelope).
// Registry keys for OpenAPI/JSON-Schema generation live in ./registry.ts.
// ============================================================================

export const colonelInfoResponseSchema = createApiResponseSchema(
  z.object({}),
  colonelInfoDetailsSchema
);
export const colonelStatsResponseSchema = createApiResponseSchema(
  z.object({}),
  colonelStatsDetailsSchema
);
export const colonelUsersResponseSchema = createApiResponseSchema(
  z.object({}),
  colonelUsersDetailsSchema
);
export const colonelSecretsResponseSchema = createApiResponseSchema(
  z.object({}),
  colonelSecretsDetailsSchema
);
export const colonelCustomDomainsResponseSchema = createApiResponseSchema(
  z.object({}),
  colonelCustomDomainsDetailsSchema
);
export const colonelOrganizationsResponseSchema = createApiResponseSchema(
  z.object({}),
  colonelOrganizationsDetailsSchema
);
export const investigateOrganizationResponseSchema = createApiResponseSchema(
  investigateOrganizationResultSchema
);
export const databaseMetricsResponseSchema = createApiResponseSchema(
  z.object({}),
  databaseMetricsDetailsSchema
);
export const redisMetricsResponseSchema = createApiResponseSchema(
  z.object({}),
  redisMetricsDetailsSchema
);
export const bannedIPsResponseSchema = createApiResponseSchema(
  z.object({}),
  bannedIPsDetailsSchema
);
export const usageExportResponseSchema = createApiResponseSchema(
  z.object({}),
  usageExportDetailsSchema
);
export const queueMetricsResponseSchema = createApiResponseSchema(
  z.object({}),
  queueMetricsDetailsSchema
);
export const systemSettingsResponseSchema = createApiResponseSchema(
  z.object({}),
  systemSettingsDetailsSchema
);

// Customer detail + guarded-mutation acks (ticket #22). Single-record envelopes
// (`{ record, details }`) — the customers detail view + guarded action buttons.
export const colonelUserDetailResponseSchema = createApiResponseSchema(
  colonelUserDetailRecordSchema,
  colonelUserDetailsSchema
);
export const colonelUserMutationResponseSchema = createApiResponseSchema(
  colonelUserMutationRecordSchema,
  colonelUserMutationDetailsSchema
);

export type ColonelInfoResponse = z.infer<typeof colonelInfoResponseSchema>;
export type ColonelStatsResponse = z.infer<typeof colonelStatsResponseSchema>;
export type ColonelUsersResponse = z.infer<typeof colonelUsersResponseSchema>;
export type ColonelSecretsResponse = z.infer<typeof colonelSecretsResponseSchema>;
export type CustomDomainsResponse = z.infer<typeof colonelCustomDomainsResponseSchema>;
export type ColonelOrganizationsResponse = z.infer<typeof colonelOrganizationsResponseSchema>;
export type InvestigateOrganizationResponse = z.infer<typeof investigateOrganizationResponseSchema>;
export type DatabaseMetricsResponse = z.infer<typeof databaseMetricsResponseSchema>;
export type RedisMetricsResponse = z.infer<typeof redisMetricsResponseSchema>;
export type BannedIPsResponse = z.infer<typeof bannedIPsResponseSchema>;
export type UsageExportResponse = z.infer<typeof usageExportResponseSchema>;
export type QueueMetricsResponse = z.infer<typeof queueMetricsResponseSchema>;
export type SystemSettingsResponse = z.infer<typeof systemSettingsResponseSchema>;
export type ColonelUserDetailResponse = z.infer<typeof colonelUserDetailResponseSchema>;
export type ColonelUserMutationResponse = z.infer<typeof colonelUserMutationResponseSchema>;
