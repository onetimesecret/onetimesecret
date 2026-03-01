// src/schemas/config/config.ts

/**
 * Application Configuration Schema
 *
 * Consolidated Zod v4 schemas for config.defaults.yaml
 *
 * This schema supports two use cases:
 * 1. API Response Parsing - flexible schemas that accept string/boolean unions
 *    for values that may come as strings from environment variables
 * 2. Config File Validation - strict schemas matching YAML structure
 *
 * The API response schemas use booleanOrString/numberOrString for flexibility
 * when parsing backend responses that may have coerced values.
 */

import { z } from 'zod';

import { siteSchema, siteAuthenticationSchema, passphraseSchema, passwordGenerationSchema } from './section/site';
import { storageSchema, redisSchema } from './section/storage';
import { emailerSchema, mailSchema, mailConnectionSchema, mailValidationSchema } from './section/mail';
import { diagnosticsSchema } from './section/diagnostics';
import { featuresSchema } from './section/features';
import { capabilitiesSchema } from './section/capabilities';
import { i18nSchema } from './section/i18n';
import { developmentSchema } from './section/development';
import { userInterfaceSchema, apiSchema } from './section/ui';
import { limitsSchema } from './section/limits';
import { secretOptionsSchema } from './section/secret_options';
import { brandSchema } from './section/brand';
import { jobsSchema } from './section/jobs';

// ============================================================================
// Flexible Type Helpers (for API response parsing)
// ============================================================================

/**
 * Flexible boolean that accepts boolean or string ("true"/"false")
 * Used when parsing API responses where env vars may be stringified
 */
export const booleanOrString = z.union([z.boolean(), z.string()]).optional();

/**
 * Flexible number that accepts number or string
 * Used when parsing API responses where env vars may be stringified
 */
export const numberOrString = z.union([z.string(), z.number()]).optional();

// ============================================================================
// API Response Schemas (flexible, for parsing backend responses)
// ============================================================================

/**
 * Interface schema for API responses
 * More permissive than config file schema to handle string coercion
 */
export const apiInterfaceSchema = z.object({
  ui: z
    .object({
      enabled: booleanOrString,
      header: z
        .object({
          enabled: booleanOrString,
          branding: z
            .object({
              logo: z
                .object({
                  url: z.string().optional(),
                  alt: z.string().optional(),
                  href: z.string().optional(),
                  link_to: z.string().optional(), // Legacy field
                })
                .optional(),
              site_name: z.string().optional(),
            })
            .optional(),
          navigation: z
            .object({
              enabled: booleanOrString,
            })
            .optional(),
        })
        .optional(),
      footer_links: z
        .object({
          enabled: booleanOrString,
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
      enabled: booleanOrString,
    })
    .optional(),
});

/**
 * Secret options schema for API responses
 */
export const apiSecretOptionsSchema = z.object({
  default_ttl: numberOrString,
  ttl_options: z.union([z.string(), z.array(z.number())]).optional(),
  passphrase: z
    .object({
      required: booleanOrString,
      minimum_length: numberOrString,
      maximum_length: numberOrString,
      enforce_complexity: booleanOrString,
    })
    .nullable()
    .optional(),
  password_generation: z
    .object({
      default_length: numberOrString,
      character_sets: z
        .object({
          uppercase: booleanOrString,
          lowercase: booleanOrString,
          numbers: booleanOrString,
          symbols: booleanOrString,
          exclude_ambiguous: booleanOrString,
        })
        .nullable()
        .optional(),
    })
    .nullable()
    .optional(),
});

/**
 * Emailer schema for API responses
 */
export const apiEmailerSchema = z.object({
  mode: z.string().nullable().optional(),
  region: z.string().nullable().optional(),
  from: z.string().nullable().optional(),
  from_name: z.string().nullable().optional(),
  reply_to: z.string().nullable().optional(),
  host: z.string().nullable().optional(),
  port: numberOrString.nullable(),
  user: z.string().nullable().optional(),
  pass: z.string().nullable().optional(),
  auth: z.string().nullable().optional(),
  tls: z.union([z.boolean(), z.string()]).nullable().optional(),
});

/**
 * Mail schema for API responses
 */
export const apiMailSchema = z.object({
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

/**
 * Diagnostics schema for API responses
 */
export const apiDiagnosticsSchema = z.object({
  enabled: booleanOrString.nullable(),
  redis_uri: z.string().nullable().optional(),
  sentry: z
    .object({
      defaults: z
        .object({
          dsn: z.string().nullable().optional(),
          sampleRate: z.union([z.string(), z.number()]).nullable().optional(),
          maxBreadcrumbs: z.union([z.string(), z.number()]).nullable().optional(),
          logErrors: booleanOrString.nullable(),
        })
        .nullable()
        .optional(),
      backend: z
        .object({
          dsn: z.string().nullable().optional(),
          sampleRate: z.union([z.string(), z.number()]).nullable().optional(),
          maxBreadcrumbs: z.union([z.string(), z.number()]).nullable().optional(),
          logErrors: booleanOrString.nullable(),
        })
        .nullable()
        .optional(),
      frontend: z
        .object({
          dsn: z.string().nullable().optional(),
          sampleRate: z.union([z.string(), z.number()]).nullable().optional(),
          maxBreadcrumbs: z.union([z.string(), z.number()]).nullable().optional(),
          logErrors: booleanOrString.nullable(),
          trackComponents: booleanOrString.nullable(),
        })
        .nullable()
        .optional(),
    })
    .nullable()
    .optional(),
});

/**
 * Authentication schema for API responses
 */
export const apiAuthenticationSchema = z.object({
  enabled: booleanOrString,
  signup: booleanOrString,
  signin: booleanOrString,
  autoverify: booleanOrString,
  required: booleanOrString,
  colonels: z.array(z.string()).nullable().optional(),
  allowed_signup_domains: z.array(z.string()).nullable().optional(),
});

/**
 * Logging schema for API responses
 */
export const apiLoggingSchema = z.object({
  default_level: z.string().nullable().optional(),
  formatter: z.string().nullable().optional(),
  loggers: z.record(z.string(), z.string()).nullable().optional(),
  http: z
    .object({
      enabled: booleanOrString,
      level: z.string().nullable().optional(),
      capture: z.string().nullable().optional(),
      slow_request_ms: numberOrString,
      ignore_paths: z.array(z.string()).nullable().optional(),
    })
    .nullable()
    .optional(),
});

/**
 * Billing schema for API responses
 * Matches the flat billing.yaml structure (merged from billing.yaml + billing-catalog.yaml)
 */
export const apiBillingSchema = z.object({
  schema_version: z.string().nullable().optional(),
  app_identifier: z.string().nullable().optional(),
  enabled: booleanOrString,
  stripe_key: z.string().nullable().optional(),
  webhook_signing_secret: z.string().nullable().optional(),
  stripe_api_version: z.string().nullable().optional(),
  entitlements: z.record(z.string(), z.any()).nullable().optional(),
  plans: z.record(z.string(), z.any()).nullable().optional(),
  stripe_metadata_schema: z.any().nullable().optional(),
});

/**
 * Features schema for API responses
 */
export const apiFeaturesSchema = z.object({
  regions: z
    .object({
      enabled: booleanOrString,
      current_jurisdiction: z.string().nullable().optional(),
      jurisdictions: z.array(z.any()).nullable().optional(),
    })
    .nullable()
    .optional(),
  incoming: z
    .object({
      enabled: booleanOrString,
      memo_max_length: numberOrString,
      default_ttl: numberOrString,
    })
    .nullable()
    .optional(),
  domains: z
    .object({
      enabled: booleanOrString,
      default: z.string().nullable().optional(),
      validation_strategy: z.string().nullable().optional(),
    })
    .nullable()
    .optional(),
});

/**
 * System settings schema for API responses (colonel endpoint)
 * This is the flexible schema used when parsing backend responses
 */
export const systemSettingsSchema = z.object({
  interface: apiInterfaceSchema.nullable().optional(),
  secret_options: apiSecretOptionsSchema.nullable().optional(),
  authentication: apiAuthenticationSchema.nullable().optional(),
  emailer: apiEmailerSchema.nullable().optional(),
  mail: apiMailSchema.nullable().optional(),
  diagnostics: apiDiagnosticsSchema.nullable().optional(),
  logging: apiLoggingSchema.nullable().optional(),
  billing: apiBillingSchema.nullable().optional(),
  features: apiFeaturesSchema.nullable().optional(),
});

export const systemSettingsDetailsSchema = systemSettingsSchema.extend({});

// ============================================================================
// Config File Schemas (strict, for YAML validation)
// ============================================================================

/**
 * Combined mail schema for static config
 */
const staticMailSchema = z.object({
  connection: mailConnectionSchema,
  validation: z.object({
    defaults: mailValidationSchema.optional(),
  }),
});

/**
 * Mutable mail validation schema
 */
const mutableMailSchema = z.object({
  validation: z.object({
    recipients: mailValidationSchema.optional(),
    accounts: mailValidationSchema.optional(),
  }),
});

/**
 * Simple logging schema for static config
 */
const simpleLoggingSchema = z.object({
  http_requests: z.boolean().default(true),
});

/**
 * Static configuration schema
 * Matches the structure from config.defaults.yaml for application startup
 */
export const staticConfigSchema = z.object({
  site: siteSchema,
  features: featuresSchema.optional(),
  redis: redisSchema.optional(),
  emailer: emailerSchema.optional(),
  mail: mailSchema.optional(),
  internationalization: i18nSchema.optional(),
  diagnostics: diagnosticsSchema.optional(),
  development: developmentSchema.optional(),
  brand: brandSchema.optional(),
  jobs: jobsSchema.optional(),
});

/**
 * Mutable configuration schema
 * Settings that can be changed at runtime without restart
 */
export const mutableConfigSchema = z.object({
  ui: userInterfaceSchema.optional(),
  api: apiSchema.optional(),
  secret_options: secretOptionsSchema.optional(),
  mail: mutableMailSchema.optional(),
  features: featuresSchema.optional(),
  limits: limitsSchema.optional(),
});

/**
 * Runtime configuration schema
 * Combines static and mutable config; static takes precedence
 */
export const runtimeConfigSchema = z.object({
  ...mutableConfigSchema.shape,
  ...staticConfigSchema.shape,
});

/**
 * Legacy static config schema for backward compatibility
 */
export const legacyStaticConfigSchema = z.object({
  site: siteSchema,
  storage: storageSchema.optional(),
  features: featuresSchema.optional(),
  capabilities: capabilitiesSchema.optional(),
  mail: staticMailSchema.optional(),
  logging: simpleLoggingSchema.optional(),
  i18n: i18nSchema.optional(),
  development: developmentSchema.optional(),
  diagnostics: diagnosticsSchema.optional(),
});

// ============================================================================
// Type Exports
// ============================================================================

export type StaticConfig = z.infer<typeof staticConfigSchema>;
export type MutableConfig = z.infer<typeof mutableConfigSchema>;
export type RuntimeConfig = z.infer<typeof runtimeConfigSchema>;
export type LegacyStaticConfig = z.infer<typeof legacyStaticConfigSchema>;
export type SystemSettings = z.infer<typeof systemSettingsSchema>;
export type SystemSettingsDetails = z.infer<typeof systemSettingsDetailsSchema>;

// Re-export section schemas for direct access
export {
  siteSchema,
  siteAuthenticationSchema,
  passphraseSchema,
  passwordGenerationSchema,
  storageSchema,
  redisSchema,
  emailerSchema,
  mailSchema,
  mailConnectionSchema,
  mailValidationSchema,
  diagnosticsSchema,
  featuresSchema,
  capabilitiesSchema,
  i18nSchema,
  developmentSchema,
  userInterfaceSchema,
  apiSchema,
  limitsSchema,
  secretOptionsSchema,
  brandSchema,
  jobsSchema,
};

// Aliases for backward compatibility
export { staticMailSchema, mutableMailSchema, simpleLoggingSchema as loggingSchema };
