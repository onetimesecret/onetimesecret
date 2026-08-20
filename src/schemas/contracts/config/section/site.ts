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
  /**
   * Full external paths (SCRIPT_NAME + PATH_INFO) matched EXACTLY, for which
   * no session is persisted — anonymous probe endpoints only (#3997).
   */
  skip_paths: z.array(z.string()).optional(),
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
  referrer_policy: z.boolean().optional(),
  permissions_policy: z.boolean().optional(),
  frame_options: z.boolean().optional(),
  path_traversal: z.boolean().optional(),
  cookie_tossing: z.boolean().optional(),
  ip_spoofing: z.boolean().optional(),
  strict_transport: z.boolean().optional(),
});

/**
 * Admin (Colonel) configuration
 *
 * Host- and network-level posture for the Colonel admin surfaces (/colonel +
 * /api/colonel), both enforced by the AdminNetworkIsolation Rack middleware;
 * a request failing either gate gets the same 404. allowed_hosts is the
 * hostname allowlist (unset = the canonical anchor hosts plus their
 * www. siblings; a `*` anywhere in the list turns the host gate off).
 * allowed_cidrs is an opt-in CIDR allowlist (empty/unset = no-op, the
 * self-hosted default). Defaults belong in `shapes/config/section/site.ts`.
 *
 * allowed_hosts is nullable because the YAML renders null when
 * ADMIN_ALLOWED_HOSTS is unset, and an EMPTY list when it is set but blank —
 * a distinction the boot check warns on (#4127), so the template must not
 * collapse null to []. Runtime behavior is identical for both shapes.
 */
const siteAdminSchema = z.object({
  allowed_hosts: z.array(z.string()).nullable().optional(),
  allowed_cidrs: z.array(z.string()).optional(),
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
  // Ceiling for secrets created without an account. Default 7 days; operators
  // may raise or lower it (TTL_MAX_ANONYMOUS). Coerced to Integer seconds in
  // after_load.
  ttl_max_anonymous: z.number().nullable().optional(),
  generated_value_display_ttl: z.number().optional(),
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
  /**
   * Boot-time SECRET verifier policy (C10/QS-6).
   * @sync lib/onetime/secret_verifier.rb — MODES
   */
  secret_verifier_mode: z.enum(['warn', 'enforce', 'off']).optional(),
  interface: z.any().optional(), // Defined in ui.ts for mutable config
  secret_options: siteSecretOptionsSchema.optional(),
  authentication: siteAuthenticationSchema.optional(),
  support: siteSupportSchema.optional(),
  session: sessionConfigSchema.optional(),
  middleware: middlewareSchema.optional(),
  security: securitySchema.optional(),
  admin: siteAdminSchema.optional(),
});

export type SessionConfig = z.infer<typeof sessionConfigSchema>;
export type MiddlewareConfig = z.infer<typeof middlewareSchema>;
export type CspConfig = z.infer<typeof cspSchema>;
export type SecurityConfig = z.infer<typeof securitySchema>;
export type SiteAdminConfig = z.infer<typeof siteAdminSchema>;

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
  siteAdminSchema,
};
