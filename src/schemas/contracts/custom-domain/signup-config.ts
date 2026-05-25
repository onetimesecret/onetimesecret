// src/schemas/contracts/custom-domain/signup-config.ts
//
// CustomDomain::SignupConfig contracts defining field names and wire format types.
// Shapes transform these to runtime types (e.g., timestamps -> Date).
//
// Architecture: contract -> shape -> API

/**
 * Per-Domain Signup Validation Configuration contracts.
 *
 * Stores email validation strategy for custom domains so each domain can
 * apply its own signup policy (format-only, allowlist, MX lookup, or full
 * SMTP probe) independent of the global default.
 *
 * Design Decisions:
 *
 * 1. One-to-One with Domain: Each custom domain has at most one signup
 *    config. The domain_id field is the identifier.
 *
 * 2. Strategy Types: Four supported strategies map to escalating validation
 *    rigor: 'passthrough' (format only), 'domain_allowlist' (against an
 *    operator-curated list), 'mx' (DNS MX lookup), 'smtp' (full SMTP probe).
 *
 * 3. Allowlist Semantics: The allowed_signup_domains list is only consulted
 *    when validation_strategy is 'domain_allowlist'. Other strategies ignore
 *    the list entirely.
 *
 * 4. No Sensitive Fields: Unlike SsoConfig, SignupConfig contains no
 *    secrets — all fields are safe to log and display directly.
 *
 * @module contracts/custom-domain/signup-config
 * @category Contracts
 * @see {@link "shapes/domains/signup-config"} - Shapes with transforms
 */

import { z } from 'zod';

// ─────────────────────────────────────────────────────────────────────────────
// Strategy type schema
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Supported signup validation strategies.
 *
 * - passthrough: Format check only — accepts any syntactically valid email
 * - domain_allowlist: Email domain must appear in allowed_signup_domains
 * - mx: Validates email domain has MX records (DNS lookup)
 * - smtp: Full SMTP validation — strictest, may be slow
 *
 * @category Contracts
 */
export const signupValidationStrategySchema = z.enum([
  'passthrough',
  'domain_allowlist',
  'mx',
  'smtp',
]);

export type SignupValidationStrategy = z.infer<typeof signupValidationStrategySchema>;

/**
 * Strategy metadata for UI behavior.
 *
 * Mirrors STRATEGY_METADATA in lib/onetime/models/custom_domain/signup_config.rb.
 * Used by forms to determine when the allowlist field should be shown/required
 * and to surface network-validation warnings.
 */
export const SIGNUP_STRATEGY_METADATA: Record<SignupValidationStrategy, {
  requiresAllowlist: boolean;
  networkValidation: boolean;
  description: string;
}> = {
  passthrough: {
    requiresAllowlist: false,
    networkValidation: false,
    description: 'Format check only — accepts any valid email format',
  },
  domain_allowlist: {
    requiresAllowlist: true,
    networkValidation: false,
    description: 'Email domain must be in the configured allowed list',
  },
  mx: {
    requiresAllowlist: false,
    networkValidation: true,
    description: 'Validates email domain has MX records (DNS lookup)',
  },
  smtp: {
    requiresAllowlist: false,
    networkValidation: true,
    description: 'Full SMTP validation — strictest, may be slow',
  },
} as const;

// ─────────────────────────────────────────────────────────────────────────────
// Canonical schema
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Canonical CustomDomain::SignupConfig contract schema.
 *
 * Defines field names matching the Ruby CustomDomain::SignupConfig model and
 * wire format. Shapes transform timestamps (number -> Date) for runtime use.
 *
 * @see lib/onetime/models/custom_domain/signup_config.rb - Backend model
 * @category Contracts
 */
export const customDomainSignupConfigCanonical = z.object({
  /** Domain ID (references CustomDomain.extid). */
  domain_id: z.string(),

  /** Validation strategy in effect for this domain. */
  validation_strategy: signupValidationStrategySchema,

  /**
   * Email domains allowed to sign up on this custom domain.
   * Only consulted when validation_strategy is 'domain_allowlist'.
   * Empty array means no allowlist configured.
   */
  allowed_signup_domains: z.array(z.string()),

  /** Whether this per-domain signup config is active. */
  enabled: z.boolean(),

  /**
   * Whether the current strategy requires an allowlist.
   * Read-only, computed from validation_strategy.
   */
  requires_allowlist: z.boolean(),

  /**
   * Whether the current strategy performs network calls (DNS or SMTP).
   * Read-only, computed from validation_strategy.
   */
  network_validation: z.boolean(),

  /** Configuration creation timestamp (Unix epoch seconds). */
  created_at: z.number(),

  /** Last update timestamp (Unix epoch seconds). */
  updated_at: z.number(),
});

// ─────────────────────────────────────────────────────────────────────────────
// Type exports
// ─────────────────────────────────────────────────────────────────────────────

/** TypeScript type for CustomDomain::SignupConfig wire format. */
export type CustomDomainSignupConfigCanonical = z.infer<typeof customDomainSignupConfigCanonical>;

// ─────────────────────────────────────────────────────────────────────────────
// PUT payload schema (full replacement)
// ─────────────────────────────────────────────────────────────────────────────

/**
 * PUT signup configuration request payload schema.
 *
 * Full replacement semantics: the request body IS the new state.
 *
 * @category Contracts
 */
export const putSignupConfigPayloadSchema = z.object({
  /** Validation strategy to apply. */
  validation_strategy: signupValidationStrategySchema,

  /**
   * Email domain allowlist (required when validation_strategy is
   * 'domain_allowlist', ignored otherwise).
   */
  allowed_signup_domains: z.array(z.string()).optional(),

  /** Whether the per-domain config is active. Defaults to false. */
  enabled: z.boolean().optional(),
});

/**
 * PUT signup config payload with strategy-specific validation.
 *
 * domain_allowlist strategy requires at least one entry in
 * allowed_signup_domains.
 */
export const putSignupConfigPayloadStrictSchema = putSignupConfigPayloadSchema.superRefine(
  (data, ctx) => {
    if (data.validation_strategy === 'domain_allowlist') {
      const list = data.allowed_signup_domains ?? [];
      if (list.length === 0) {
        ctx.addIssue({
          code: z.ZodIssueCode.custom,
          message: 'allowed_signup_domains is required when validation_strategy is domain_allowlist',
          path: ['allowed_signup_domains'],
        });
      }
    }
  }
);

export type PutSignupConfigPayload = z.infer<typeof putSignupConfigPayloadSchema>;
export type PutSignupConfigPayloadStrict = z.infer<typeof putSignupConfigPayloadStrictSchema>;
