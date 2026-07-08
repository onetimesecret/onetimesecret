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
import {
  publicSecretOptionsSchema,
  publicAuthenticationSchema,
  publicFeaturesSchema,
  publicSettingsSchema,
} from '@/schemas/contracts/config/public';
import { augment, type AugmentTree } from '@/schemas/utils/augment';

export {
  publicSecretOptionsSchema,
  publicAuthenticationSchema,
  publicFeaturesSchema,
  publicSettingsSchema,
};

export type {
  PublicSecretOptions,
  PublicAuthenticationSettings,
  PublicSettings,
  PublicFeatures,
  SecretOptions,
  AuthenticationSettings,
  Features,
} from '@/schemas/contracts/config/public';

const passphraseTree: AugmentTree = {
  required: (b) => b.default(false),
  /**
   * Minimum length required for passphrases.
   * @sync apps/api/v2/logic/secrets/base_secret_action.rb — validate_passphrase
   */
  minimum_length: (n) => n.int().min(0).max(256).default(4),
  maximum_length: (n) => n.int().min(8).max(1024).default(128),
  enforce_complexity: (b) => b.default(false),
};

const contentTree: AugmentTree = {
  /**
   * Maximum length allowed for a secret's body.
   * @sync lib/onetime/logic/base.rb — validate_secret_size
   */
  maximum_length: (n) => n.int().positive().default(10000),
};

const passwordGenerationTree: AugmentTree = {
  default_length: (n) => n.int().min(4).max(128).default(12),
  length_options: () =>
    z.array(z.number().int().min(4).max(128)).default([8, 12, 16, 20, 24, 32]),
  character_sets: {
    uppercase: (b) => b.default(true),
    lowercase: (b) => b.default(true),
    numbers: (b) => b.default(true),
    symbols: (b) => b.default(false),
    exclude_ambiguous: (b) => b.default(true),
  },
};

const publicSecretOptionsShape = augment(publicSecretOptionsSchema, {
  /**
   * Default Time-To-Live (TTL) for secrets in seconds
   * Default: 604800 (7 days in seconds)
   */
  default_ttl: (n) => n.int().positive().default(604800),

  /**
   * Available TTL options for secret creation (in seconds)
   * Default: [300, 1800, 3600, 14400, 43200, 86400, 259200, 604800, 1209600, 2592000]
   */
  ttl_options: () =>
    z
      .array(z.number().int().positive().min(60).max(2592000))
      .default([300, 1800, 3600, 14400, 43200, 86400, 259200, 604800, 1209600, 2592000]),

  passphrase: passphraseTree,
  content: contentTree,
  password_generation: passwordGenerationTree,
});

/**
 * Public API Authentication Shape — contract is already type-only with no
 * defaults to inject; re-export under shape naming for consistency.
 */
const publicAuthenticationShape = publicAuthenticationSchema;

/**
 * Public API Features Shape — same story as authentication; the contract's
 * regions/domains nested objects are required fields without defaults.
 */
const publicFeaturesShape = publicFeaturesSchema;

const publicSettingsShape = augment(publicSettingsSchema, {
  secret_options: {
    default_ttl: (n) => n.int().positive().default(604800),
    ttl_options: () =>
      z
        .array(z.number().int().positive().min(60).max(2592000))
        .default([300, 1800, 3600, 14400, 43200, 86400, 259200, 604800, 1209600, 2592000]),
    passphrase: passphraseTree,
    content: contentTree,
    password_generation: passwordGenerationTree,
  },
});

export {
  publicSecretOptionsShape,
  publicAuthenticationShape,
  publicFeaturesShape,
  publicSettingsShape,
};
