// src/schemas/api/account/endpoints/colonel.ts

/**
 * Colonel (Admin) API Endpoint Schemas
 *
 * This file contains schemas for the colonel/admin API endpoints.
 * Config-related schemas are imported from @/schemas/config/config.ts
 */

import { feedbackSchema } from '@/schemas/models';
import { transforms } from '@/schemas/transforms';
import { z } from 'zod/v4';

// Import system settings schemas from config
import {
  systemSettingsSchema,
  systemSettingsDetailsSchema,
} from '@/schemas/config/config';

// Re-export for backward compatibility
export { systemSettingsSchema, systemSettingsDetailsSchema };
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
  secrets_created: transforms.fromString.number,
  secrets_shared: transforms.fromString.number,
  emails_sent: transforms.fromString.number,
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
  created: transforms.fromString.number,
  created_human: z.string(),
  last_login: transforms.fromString.number.nullable(),
  last_login_human: z.string(),
  planid: z.string().nullable(),
  secrets_count: z.number(),
  secrets_created: transforms.fromString.number,
  secrets_shared: transforms.fromString.number,
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
  created: transforms.fromString.number,
  created_human: z.string(),
  expiration: transforms.fromString.number.nullable(),
  expiration_human: z.string().nullable(),
  lifespan: transforms.fromString.number.nullable(),
  metadata_id: z.string().nullable(),
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
    metadata: z.number(),
  }),
});

/**
 * Redis metrics response details (full Redis INFO)
 */
export const redisMetricsDetailsSchema = z.object({
  redis_info: z.record(z.string(), z.string()),
  timestamp: z.number(),
  timestamp_human: z.string(),
});

/**
 * Banned IP record
 */
export const bannedIPSchema = z.object({
  id: z.string(),
  ip_address: z.string(),
  reason: z.string().nullable(),
  banned_by: z.string().nullable(),
  banned_at: transforms.fromString.number,
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
    start_date: z.number(),
    start_date_human: z.string(),
    end_date: z.number(),
    end_date_human: z.string(),
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
  created: z.number(),
  created_human: z.string(),
  updated: z.number().nullable(),
  updated_human: z.string(),
  org_id: z.string(),
  org_name: z.string(),
  brand: z.object({
    name: z.string().nullable(),
    tagline: z.string().nullable(),
    homepage_url: z.string().nullable(),
    allow_public_homepage: z.boolean(),
    allow_public_api: z.boolean(),
  }),
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
    customer_count: transforms.fromString.number,
    emails_sent: transforms.fromString.number,
    metadata_count: transforms.fromString.number,
    secret_count: transforms.fromString.number,
    secrets_created: transforms.fromString.number,
    secrets_shared: transforms.fromString.number,
    session_count: transforms.fromString.number,
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
    customer_count: transforms.fromString.number,
    emails_sent: transforms.fromString.number,
    feedback_count: transforms.fromString.number,
    metadata_count: transforms.fromString.number,
    older_feedback_count: transforms.fromString.number,
    recent_customer_count: transforms.fromString.number,
    secret_count: transforms.fromString.number,
    secrets_created: transforms.fromString.number,
    secrets_shared: transforms.fromString.number,
    session_count: transforms.fromString.number,
    today_feedback_count: transforms.fromString.number,
    yesterday_feedback_count: transforms.fromString.number,
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
  created: z.number(),
  created_human: z.string(),
  updated: z.number().nullable(),
  updated_human: z.string(),
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
