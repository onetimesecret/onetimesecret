// src/schemas/shapes/config/section/site.ts

/**
 * Site Configuration Shape
 *
 * Adds runtime defaults and value constraints on top of the type-only site
 * contract — authentication defaults, session/cookie settings, middleware
 * toggles, passphrase/password-generation bounds, and the top-level host.
 *
 * @see src/schemas/contracts/config/section/site.ts
 */

import { z } from 'zod';
import { nullableString } from '@/schemas/contracts/config/shared/primitives';

export {
  siteSchema,
  siteAuthenticationSchema,
  siteSecretOptionsSchema,
  passphraseSchema,
  passwordGenerationSchema,
  sessionConfigSchema,
  middlewareSchema,
  securitySchema,
  cspSchema,
} from '@/schemas/contracts/config/section/site';

export type {
  SessionConfig,
  MiddlewareConfig,
  CspConfig,
  SecurityConfig,
} from '@/schemas/contracts/config/section/site';

const siteAuthenticationShape = z.object({
  enabled: z.boolean().default(true),
  signup: z.boolean().default(true),
  signin: z.boolean().default(true),
  autoverify: z.boolean().default(false),
  required: z.boolean().default(false),
  colonels: z.array(z.string()).default([]),
  allowed_signup_domains: z.array(z.string()).default([]),
});

const siteSupportShape = z.object({
  host: z.string().nullable().optional(),
});

const sessionConfigShape = z.object({
  secret: nullableString,
  expire_after: z.number().int().positive().default(86400),
  key: z.string().default('onetime.session'),
  secure: z.boolean().default(true),
  same_site: z.enum(['strict', 'lax', 'none']).default('lax'),
  httponly: z.boolean().default(true),
});

const cspShape = z.object({
  enabled: z.boolean().default(false),
});

const securityShape = z.object({
  csp: cspShape.optional(),
});

const middlewareShape = z.object({
  static_files: z.boolean().default(true),
  utf8_sanitizer: z.boolean().default(true),
  authenticity_token: z.boolean().default(true),
  http_origin: z.boolean().default(false),
  xss_header: z.boolean().default(false),
  frame_options: z.boolean().default(false),
  path_traversal: z.boolean().default(false),
  cookie_tossing: z.boolean().default(false),
  ip_spoofing: z.boolean().default(false),
  strict_transport: z.boolean().default(false),
});

const passphraseShape = z.object({
  required: z.boolean().default(false),
  /**
   * Minimum length required for passphrases.
   * Default: 4. Set to 0 to disable enforcement.
   * @sync apps/api/v1/logic/secrets/base_secret_action.rb — passphrase validation
   */
  minimum_length: z.number().int().min(0).max(256).default(4),
  maximum_length: z.number().int().positive().default(128),
  enforce_complexity: z.boolean().default(false),
});

const passwordGenerationCharacterSetsShape = z.object({
  uppercase: z.boolean().default(true),
  lowercase: z.boolean().default(true),
  numbers: z.boolean().default(true),
  symbols: z.boolean().default(true),
  exclude_ambiguous: z.boolean().default(true),
});

const passwordGenerationShape = z.object({
  default_length: z.number().int().positive().default(12),
  character_sets: passwordGenerationCharacterSetsShape,
});

const siteSecretOptionsShape = z.object({
  default_ttl: z.number().int().positive().nullable().optional(),
  ttl_options: z.string().nullable().optional(),
  generated_value_display_ttl: z.number().int().nonnegative().optional(),
  passphrase: passphraseShape,
  password_generation: passwordGenerationShape,
});

const siteShape = z.object({
  host: z.string().default('localhost:3000'),
  ssl: z.boolean().default(false),
  secret: z.string().nullable().optional(),
  interface: z.any().optional(),
  secret_options: siteSecretOptionsShape.optional(),
  authentication: siteAuthenticationShape.optional(),
  support: siteSupportShape.optional(),
  session: sessionConfigShape.optional(),
  middleware: middlewareShape.optional(),
  security: securityShape.optional(),
});

export {
  siteShape,
  siteAuthenticationShape,
  siteSecretOptionsShape,
  passphraseShape,
  passwordGenerationShape,
  sessionConfigShape,
  middlewareShape,
  securityShape,
  cspShape,
};
