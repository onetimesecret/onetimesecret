// src/schemas/contracts/custom-domain/homepage-config.ts
//
// Homepage configuration contract — per-domain homepage secrets settings.
// Gated by the homepage_secrets entitlement (available on free plan).
//
// Architecture: contract -> shape -> API

import { z } from 'zod';

import { disabledHomepageVariantSchema } from '@/schemas/contracts/disabled-homepage';

// ─────────────────────────────────────────────────────────────────────────────
// Homepage config canonical schema
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Canonical homepage configuration contract.
 *
 * Controls whether anonymous users can create secrets on the domain's
 * public homepage. Managed via the /homepage-config endpoint, gated
 * by the homepage_secrets entitlement.
 *
 * @category Contracts
 */
export const homepageConfigCanonical = z.object({
  /** Domain ID (references CustomDomain.identifier). */
  domain_id: z.string(),

  /** Whether homepage secrets is enabled for this domain. */
  enabled: z.boolean().default(false),

  /**
   * Whether the Sign Up link renders on this domain's homepage.
   * Defaults to true (link visible). The site-level authentication.signup
   * flag remains the master switch — the frontend ANDs both layers.
   */
  signup_enabled: z.boolean().default(true),

  /**
   * Whether the Sign In link renders on this domain's homepage.
   * Defaults to true (link visible). The site-level authentication.signin
   * flag remains the master switch — the frontend ANDs both layers.
   */
  signin_enabled: z.boolean().default(true),

  /**
   * Which disabled-homepage variant this domain renders when the homepage
   * secret form is gated by auth. Null means "use the frontend default"
   * (DEFAULT_DISABLED_HOMEPAGE_VARIANT) — operators only set this when
   * they want to deviate from the deployment-wide default.
   *
   * The ?variant URL override still wins for dogfood/preview.
   */
  disabled_homepage_variant: disabledHomepageVariantSchema.nullable().default(null),

  /** Configuration creation timestamp (Unix epoch seconds). Null if unconfigured. */
  created_at: z.number().nullable(),

  /** Last update timestamp (Unix epoch seconds). Null if unconfigured. */
  updated_at: z.number().nullable(),
});

// ─────────────────────────────────────────────────────────────────────────────
// Type exports
// ─────────────────────────────────────────────────────────────────────────────

/** TypeScript type for homepage configuration. */
export type HomepageConfigCanonical = z.infer<typeof homepageConfigCanonical>;
