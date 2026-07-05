// src/schemas/contracts/config/section/site.ts

/**
 * Site Configuration Schema
 *
 * Maps to the `site:` section in config.defaults.yaml
 *
 * Per contracts convention, this schema describes field names and types only.
 * Defaults and value constraints belong in `shapes/config/section/site.ts`.
 */

import { z } from 'zod';
import { nullableString } from '../shared/primitives';

/**
 * Authentication settings within site configuration
 */
const siteAuthenticationSchema = z.object({
  enabled: z.boolean().optional(),
  signup: z.boolean().optional(),
  signin: z.boolean().optional(),
  autoverify: z.boolean().optional(),
  required: z.boolean().optional(),
  colonels: z.array(z.string()).optional(),
  allowed_signup_domains: z.array(z.string()).optional(),
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
  expire_after: z.number().optional(),
  key: z.string().optional(),
  secure: z.boolean().optional(),
  same_site: z.enum(['strict', 'lax', 'none']).optional(),
  httponly: z.boolean().optional(),
});

/**
 * Content Security Policy configuration
 */
const cspSchema = z.object({
  enabled: z.boolean().optional(),
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
  static_files: z.boolean().optional(),
  utf8_sanitizer: z.boolean().optional(),
  authenticity_token: z.boolean().optional(),
  http_origin: z.boolean().optional(),
  xss_header: z.boolean().optional(),
  frame_options: z.boolean().optional(),
  path_traversal: z.boolean().optional(),
  cookie_tossing: z.boolean().optional(),
  ip_spoofing: z.boolean().optional(),
  strict_transport: z.boolean().optional(),
});

/**
 * Secret options - passphrase settings
 */
const passphraseSchema = z.object({
  required: z.boolean().optional(),
  /**
   * Minimum length required for passphrases.
   * @sync apps/api/v1/logic/secrets/base_secret_action.rb — passphrase validation
   */
  minimum_length: z.number().optional(),
  maximum_length: z.number().optional(),
  enforce_complexity: z.boolean().optional(),
});

/**
 * Secret options - password generation settings
 */
const passwordGenerationCharacterSetsSchema = z.object({
  uppercase: z.boolean().optional(),
  lowercase: z.boolean().optional(),
  numbers: z.boolean().optional(),
  symbols: z.boolean().optional(),
  exclude_ambiguous: z.boolean().optional(),
});

const passwordGenerationSchema = z.object({
  default_length: z.number().optional(),
  character_sets: passwordGenerationCharacterSetsSchema,
});

/**
 * Secret options configuration
 */
const siteSecretOptionsSchema = z.object({
  default_ttl: z.number().nullable().optional(),
  ttl_options: z.string().nullable().optional(), // Raw string from env, parsed elsewhere
  generated_value_display_ttl: z.number().optional(),
  // Legacy V1 API escape hatch: reveal concealed plaintext on the V1 receipt
  // endpoint (server-side behavior flag; V2/V3 never do this).
  v1_reveal_concealed_on_receipt: z.boolean().optional(),
  passphrase: passphraseSchema,
  password_generation: passwordGenerationSchema,
});

/**
 * Complete site schema matching config.defaults.yaml site: section
 */
const siteSchema = z.object({
  host: z.string().optional(),
  ssl: z.boolean().optional(),
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
