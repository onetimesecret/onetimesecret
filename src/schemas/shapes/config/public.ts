// src/schemas/shapes/config/public.ts

/**
 * Public API Configuration Response Shapes
 *
 * These shapes validate public settings API responses with the same TTL,
 * passphrase, and password-generation bounds the previous contract enforced.
 * The type-only contract in `contracts/config/public.ts` describes the wire
 * shape; this file is where defaults and value constraints live.
 *
 * @see src/schemas/contracts/config/public.ts
 */

import { z } from 'zod';

export {
  publicSecretOptionsSchema,
  publicAuthenticationSchema,
  publicFeaturesSchema,
  publicSettingsSchema,
} from '@/schemas/contracts/config/public';

export type {
  PublicSecretOptions,
  PublicAuthenticationSettings,
  PublicSettings,
  PublicFeatures,
  SecretOptions,
  AuthenticationSettings,
  Features,
} from '@/schemas/contracts/config/public';

/**
 * Public API Secret Options Shape — defaults and value bounds applied.
 */
const publicSecretOptionsShape = z.object({
  /**
   * Default Time-To-Live (TTL) for secrets in seconds
   * Default: 604800 (7 days in seconds)
   */
  default_ttl: z.number().int().positive().default(604800),

  /**
   * Available TTL options for secret creation (in seconds)
   * Format: Array of integers representing seconds
   * Default: [300, 1800, 3600, 14400, 43200, 86400, 259200, 604800, 1209600]
   */
  ttl_options: z
    .array(z.number().int().positive().min(60).max(2592000))
    .default([300, 1800, 3600, 14400, 43200, 86400, 259200, 604800, 1209600, 2592000]),

  passphrase: z
    .object({
      required: z.boolean().default(false),
      /**
       * Minimum length required for passphrases.
       * Default: 4. Set to 0 to disable enforcement.
       * @sync apps/api/v1/logic/secrets/base_secret_action.rb — passphrase validation
       */
      minimum_length: z.number().int().min(0).max(256).default(4),
      maximum_length: z.number().int().min(8).max(1024).default(128),
      enforce_complexity: z.boolean().default(false),
    })
    .optional(),

  password_generation: z
    .object({
      default_length: z.number().int().min(4).max(128).default(12),
      length_options: z.array(z.number().int().min(4).max(128)).default([8, 12, 16, 20, 24, 32]),
      character_sets: z
        .object({
          uppercase: z.boolean().default(true),
          lowercase: z.boolean().default(true),
          numbers: z.boolean().default(true),
          symbols: z.boolean().default(false),
          exclude_ambiguous: z.boolean().default(true),
        })
        .optional(),
    })
    .optional(),
});

/**
 * Public API Authentication Shape — no defaults, type-only is already correct.
 * Re-exported for consistent shape naming.
 */
const publicAuthenticationShape = z.object({
  enabled: z.boolean(),
  signup: z.boolean(),
  signin: z.boolean(),
  autoverify: z.boolean(),
  required: z.boolean(),
  mode: z.enum(['simple', 'full']).optional(),
});

const jurisdictionIconShape = z.object({
  collection: z.string(),
  name: z.string(),
});

const jurisdictionShape = z.object({
  identifier: z.string(),
  display_name_i18n_key: z.string(),
  domain: z.string(),
  icon: jurisdictionIconShape.optional(),
});

const regionsShape = z.object({
  enabled: z.boolean(),
  current_jurisdiction: z.string().optional(),
  jurisdictions: z.array(jurisdictionShape).optional(),
});

const approximatedShape = z
  .object({
    api_key: z.string().nullable().optional(),
    proxy_ip: z.string().nullable().optional(),
    proxy_host: z.string().nullable().optional(),
    proxy_name: z.string().nullable().optional(),
    vhost_target: z.string().nullable().optional(),
  })
  .strip();

const acmeShape = z
  .object({
    enabled: z.boolean(),
    listen_address: z.string().optional(),
    port: z.union([z.string(), z.number()]).optional(),
  })
  .strip();

const domainsShape = z.object({
  enabled: z.boolean(),
  require_verified: z.boolean().optional(),
  default: z.string().nullable().optional(),
  validation_strategy: z.string().optional(),
  approximated: approximatedShape.optional(),
  acme: acmeShape.optional(),
});

const authenticityShape = z
  .object({
    type: z.string(),
  })
  .strip();

const supportShape = z.object({
  host: z.string().optional(),
});

/**
 * Public API Features Shape — type-only equivalent; no defaults to inject.
 */
const publicFeaturesShape = z.object({
  regions: regionsShape,
  domains: domainsShape,
});

const publicSettingsShape = z
  .object({
    host: z.string(),
    ssl: z.boolean(),
    authentication: publicAuthenticationShape,
    authenticity: authenticityShape,
    support: supportShape,
    secret_options: publicSecretOptionsShape,
  })
  .strict();

export {
  publicSecretOptionsShape,
  publicAuthenticationShape,
  publicFeaturesShape,
  publicSettingsShape,
};
