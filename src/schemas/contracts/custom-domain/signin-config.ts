// src/schemas/contracts/custom-domain/signin-config.ts
//
// CustomDomain::SigninConfig contracts defining field names and wire format types.
// Shapes transform these to runtime types (e.g., timestamps -> Date).
//
// Architecture: contract -> shape -> API

/**
 * Per-Domain Sign-In Configuration contracts.
 *
 * Controls sign-in behavior on a custom domain: whether signin is available,
 * which authentication methods are offered, and whether to restrict to a
 * single method. Mirrors the install-level AUTH_SIGNIN / restrict_to /
 * feature toggles but scoped per domain.
 *
 * Design Decisions:
 *
 * 1. One-to-One with Domain: Each custom domain has at most one signin
 *    config. The domain_id field is the identifier.
 *
 * 2. Nullable Overrides: Boolean fields use nullable semantics — null means
 *    "inherit the install-level default." Only explicit true/false overrides.
 *
 * 3. restrict_to: Mirrors auth.defaults.yaml full.restrict_to. When set,
 *    only that single method is shown on the login page. The underlying
 *    feature must also be enabled (install-level or domain-level).
 *
 * 4. No Sensitive Fields: SigninConfig contains no secrets — all fields
 *    are safe to log and display directly.
 *
 * 5. Scope Boundary: Install-wide security posture (MFA, lockout,
 *    password_requirements, active_sessions) is NOT overridable per
 *    domain — those are infrastructure, not tenant configuration.
 *
 * @module contracts/custom-domain/signin-config
 * @category Contracts
 */

import { z } from 'zod';

// ─────────────────────────────────────────────────────────────────────────────
// Auth method restriction schema
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Authentication method values for restrict_to.
 *
 * Mirrors RestrictTo in src/utils/features.ts and the valid values for
 * full.restrict_to in auth.defaults.yaml.
 *
 * @category Contracts
 */
export const signinRestrictToSchema = z.enum([
  'password',
  'email_auth',
  'webauthn',
  'sso',
]);

export type SigninRestrictTo = z.infer<typeof signinRestrictToSchema>;

/**
 * Method metadata for UI behavior.
 *
 * Used by forms to describe each restriction option and its implications.
 */
export const SIGNIN_RESTRICT_TO_METADATA: Record<SigninRestrictTo, {
  description: string;
  requiresFeature: string;
}> = {
  password: {
    description: 'Password-only — hides all other sign-in methods',
    requiresFeature: 'Password authentication (always available)',
  },
  email_auth: {
    description: 'Email auth only — passwordless magic link sign-in',
    requiresFeature: 'AUTH_EMAIL_AUTH_ENABLED=true',
  },
  webauthn: {
    description: 'WebAuthn only — biometrics and security keys',
    requiresFeature: 'AUTH_WEBAUTHN_ENABLED=true',
  },
  sso: {
    description: 'SSO only — external identity provider, disables password management',
    requiresFeature: 'AUTH_SSO_ENABLED=true + provider configured',
  },
} as const;

// ─────────────────────────────────────────────────────────────────────────────
// Canonical schema
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Canonical CustomDomain::SigninConfig contract schema.
 *
 * Defines field names matching the (future) Ruby CustomDomain::SigninConfig
 * model and wire format. Shapes transform timestamps for runtime use.
 *
 * @category Contracts
 */
export const customDomainSigninConfigCanonical = z.object({
  /** Domain ID (references CustomDomain.extid). */
  domain_id: z.string(),

  /** Whether this per-domain signin config is active. */
  enabled: z.boolean(),

  /**
   * Domain-level override for AUTH_SIGNIN.
   * When false, the signin page is disabled on this custom domain.
   * Null inherits the install-level default.
   */
  signin_enabled: z.boolean().nullable(),

  /**
   * Restrict the login page to a single authentication method.
   * Null shows all enabled methods (default behavior).
   *
   * Mirrors full.restrict_to in auth.defaults.yaml. The underlying
   * feature must be enabled at the install level.
   */
  restrict_to: signinRestrictToSchema.nullable(),

  /**
   * Domain-level override for email auth / magic links.
   * Null inherits the install-level AUTH_EMAIL_AUTH_ENABLED setting.
   */
  email_auth_enabled: z.boolean().nullable(),

  /**
   * Domain-level override for SSO availability.
   * Null inherits the install-level AUTH_SSO_ENABLED setting.
   * When true, the domain must also have a valid SsoConfig.
   */
  sso_enabled: z.boolean().nullable(),

  /** Configuration creation timestamp (Unix epoch seconds). */
  created_at: z.number(),

  /** Last update timestamp (Unix epoch seconds). */
  updated_at: z.number(),
});

// ─────────────────────────────────────────────────────────────────────────────
// Type exports
// ─────────────────────────────────────────────────────────────────────────────

/** TypeScript type for CustomDomain::SigninConfig wire format. */
export type CustomDomainSigninConfigCanonical = z.infer<typeof customDomainSigninConfigCanonical>;

// ─────────────────────────────────────────────────────────────────────────────
// PUT payload schema (full replacement)
// ─────────────────────────────────────────────────────────────────────────────

/**
 * PUT signin configuration request payload schema.
 *
 * Full replacement semantics: the request body IS the new state.
 *
 * @category Contracts
 */
export const putSigninConfigPayloadSchema = z.object({
  /** Whether the per-domain config is active. Defaults to false. */
  enabled: z.boolean().optional(),

  /** Domain-level override for signin availability. Null to inherit global default. */
  signin_enabled: z.boolean().nullable().optional(),

  /** Restrict login page to a single method. Null to show all enabled methods. */
  restrict_to: signinRestrictToSchema.nullable().optional(),

  /** Domain-level override for email auth. Null to inherit global default. */
  email_auth_enabled: z.boolean().nullable().optional(),

  /** Domain-level override for SSO. Null to inherit global default. */
  sso_enabled: z.boolean().nullable().optional(),
});

export type PutSigninConfigPayload = z.infer<typeof putSigninConfigPayloadSchema>;
