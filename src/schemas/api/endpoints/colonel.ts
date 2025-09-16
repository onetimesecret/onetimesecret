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
                      text: z.string().optional(),
                      i18n_key: z.string().optional(),
                      url: z.string().optional(),
                      external: z.boolean().optional(),
                      icon: z.string().optional(),
                      visible: z.boolean().optional(),
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

/**
 * SystemSettingsSchema defines the top-level structure of the settings.
 * Each section references deeper schemas defined elsewhere.
 * Using .optional() to handle partial settings data during initialization.
 */
export const systemSettingsSchema = z.object({
  interface: interfaceSchema.nullable().optional(),
  secret_options: secretOptionsSchema.nullable().optional(),
  mail: mailSchema.nullable().optional(),
  diagnostics: diagnosticsSchema.nullable().optional(),
  // development: developmentSchema.optional(),
  // experimental: z.record(z.any()).optional(),
  // features: z.record(z.any()).optional(),
  // redis: z.record(z.any()).optional(),
  // logging: z.record(z.any()).optional(),
  // emailer: z.record(z.any()).optional(),
  // internationalization: z.record(z.any()).optional(),
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
  planid: z.string(),
  colonel: z.boolean(),
  secrets_created: transforms.fromString.number,
  secrets_shared: transforms.fromString.number,
  emails_sent: transforms.fromString.number,
  verified: z.boolean(),
  stamp: z.string(),
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
