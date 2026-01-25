// src/schemas/config/section/site.ts

/**
 * Site Configuration Schema
 *
 * Maps to the `site:` section in config.defaults.yaml
 */

import { z } from 'zod';
import { nullableString } from '../shared/primitives';

/**
 * Authentication settings within site configuration
 */
const siteAuthenticationSchema = z.object({
  enabled: z.boolean().default(true),
  signup: z.boolean().default(true),
  signin: z.boolean().default(true),
  autoverify: z.boolean().default(false),
  required: z.boolean().default(false),
  colonels: z.array(z.string()).default([]),
  allowed_signup_domains: z.array(z.string()).default([]),
});

/**
 * Support configuration
 */
const siteSupportSchema = z.object({
  host: z.string().nullable().optional(),
});

/**
 * Session configuration
 *
 * Controls browser cookie and server-side session behavior.
 * Moved from auth config as sessions are auth-mode agnostic.
 */
const sessionConfigSchema = z.object({
  secret: nullableString,
  expire_after: z.number().int().positive().default(86400), // 24 hours
  key: z.string().default('onetime.session'),
  secure: z.boolean().default(true),
  same_site: z.enum(['strict', 'lax', 'none']).default('lax'),
  httponly: z.boolean().default(true),
});

/**
 * Content Security Policy configuration
 */
const cspSchema = z.object({
  enabled: z.boolean().default(false),
});

/**
 * Security configuration
 *
 * Additional security settings beyond middleware.
 */
const securitySchema = z.object({
  csp: cspSchema.optional(),
});

/**
 * Middleware configuration
 *
 * Controls which Rack middleware components are enabled.
 * Relocated from experimental to site as these are now stable.
 */
const middlewareSchema = z.object({
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

/**
 * Secret options - passphrase settings
 */
const passphraseSchema = z.object({
  required: z.boolean().default(false),
  minimum_length: z.number().int().positive().default(8),
  maximum_length: z.number().int().positive().default(128),
  enforce_complexity: z.boolean().default(false),
});

/**
 * Secret options - password generation settings
 */
const passwordGenerationCharacterSetsSchema = z.object({
  uppercase: z.boolean().default(true),
  lowercase: z.boolean().default(true),
  numbers: z.boolean().default(true),
  symbols: z.boolean().default(true),
  exclude_ambiguous: z.boolean().default(true),
});

const passwordGenerationSchema = z.object({
  default_length: z.number().int().positive().default(12),
  character_sets: passwordGenerationCharacterSetsSchema,
});

/**
 * Secret options configuration
 */
const siteSecretOptionsSchema = z.object({
  default_ttl: z.number().int().positive().nullable().optional(),
  ttl_options: z.string().nullable().optional(), // Raw string from env, parsed elsewhere
  passphrase: passphraseSchema,
  password_generation: passwordGenerationSchema,
});

/**
 * Complete site schema matching config.defaults.yaml site: section
 */
const siteSchema = z.object({
  host: z.string().default('localhost:3000'),
  ssl: z.boolean().default(false),
  secret: z.string().nullable().optional(),
  interface: z.any().optional(), // Defined in ui.ts for mutable config
  secret_options: siteSecretOptionsSchema.optional(),
  authentication: siteAuthenticationSchema.optional(),
  support: siteSupportSchema.optional(),
  session: sessionConfigSchema.optional(),
  middleware: middlewareSchema.optional(),
  security: securitySchema.optional(),
});

export type SessionConfig = z.infer<typeof sessionConfigSchema>;
export type MiddlewareConfig = z.infer<typeof middlewareSchema>;
export type CspConfig = z.infer<typeof cspSchema>;
export type SecurityConfig = z.infer<typeof securitySchema>;

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
};
