// src/schemas/shapes/organizations/org-sso-config.ts
//
// OrgSsoConfig shapes with runtime transforms.
// Derives from contracts, adding timestamp transforms.
//
// Architecture: contract -> shape -> API
// - contracts/org-sso-config.ts: Canonical schema + request payloads
// - This file: Shapes with transforms for API responses

import {
  orgSsoConfigCanonical,
  ssoProviderTypeSchema,
} from '@/schemas/contracts/org-sso-config';
import { transforms } from '@/schemas/transforms';
import { z } from 'zod';

// Re-export contracts for backwards compatibility
export * from '@/schemas/contracts/org-sso-config';

// ─────────────────────────────────────────────────────────────────────────────
// Timestamp transforms
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Timestamp field overrides.
 * API sends timestamps as Unix epoch numbers; these transform to Date objects.
 */
const timestampOverrides = {
  created_at: transforms.fromNumber.toDate,
  updated_at: transforms.fromNumber.toDate,
};

// ─────────────────────────────────────────────────────────────────────────────
// OrgSsoConfig schema
// ─────────────────────────────────────────────────────────────────────────────

/**
 * OrgSsoConfig schema with transforms.
 *
 * Derives from orgSsoConfigCanonical contract, applies:
 * - Timestamps: number (Unix epoch seconds) -> Date
 * - Nullish normalization for optional fields
 *
 * @example
 * ```typescript
 * const config = orgSsoConfigSchema.parse({
 *   org_id: 'org123',
 *   provider_type: 'entra_id',
 *   enabled: true,
 *   display_name: 'Acme Corp SSO',
 *   client_id: 'abc123',
 *   client_secret_masked: '••••5678',
 *   tenant_id: 'tenant-uuid',
 *   issuer: null,
 *   allowed_domains: ['acme.com'],
 *   created_at: 1609459200,
 *   updated_at: 1609545600,
 * });
 *
 * console.log(config.created_at instanceof Date); // true
 * ```
 */
export const orgSsoConfigSchema = orgSsoConfigCanonical
  .extend({
    // Timestamp transforms
    ...timestampOverrides,

    // Nullish normalization for optional fields
    tenant_id: z.string().nullish().transform((v) => v ?? null),
    issuer: z.string().nullish().transform((v) => v ?? null),
    allowed_domains: z.array(z.string()).nullish().transform((v) => v ?? []),
  });

export type OrgSsoConfig = z.infer<typeof orgSsoConfigSchema>;

// ─────────────────────────────────────────────────────────────────────────────
// Summary schema (for list views)
// ─────────────────────────────────────────────────────────────────────────────

/**
 * OrgSsoConfig summary schema for list views.
 *
 * Contains only essential fields needed for displaying SSO configs in lists
 * without exposing all configuration details.
 */
export const orgSsoConfigSummarySchema = z.object({
  org_id: z.string(),
  provider_type: ssoProviderTypeSchema,
  enabled: z.boolean(),
  display_name: z.string(),
  created_at: transforms.fromNumber.toDate,
  updated_at: transforms.fromNumber.toDate,
});

export type OrgSsoConfigSummary = z.infer<typeof orgSsoConfigSummarySchema>;

// Note: All payload schemas are re-exported via `export * from '@/schemas/contracts/org-sso-config'` above.
// This includes:
// - createOrUpdateSsoConfigPayloadSchema (legacy, for backwards compatibility)
// - createOrUpdateSsoConfigPayloadStrictSchema (legacy)
// - patchSsoConfigPayloadSchema (PATCH - all fields optional)
// - putSsoConfigPayloadSchema (PUT - required fields enforced)
// - putSsoConfigPayloadStrictSchema (PUT with provider-specific validation)
