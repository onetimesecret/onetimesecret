// src/schemas/models/public.ts

import { transforms } from '@/schemas/transforms';
import { z } from 'zod';

/**
 * Public API Secret Options Schema
 *
 * This schema is for parsing public settings API responses where values may
 * be stringified from environment variables. Uses transforms.fromString.*
 * for automatic string-to-type coercion.
 *
 * NOTE: This is distinct from config/section/secret_options.ts which validates
 * backend YAML configuration structure.
 *
 * @example Validate and parse the data
 *    const parsedSecretOptions: SecretOptions = publicSecretOptionsSchema.parse(receivedSecretOptions);
 *
 */
export const publicSecretOptionsSchema = z.object({
  /**
   * Default Time-To-Live (TTL) for secrets in seconds
   * Default: 604800 (7 days in seconds)
   */
  default_ttl: z
    .number()
    .int()
    .positive()
    .default(604800)
    .transform((val) => transforms.fromString.number.parse(val)),

  /**
   * Available TTL options for secret creation (in seconds)
   * These options will be presented to users when they create a new secret
   * Format: Array of integers representing seconds
   * Default: [300, 1800, 3600, 14400, 43200, 86400, 259200, 604800, 1209600]
   */
  ttl_options: z
    .array(z.number().int().positive().min(60).max(2592000))
    .transform((arr) => arr.map((val) => transforms.fromString.number.parse(val)))
    .default([300, 1800, 3600, 14400, 43200, 86400, 259200, 604800, 1209600, 2592000]),

  /**
   * Settings for the passphrase field that protects access to secrets
   */
  passphrase: z
    .object({
      /**
       * Whether passphrases are required for all secrets
       */
      required: transforms.fromString.boolean.default(false),

      /**
       * Minimum length required for passphrases
       */
      minimum_length: z.number().int().min(1).max(256).default(8),

      /**
       * Maximum length allowed for passphrases
       */
      maximum_length: z.number().int().min(8).max(1024).default(128),

      /**
       * Whether to enforce complexity requirements
       */
      enforce_complexity: transforms.fromString.boolean.default(false),
    })
    .optional(),

  /**
   * Settings for password generation feature
   */
  password_generation: z
    .object({
      /**
       * Default length for generated passwords
       */
      default_length: z.number().int().min(4).max(128).default(12),

      /**
       * Available length options for password generation
       */
      length_options: z.array(z.number().int().min(4).max(128)).default([8, 12, 16, 20, 24, 32]),

      /**
       * Character sets to include in generated passwords
       */
      character_sets: z
        .object({
          uppercase: transforms.fromString.boolean.default(true),
          lowercase: transforms.fromString.boolean.default(true),
          numbers: transforms.fromString.boolean.default(true),
          symbols: transforms.fromString.boolean.default(false),
          exclude_ambiguous: transforms.fromString.boolean.default(true),
        })
        .optional(),
    })
    .optional(),
});

/**
 * Inferred TypeScript type for SecretOptions
 */
export type SecretOptions = z.infer<typeof publicSecretOptionsSchema>;

/**
 * Public API Authentication Schema
 *
 * This schema is for parsing public settings API responses where boolean
 * values may be stringified. Uses transforms.fromString.boolean for coercion.
 *
 * NOTE: This is distinct from config/section/site.ts:siteAuthenticationSchema
 * which validates backend YAML configuration structure.
 */
export const publicAuthenticationSchema = z.object({
  /**
   * Flag to enable or disable authentication
   */
  enabled: transforms.fromString.boolean,

  /**
   * Flag to allow or disallow user sign-up
   */
  signup: transforms.fromString.boolean,

  /**
   * Flag to allow or disallow user sign-in
   */
  signin: transforms.fromString.boolean,

  /**
   * Flag to enable or disable automatic verification
   */
  autoverify: transforms.fromString.boolean,

  /**
   * Flag to enable or disable homepage secret form when not logged in.
   */
  required: transforms.fromString.boolean,
});

/**
 * Inferred TypeScript type for Authentication
 */
export type AuthenticationSettings = z.infer<typeof publicAuthenticationSchema>;

/**
 * Schema for the :jurisdiction section
 */
const jurisdictionSchema = z.object({
  identifier: z.string(),
  display_name: z.string(),
  domain: z.string(),
  icon: z.string(),
});

/**
 * Schema for the :regions section
 */
const regionsSchema = z.object({
  enabled: transforms.fromString.boolean,
  current_jurisdiction: z.string().optional(),
  jurisdictions: z.array(jurisdictionSchema).optional(),
});

/**
 * Schema for the :cluster section within :domains
 */
const clusterSchema = z
  .object({
    type: z.string().optional(),
    //  api_key: z.string().optional(),
    cluster_ip: z.string().optional(),
    cluster_host: z.string().optional(),
    cluster_name: z.string(),
    vhost_target: z.string(),
  })
  .strip();

/**
 * Schema for the :domains section
 */
const domainsSchema = z.object({
  enabled: transforms.fromString.boolean,
  default: z.string().optional(),
  cluster: clusterSchema,
});

/**
 * Schema for the :authenticity section
 */
const authenticitySchema = z
  .object({
    type: z.string(),
    //  secret_identifier: z.string(),
  })
  .strip();

/**
 * Schema for the :support section
 */
const supportSchema = z.object({
  host: z.string().optional(),
});

/**
 * Public API Features Schema
 *
 * This schema is for parsing public settings API responses for feature flags.
 * Uses transforms.fromString.boolean for stringified boolean coercion.
 *
 * NOTE: This is distinct from config/section/features.ts:featuresSchema
 * which validates backend YAML configuration structure.
 */
export const publicFeaturesSchema = z.object({
  regions: regionsSchema,
  domains: domainsSchema,
});

/**
 * Combined Schema for PublicSettings based on :site in config.schema.yaml
 */
export const publicSettingsSchema = z
  .object({
    host: z.string(),
    ssl: transforms.fromString.boolean,
    authentication: publicAuthenticationSchema,
    // secret: z.string(),
    authenticity: authenticitySchema,
    support: supportSchema,
    secret_options: publicSecretOptionsSchema,
  })
  .strict();

/**
 * Inferred TypeScript type for PublicSettings
 */
export type PublicSettings = z.infer<typeof publicSettingsSchema>;

/**
 * Inferred TypeScript type for Features
 */
export type Features = z.infer<typeof publicFeaturesSchema>;
