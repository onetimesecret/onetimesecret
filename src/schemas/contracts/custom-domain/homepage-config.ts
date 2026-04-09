// src/schemas/contracts/custom-domain/homepage-config.ts
//
// Homepage configuration contract — per-domain homepage secrets settings.
// Gated by the homepage_secrets entitlement (available on free plan).
//
// Architecture: contract -> shape -> API

import { z } from 'zod';

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
