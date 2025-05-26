import { feedbackSchema } from '@/schemas/models';
import { transforms } from '@/schemas/transforms';
import { z } from 'zod';

// Common types
const BooleanOrString = z.union([z.boolean(), z.string()]);
const NumberOrString = z.union([z.string(), z.number()]);

const InterfaceSchema = z.object({
  ui: z.object({
    enabled: BooleanOrString,
    header: z
      .object({
        enabled: BooleanOrString.optional(),
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
            enabled: BooleanOrString.optional(),
          })
          .optional(),
      })
      .optional(),
    footer_links: z
      .object({
        enabled: BooleanOrString.optional(),
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
    enabled: BooleanOrString,
  }),
});

// Secret options
const SecretOptionsSchema = z.object({
  default_ttl: NumberOrString,
  ttl_options: z.string(),
});

// Mail schema
const MailSchema = z.object({
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
const DiagnosticsSchema = z.object({
  enabled: BooleanOrString,
  sentry: z.object({
    defaults: z.object({
      dsn: z.string().optional(),
      sampleRate: z.union([z.string(), z.number()]),
      maxBreadcrumbs: z.union([z.string(), z.number()]),
      logErrors: BooleanOrString,
    }),
    backend: z.object({
      dsn: z.string().optional(),
    }),
    frontend: z.object({
      dsn: z.string().optional(),
      trackComponents: BooleanOrString.optional(),
    }),
  }),
});

// Limits schema
const LimitsSchema = z.object({
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

const DevelopmentSchema = z.object({
  enabled: z.any(),
  debug: z.any(),
  frontend_host: z.string(),
});

/**
 * ColonelConfigSchema defines the top-level structure of the configuration.
 * Each section references deeper schemas defined elsewhere.
 */
export const ColonelConfigSchema = z.object({
  interface: InterfaceSchema,
  secret_options: SecretOptionsSchema,
  mail: MailSchema,
  diagnostics: DiagnosticsSchema,
  limits: LimitsSchema,
  development: DevelopmentSchema,
  // features: z.record(z.any()),
  // redis: z.record(z.any()),
  // logging: z.record(z.any()),
  // emailer: z.record(z.any()),
  // internationalization: z.record(z.any()),
  // experimental: z.record(z.any()).optional(),
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
 * Raw API data structures before transformation
 * These represent the API shape that will be transformed by input schemas
 */
export const colonelDetailsSchema = z.object({
  recent_customers: z.array(recentCustomerSchema),
  today_feedback: z.array(feedbackSchema),
  yesterday_feedback: z.array(feedbackSchema),
  older_feedback: z.array(feedbackSchema).nullable(),
  redis_info: z.string(),
  plans_enabled: z.boolean(),
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
export type ColonelDetails = z.infer<typeof colonelDetailsSchema>;
export type RecentCustomer = z.infer<typeof recentCustomerSchema>;
