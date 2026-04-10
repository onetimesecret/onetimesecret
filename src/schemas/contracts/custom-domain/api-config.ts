// src/schemas/contracts/custom-domain/api-config.ts
//
// API access configuration contract — per-domain API access settings.
// Gated by the api_access entitlement (available on free plan).
//
// Architecture: contract -> shape -> API

import { z } from 'zod';

// ─────────────────────────────────────────────────────────────────────────────
// API config canonical schema
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Canonical API access configuration contract.
 *
 * Controls whether anonymous users can use the API against this domain.
 * Managed via the /api-config endpoint, gated by the api_access entitlement.
 *
 * @category Contracts
 */
export const apiConfigCanonical = z.object({
  /** Domain ID (references CustomDomain.identifier). */
  domain_id: z.string(),

  /** Whether public API access is enabled for this domain. */
  enabled: z.boolean().default(false),

  /** Configuration creation timestamp (Unix epoch seconds). Null if unconfigured. */
  created_at: z.number().nullable(),

  /** Last update timestamp (Unix epoch seconds). Null if unconfigured. */
  updated_at: z.number().nullable(),
});

// ─────────────────────────────────────────────────────────────────────────────
// Type exports
// ─────────────────────────────────────────────────────────────────────────────

/** TypeScript type for API access configuration. */
export type ApiConfigCanonical = z.infer<typeof apiConfigCanonical>;
