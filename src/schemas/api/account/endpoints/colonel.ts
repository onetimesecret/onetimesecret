// src/schemas/api/endpoints/colonel.ts

import { feedbackSchema } from '@/schemas/models';
import { transforms } from '@/schemas/transforms';
import { z } from 'zod';

// Common types
// More flexible type validation that can handle missing values
const booleanOrString = z.union([z.boolean(), z.string()]).optional();
const numberOrString = z.union([z.string(), z.number()]).optional();

const interfaceSchema = z.object({
  ui: z
    .object({
      enabled: booleanOrString.optional(),
      header: z
        .object({
          enabled: booleanOrString.optional(),
          branding: z
            .object({
              logo: z
                .object({
                  url: z.string().optional(),
                  alt: z.string().optional(),
                  link_to: z.string().optional(),
                })
                .optional(),
              site_name: z.string().optional(),
            })
            .optional(),
          navigation: z
            .object({
              enabled: booleanOrString.optional(),
            })
            .optional(),
        })
        .optional(),
      footer_links: z
        .object({
          enabled: booleanOrString.optional(),
          groups: z
            .array(
              z.object({
                name: z.string().optional(),
                i18n_key: z.string().optional(),
                links: z
                  .array(
                    z.object({
                      text: z.string().nullable().optional(),
                      i18n_key: z.string().nullable().optional(),
                      url: z.string().nullable().optional(),
                      external: z.boolean().nullable().optional(),
                      icon: z.string().nullable().optional(),
                      visible: z.boolean().nullable().optional(),
                    })
                  )
                  .optional(),
              })
            )
            .optional(),
        })
        .optional(),
    })
    .optional(),
  api: z
    .object({
      enabled: booleanOrString.optional(),
    })
    .optional(),
});

// Secret options
const secretOptionsSchema = z.object({
  default_ttl: numberOrString.optional(),
  ttl_options: z.union([z.string(), z.array(z.number())]).optional(),
});

// Mail schema
const mailSchema = z.object({
  truemail: z
    .object({
      default_validation_type: z.string().optional(),
      verifier_email: z.string().optional(),
      verifier_domain: z.string().optional(),
      allowed_domains_only: z.boolean().optional(),
      dns: z.array(z.string()).optional(),
      smtp_fail_fast: z.boolean().optional(),
      smtp_safe_check: z.boolean().optional(),
      not_rfc_mx_lookup_flow: z.boolean().optional(),
      logger: z
        .object({
          tracking_event: z.any().optional(),
          stdout: z.any().optional(),
        })
        .optional(),
    })
    .optional(),
});

// Diagnostics schema
const diagnosticsSchema = z.object({
  enabled: booleanOrString.optional(),
  sentry: z
    .object({
      backend: z
        .object({
          dsn: z.string().optional(),
          sampleRate: z.union([z.string(), z.number()]).optional(),
          maxBreadcrumbs: z.union([z.string(), z.number()]).optional(),
          logErrors: booleanOrString.optional(),
        })
        .optional(),
      frontend: z
        .object({
          dsn: z.string().optional(),
          sampleRate: z.union([z.string(), z.number()]).optional(),
          maxBreadcrumbs: z.union([z.string(), z.number()]).optional(),
          logErrors: booleanOrString.optional(),
          trackComponents: booleanOrString.optional(),
        })
        .optional(),
    })
    .optional(),
});

// Authentication schema
const authenticationSchema = z.object({
  enabled: booleanOrString.optional(),
  signup: booleanOrString.optional(),
  signin: booleanOrString.optional(),
  autoverify: booleanOrString.optional(),
  required: booleanOrString.optional(),
  colonels: z.array(z.string()).nullable().optional(),
  allowed_signup_domains: z.array(z.string()).nullable().optional(),
});

// Logging schema
const loggingSchema = z.object({
  default_level: z.string().nullable().optional(),
  formatter: z.string().nullable().optional(),
  loggers: z.record(z.string()).nullable().optional(),
  http: z
    .object({
      enabled: booleanOrString.optional(),
      level: z.string().nullable().optional(),
      capture: z.string().nullable().optional(),
      slow_request_ms: numberOrString.optional(),
      ignore_paths: z.array(z.string()).nullable().optional(),
    })
    .nullable()
    .optional(),
});

// Billing schema (when enabled)
const billingSchema = z.object({
  enabled: booleanOrString.optional(),
  stripe_key: z.string().nullable().optional(), // Masked by backend
  webhook_signing_secret: z.string().nullable().optional(), // Masked by backend
  stripe_api_version: z.string().nullable().optional(),
  capabilities: z.record(z.any()).nullable().optional(),
});

// Features schema
const featuresSchema = z.object({
  regions: z
    .object({
      enabled: booleanOrString.optional(),
      current_jurisdiction: z.string().nullable().optional(),
      jurisdictions: z.array(z.any()).nullable().optional(),
    })
    .nullable()
    .optional(),
  domains: z
    .object({
      enabled: booleanOrString.optional(),
      default: z.string().nullable().optional(),
      strategy: z.string().nullable().optional(),
    })
    .nullable()
    .optional(),
});

/**
 * SystemSettingsSchema defines the top-level structure of the settings.
 * Each section references deeper schemas defined elsewhere.
 * Using .optional() to handle partial settings data during initialization.
 */
export const systemSettingsSchema = z.object({
  interface: interfaceSchema.nullable().optional(),
  secret_options: secretOptionsSchema.nullable().optional(),
  authentication: authenticationSchema.nullable().optional(),
  mail: mailSchema.nullable().optional(),
  diagnostics: diagnosticsSchema.nullable().optional(),
  logging: loggingSchema.nullable().optional(),
  billing: billingSchema.nullable().optional(),
  features: featuresSchema.nullable().optional(),
});

export const systemSettingsDetailsSchema = systemSettingsSchema.extend({
  // This extension allows for additional fields in the future without breaking changes
  // All fields are optional with defaults to handle missing data
});

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
  database_sizes: z.record(z.union([
    z.object({
      keys: z.number(),
      expires: z.number(),
      avg_ttl: z.number(),
    }),
    z.string(), // Sometimes Redis INFO returns string format
  ])),
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
  redis_info: z.record(z.string()),
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
  banned_at_human: z.string(),
});

/**
 * Banned IPs list response details
 */
export const bannedIPsDetailsSchema = z.object({
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
    secrets_by_state: z.record(z.number()),
    avg_secrets_per_day: z.number(),
    avg_users_per_day: z.number(),
  }),
  secrets_by_day: z.record(z.number()),
  users_by_day: z.record(z.number()),
});

/**
 * Custom domain schema
 */
export const customDomainSchema = z.object({
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

export const customDomainsDetailsSchema = z.object({
  domains: z.array(customDomainSchema),
  pagination: paginationSchema,
});

/**
 // Raw API data structures before transformation
 // These represent the API shape that will be transformed by input schemas
 */
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

// Export types
export type ColonelStatsDetails = z.infer<typeof colonelStatsDetailsSchema>;
export type ColonelInfoDetails = z.infer<typeof colonelInfoDetailsSchema>;
export type SystemSettingsDetails = z.infer<typeof systemSettingsDetailsSchema>;
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
export type CustomDomain = z.infer<typeof customDomainSchema>;
export type CustomDomainsDetails = z.infer<typeof customDomainsDetailsSchema>;
