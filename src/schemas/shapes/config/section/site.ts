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

import {
  cspSchema,
  middlewareSchema,
  passphraseSchema,
  passwordGenerationSchema,
  securitySchema,
  sessionConfigSchema,
  siteAdminSchema,
  siteAuthenticationSchema,
  siteLegalSchema,
  siteSchema,
  siteSecretOptionsSchema,
} from '@/schemas/contracts/config/section/site';
import { augment, type AugmentTree } from '@/schemas/utils/augment';

export {
  cspSchema,
  middlewareSchema,
  passphraseSchema,
  passwordGenerationSchema,
  securitySchema,
  sessionConfigSchema,
  siteAdminSchema,
  siteAuthenticationSchema,
  siteLegalSchema,
  siteSchema,
  siteSecretOptionsSchema,
};

export type {
  CspConfig,
  MiddlewareConfig,
  SecurityConfig,
  SessionConfig,
  SiteAdminConfig,
} from '@/schemas/contracts/config/section/site';

// ─── Section trees ────────────────────────────────────────────────────────

const authenticationTree: AugmentTree = {
  enabled: (b) => b.default(true),
  signup: (b) => b.default(true),
  signin: (b) => b.default(true),
  autoverify: (b) => b.default(false),
  required: (b) => b.default(false),
  colonels: (a) => a.default([]),
  allowed_signup_domains: (a) => a.default([]),
};

const sessionTree: AugmentTree = {
  expire_after: (n) => n.int().positive().default(86400),
  key: (s) => s.default('onetime.session'),
  secure: (b) => b.default(true),
  same_site: (e) => e.default('lax'),
  httponly: (b) => b.default(true),
  // Anonymous probe endpoints that must not mint a persisted session (#3997).
  // Exact-match against the full external path; never list
  // /api/v*/secret/*/status here (capability-token data reads, not probes).
  skip_paths: (a) =>
    a.default([
      '/health',
      '/health/advanced',
      '/auth/health',
      '/api/v1/status',
      '/api/v2/status',
      '/api/v3/status',
    ]),
};

const cspTree: AugmentTree = {
  enabled: (b) => b.default(false),
};

const securityTree: AugmentTree = {
  csp: cspTree,
};

// Step-up (sudo) window for destructive colonel actions (#4327). ON by
// default, mirroring config.defaults.yaml: a colonel session alone is not
// sufficient for a tier-1 verb.
//
// reauth_grace defaults to 0, and 0 is a MEANINGFUL value here (the grace is
// off) rather than the "typo'd env var" case every other numeric guards
// against — hence .min(0) and not .positive().
const adminElevationTree: AugmentTree = {
  enabled: (b) => b.default(true),
  window: (n) => n.int().positive().default(600),
  reauth_grace: (n) => n.int().min(0).default(0),
};

// One colonel rate-limit bucket. Every bucket has the same four fields but its
// OWN shipped sizing, so this is a factory rather than a shared constant — a
// single tree would have to pick one bucket's numbers and silently misreport
// the other three in the generated JSON Schema. The values must stay in step
// with config.defaults.yaml and with the DEFAULT_* constants in
// lib/onetime/security/colonel_rate_limiter.rb.
const colonelRateLimitBucketTree = (
  maxAttempts: number,
  window: number,
  lockout: number
): AugmentTree => ({
  enabled: (b) => b.default(true),
  max_attempts: (n) => n.int().positive().default(maxAttempts),
  window: (n) => n.int().positive().default(window),
  lockout: (n) => n.int().positive().default(lockout),
});

const adminRateLimitTree: AugmentTree = {
  enabled: (b) => b.default(true),
  // Step-up attempts (#4327); the mutation / destructive / handle-resolve
  // buckets (#4329). Sizing rationale is in config.defaults.yaml.
  elevation: colonelRateLimitBucketTree(5, 900, 900),
  mutation: colonelRateLimitBucketTree(120, 300, 300),
  destructive: colonelRateLimitBucketTree(10, 300, 900),
  handle_resolve: colonelRateLimitBucketTree(60, 300, 300),
};

// Idle + absolute bounds on the ADMIN API SURFACE only (#4331), mirroring
// config.defaults.yaml. Both numbers use .min(0) rather than .positive():
// 0 DISABLES that bound and is a legitimate operator choice, unlike the
// "typo'd env var collapsed to 0" case the positive() guards elsewhere catch.
const adminSessionTree: AugmentTree = {
  enabled: (b) => b.default(true),
  idle_timeout: (n) => n.int().min(0).default(3600),
  absolute_timeout: (n) => n.int().min(0).default(43200),
};

const adminTree: AugmentTree = {
  elevation: adminElevationTree,
  rate_limit: adminRateLimitTree,
  session: adminSessionTree,
  // Empty defaults mirror config.defaults.yaml, but the two gates read empty
  // differently. Host gate: an empty list is still ACTIVE — it anchors on the
  // canonical hosts (DEFAULT_DOMAIN / site.host plus www. siblings) and
  // self-disables only when neither anchor is a detectable hostname. Network
  // gate: an empty list is a no-op and both Colonel surfaces stay reachable
  // (self-hosted single-container default); populated with private CIDRs on
  // cloud for network isolation.
  //
  // `.nullable()` is re-applied here on purpose: augment hands the leaf the
  // UNWRAPPED field and does not re-wrap, and config.defaults.yaml renders
  // `allowed_hosts:` as null when ADMIN_ALLOWED_HOSTS is unset (#4127). Drop
  // it and the generated JSON Schema rejects the shipped defaults file.
  allowed_hosts: (a) => a.nullable().default([]),
  allowed_cidrs: (a) => a.default([]),
};

const middlewareTree: AugmentTree = {
  static_files: (b) => b.default(true),
  utf8_sanitizer: (b) => b.default(true),
  authenticity_token: (b) => b.default(true),
  http_origin: (b) => b.default(false),
  xss_header: (b) => b.default(false),
  frame_options: (b) => b.default(true),
  path_traversal: (b) => b.default(true),
  cookie_tossing: (b) => b.default(false),
  ip_spoofing: (b) => b.default(false),
  strict_transport: (b) => b.default(true),
};

const passphraseTree: AugmentTree = {
  required: (b) => b.default(false),
  /**
   * Minimum length required for passphrases.
   * @sync apps/api/v1/logic/secrets/base_secret_action.rb
   */
  minimum_length: (n) => n.int().min(0).max(256).default(4),
  maximum_length: (n) => n.int().positive().default(128),
  enforce_complexity: (b) => b.default(false),
};

const passwordGenerationTree: AugmentTree = {
  default_length: (n) => n.int().positive().default(12),
  character_sets: {
    uppercase: (b) => b.default(true),
    lowercase: (b) => b.default(true),
    numbers: (b) => b.default(true),
    symbols: (b) => b.default(true),
    exclude_ambiguous: (b) => b.default(true),
  },
};

const siteSecretOptionsTree: AugmentTree = {
  // Bounds-only leaves: the contract field is nullable+optional. augment unwraps
  // those for the leaf, and the leaf re-applies them so the structural shape
  // matches the contract (otherwise the field becomes required).
  default_ttl: (n) => n.int().positive().nullable().optional(),
  generated_value_display_ttl: (n) => n.int().nonnegative().optional(),
  passphrase: passphraseTree,
  password_generation: passwordGenerationTree,
};

// ─── Exported shapes ──────────────────────────────────────────────────────

const siteAuthenticationShape = augment(siteAuthenticationSchema, authenticationTree);
const sessionConfigShape = augment(sessionConfigSchema, sessionTree);
const cspShape = augment(cspSchema, cspTree);
const securityShape = augment(securitySchema, securityTree);
const middlewareShape = augment(middlewareSchema, middlewareTree);
const siteAdminShape = augment(siteAdminSchema, adminTree);
const passphraseShape = augment(passphraseSchema, passphraseTree);
const passwordGenerationShape = augment(passwordGenerationSchema, passwordGenerationTree);
const siteSecretOptionsShape = augment(siteSecretOptionsSchema, siteSecretOptionsTree);

const siteShape = augment(siteSchema, {
  host: (s) => s.default('localhost:3000'),
  ssl: (b) => b.default(false),
  secret_options: siteSecretOptionsTree,
  authentication: authenticationTree,
  session: sessionTree,
  middleware: middlewareTree,
  security: securityTree,
  admin: adminTree,
});

export {
  cspShape,
  middlewareShape,
  passphraseShape,
  passwordGenerationShape,
  securityShape,
  sessionConfigShape,
  siteAdminShape,
  siteAuthenticationShape,
  siteSecretOptionsShape,
  siteShape,
};
