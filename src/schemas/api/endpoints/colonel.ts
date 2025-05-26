// src/schemas/api/endpoints/colonel.ts

import { feedbackSchema } from '@/schemas/models';
import { transforms } from '@/schemas/transforms';
import { z } from 'zod';

// Common types
// More flexible type validation that can handle missing values
const booleanOrString = z.union([z.boolean(), z.string()]).optional();
const numberOrString = z.union([z.string(), z.number()]).optional();

const interfaceSchema = z.object({
  ui: z.object({
    enabled: booleanOrString,
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
            company_name: z.string().optional(),
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
              name: z.string(),
              i18n_key: z.string().optional(),
              links: z.array(
                z.object({
                  text: z.string().optional(),
                  i18n_key: z.string().optional(),
                  url: z.string(),
                  external: z.boolean().optional(),
                  icon: z.string().optional(),
                  visible: z.boolean().optional(),
                })
              ),
            })
          )
          .optional(),
      })
      .optional(),
  }),
  api: z.object({
    enabled: booleanOrString,
  }),
});

// Secret options
const secretOptionsSchema = z.object({
  default_ttl: numberOrString,
  ttl_options: z.union([z.string(), z.array(z.number())]),
});

// Mail schema
const mailSchema = z.object({
  truemail: z.object({
    default_validation_type: z.string(),
    verifier_email: z.string(),
    verifier_domain: z.string().optional(),
    allowed_domains_only: z.boolean(),
    dns: z.array(z.string()),
    smtp_fail_fast: z.boolean(),
    smtp_safe_check: z.boolean(),
    not_rfc_mx_lookup_flow: z.boolean(),
    logger: z.object({
      tracking_event: z.any().optional(),
      stdout: z.any().optional(),
    }),
  }),
});

// Diagnostics schema
const diagnosticsSchema = z.object({
  enabled: booleanOrString,
  sentry: z.object({
    backend: z.object({
      dsn: z.string().optional(),
      sampleRate: z.union([z.string(), z.number()]),
      maxBreadcrumbs: z.union([z.string(), z.number()]),
      logErrors: booleanOrString,
    }),
    frontend: z.object({
      dsn: z.string().optional(),
      sampleRate: z.union([z.string(), z.number()]),
      maxBreadcrumbs: z.union([z.string(), z.number()]),
      logErrors: booleanOrString,
      trackComponents: booleanOrString.optional(),
    }),
  }),
});

// Limits schema
const limitsSchema = z.object({
  create_secret: z.number(),
  create_account: z.number(),
  update_account: z.number(),
  email_recipient: z.number(),
  send_feedback: z.number(),
  authenticate_session: z.number(),
  get_page: z.number(),
  dashboard: z.number(),
  failed_passphrase: z.number(),
  show_metadata: z.number(),
  show_secret: z.number(),
  burn_secret: z.number(),
  destroy_account: z.number(),
  forgot_password_request: z.number(),
  forgot_password_reset: z.number(),
  generate_apitoken: z.number(),
  add_domain: z.number(),
  remove_domain: z.number(),
  list_domains: z.number(),
  get_domain: z.number(),
  verify_domain: z.number(),
  report_exception: z.number(),
  attempt_secret_access: z.number(),
  check_status: z.number(),
  update_branding: z.number(),
  destroy_session: z.number(),
  get_domain_brand: z.number(),
  get_domain_logo: z.number(),
  get_image: z.number(),
  remove_domain_logo: z.number(),
  show_account: z.number(),
  stripe_webhook: z.number(),
  update_domain_brand: z.number(),
  view_colonel: z.number(),
  external_redirect: z.number(),
  update_colonel_config: z.number().optional(),
});

/**
 * ColonelConfigSchema defines the top-level structure of the configuration.
 * Each section references deeper schemas defined elsewhere.
 * Using .optional().default({}) to handle partial configuration data during initialization.
 */
export const colonelConfigSchema = z.object({
  interface: interfaceSchema.optional().default({}),
  secret_options: secretOptionsSchema.optional().default({}),
  mail: mailSchema.optional().default({ truemail: {} }),
  diagnostics: diagnosticsSchema.optional().default({}),
  limits: limitsSchema.optional().default({}),
  // development: developmentSchema.optional().default({}),
  // experimental: z.record(z.any()).optional().default({}),
  // features: z.record(z.any()),
  // redis: z.record(z.any()),
  // logging: z.record(z.any()),
  // emailer: z.record(z.any()),
  // internationalization: z.record(z.any()),
});

export const colonelConfigDetailsSchema = colonelConfigSchema.extend({
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
export const colonelInfoDetailsSchema = z.object({
  recent_customers: z.array(recentCustomerSchema).default([]),
  today_feedback: z.array(feedbackSchema).default([]),
  yesterday_feedback: z.array(feedbackSchema).default([]),
  older_feedback: z.array(feedbackSchema).nullable().default(null),
  redis_info: z.string().optional().default(''),
  plans_enabled: z.boolean().optional().default(false),
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
export type ColonelInfoDetails = z.infer<typeof colonelInfoDetailsSchema>;
export type ColonelConfigDetails = z.infer<typeof colonelConfigDetailsSchema>;
export type RecentCustomer = z.infer<typeof recentCustomerSchema>;
