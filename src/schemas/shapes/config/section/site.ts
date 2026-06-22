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
import { augment, type AugmentTree } from '@/schemas/utils/augment';

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

export type {
  SessionConfig,
  MiddlewareConfig,
  CspConfig,
  SecurityConfig,
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
};

const cspTree: AugmentTree = {
  // CSP now ships enabled-by-default but staged in report-only mode.
  // @sync etc/defaults/config.defaults.yaml (site.security.csp)
  enabled: (b) => b.default(true),
  report_only: (b) => b.default(true),
  report_uri: (s) => s.nullable().default(null),
};

const securityTree: AugmentTree = {
  csp: cspTree,
};

// Secure-by-default middleware toggles.
// @sync etc/defaults/config.defaults.yaml (site.middleware)
const middlewareTree: AugmentTree = {
  static_files: (b) => b.default(true),
  utf8_sanitizer: (b) => b.default(true),
  authenticity_token: (b) => b.default(true),
  http_origin: (b) => b.default(true),
  xss_header: (b) => b.default(true),
  frame_options: (b) => b.default(true),
  path_traversal: (b) => b.default(false),
  cookie_tossing: (b) => b.default(false),
  ip_spoofing: (b) => b.default(false),
  // Effective server-side default tracks SSL (on under HTTPS, off in plain-HTTP
  // dev); false is the conservative client-side fallback when unspecified.
  strict_transport: (b) => b.default(false),
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
