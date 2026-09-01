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
 * Legal & policy URLs (`site.legal`, #4278)
 *
 * First-class config for the documents linked from signup consent, the
 * branded reveal footer, and the footer "legal" link group. Each field is
 * nullable — unset means the corresponding link is absent everywhere it
 * would render (no placeholder, no dead anchor).
 */
const siteLegalSchema = z.object({
  terms_url: nullableString,
  privacy_url: nullableString,
  dpa_url: nullableString,
  cookie_url: nullableString,
  aup_url: nullableString,
  security_url: nullableString,
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
/**
 * Step-up (sudo) window for destructive colonel actions (#4327).
 *
 * `window` is the elevation lifetime in seconds. `reauth_grace` is the
 * post-sign-in grace during which a PASSWORD-LESS colonel may elevate with no
 * credential — 0 (the shipped default) disables it, so it is the one numeric
 * here where 0 is a legitimate value rather than a typo'd env var.
 * Defaults belong in `shapes/config/section/site.ts`.
 */
const siteAdminElevationSchema = z.object({
  enabled: z.boolean().optional(),
  window: z.number().optional(),
  reauth_grace: z.number().optional(),
});

/** One colonel rate-limit bucket: cap, counting window, lockout — all seconds. */
const colonelRateLimitBucketSchema = z.object({
  enabled: z.boolean().optional(),
  max_attempts: z.number().optional(),
  window: z.number().optional(),
  lockout: z.number().optional(),
});

/**
 * Rate limits for the colonel API surface, keyed on the acting colonel's extid
 * — never on a session id (#4327 ships `elevation`; #4329 adds the mutation /
 * destructive / handle-resolve buckets). The parent `enabled` flag
 * short-circuits every bucket. Every bucket has the same four fields; the
 * shipped sizing differs per bucket and lives in
 * `shapes/config/section/site.ts`.
 */
const siteAdminRateLimitSchema = z.object({
  enabled: z.boolean().optional(),
  elevation: colonelRateLimitBucketSchema.optional(),
  /** Every mutating colonel verb, charged from the base logic constructor. */
  mutation: colonelRateLimitBucketSchema.optional(),
  /** TIER 1 verbs only, charged after step-up, confirmation and interlocks. */
  destructive: colonelRateLimitBucketSchema.optional(),
  /** The two session reads that resolve an opaque handle (#4330). */
  handle_resolve: colonelRateLimitBucketSchema.optional(),
});

/**
 * Idle + absolute bounds on the ADMIN API SURFACE (/api/colonel) only (#4331).
 * They do not shorten the shared onetime.session cookie and do not gate the
 * /colonel SPA shell. `0` disables a bound and is a legitimate value here rather
 * than a typo'd env var, so neither number is `.positive()` in the shape file.
 * Defaults belong in `shapes/config/section/site.ts`.
 */
const siteAdminSessionSchema = z.object({
  enabled: z.boolean().optional(),
  /** Seconds of inactivity, read from the best-effort SessionMetadata sidecar. */
  idle_timeout: z.number().optional(),
  /** Seconds since sign-in, read from session['authenticated_at']. */
  absolute_timeout: z.number().optional(),
});

const siteAdminSchema = z.object({
  elevation: siteAdminElevationSchema.optional(),
  rate_limit: siteAdminRateLimitSchema.optional(),
  session: siteAdminSessionSchema.optional(),
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
  legal: siteLegalSchema.optional(),
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
  siteLegalSchema,
  siteSecretOptionsSchema,
  passphraseSchema,
  passwordGenerationSchema,
  sessionConfigSchema,
  middlewareSchema,
  securitySchema,
  cspSchema,
  siteAdminSchema,
};
