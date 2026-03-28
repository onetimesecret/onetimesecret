// src/schemas/shapes/sso-config.ts
//
// DomainSsoConfig shapes with runtime transforms.
// Derives from contracts, adding timestamp transforms.
//
// Architecture: contract -> shape -> API
// - contracts/sso-config.ts: Canonical schema + request payloads
// - This file: Shapes with transforms for API responses

import {
  domainSsoConfigCanonical,
  ssoProviderTypeSchema,
} from '@/schemas/contracts/sso-config';
import { transforms } from '@/schemas/transforms';
import { z } from 'zod';

// Re-export contracts for backwards compatibility
export * from '@/schemas/contracts/sso-config';

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
// DomainSsoConfig schema
// ─────────────────────────────────────────────────────────────────────────────

/**
 * DomainSsoConfig schema with transforms.
 *
 * Derives from domainSsoConfigCanonical contract, applies:
 * - Timestamps: number (Unix epoch seconds) -> Date
 * - Nullish normalization for optional fields
 *
 * @example
 * ```typescript
 * const config = domainSsoConfigSchema.parse({
 *   domain_id: 'domain123',
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
export const domainSsoConfigSchema = domainSsoConfigCanonical
  .extend({
    // Timestamp transforms
    ...timestampOverrides,

    // Nullish normalization for optional fields
    tenant_id: z.string().nullish().transform((v) => v ?? null),
    issuer: z.string().nullish().transform((v) => v ?? null),
    allowed_domains: z.array(z.string()).nullish().transform((v) => v ?? []),
  });

export type DomainSsoConfig = z.infer<typeof domainSsoConfigSchema>;

// ─────────────────────────────────────────────────────────────────────────────
// Deprecated aliases (backward compatibility)
// ─────────────────────────────────────────────────────────────────────────────

/**
 * @deprecated Use domainSsoConfigSchema. SSO config moved from per-org to per-domain.
 */
export const orgSsoConfigSchema = domainSsoConfigSchema;

/**
 * @deprecated Use DomainSsoConfig. SSO config moved from per-org to per-domain.
 */
export type OrgSsoConfig = DomainSsoConfig;

// ─────────────────────────────────────────────────────────────────────────────
// Summary schema (for list views)
// ─────────────────────────────────────────────────────────────────────────────

/**
 * DomainSsoConfig summary schema for list views.
 *
 * Contains only essential fields needed for displaying SSO configs in lists
 * without exposing all configuration details.
 */
export const domainSsoConfigSummarySchema = z.object({
  domain_id: z.string(),
  provider_type: ssoProviderTypeSchema,
  enabled: z.boolean(),
  display_name: z.string(),
  created_at: transforms.fromNumber.toDate,
  updated_at: transforms.fromNumber.toDate,
});

export type DomainSsoConfigSummary = z.infer<typeof domainSsoConfigSummarySchema>;

/**
 * @deprecated Use domainSsoConfigSummarySchema. SSO config moved from per-org to per-domain.
 */
export const orgSsoConfigSummarySchema = domainSsoConfigSummarySchema;

/**
 * @deprecated Use DomainSsoConfigSummary. SSO config moved from per-org to per-domain.
 */
export type OrgSsoConfigSummary = DomainSsoConfigSummary;

// Note: All payload schemas are re-exported via `export * from '@/schemas/contracts/sso-config'` above.
// This includes:
// - createOrUpdateSsoConfigPayloadSchema (legacy, for backwards compatibility)
// - createOrUpdateSsoConfigPayloadStrictSchema (legacy)
// - patchSsoConfigPayloadSchema (PATCH - all fields optional)
// - putSsoConfigPayloadSchema (PUT - required fields enforced)
// - putSsoConfigPayloadStrictSchema (PUT with provider-specific validation)
