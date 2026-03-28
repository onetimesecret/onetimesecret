// src/schemas/shapes/domains/sso-config.ts
//
// DomainSsoConfig shapes with runtime transforms.
// Derives from contracts, adding timestamp transforms and null normalization.
//
// Architecture: contract → shape → API
// - contracts/sso-config.ts: Canonical schema (pure fields, nullable types)
// - This file: Shapes with transforms for API responses
//
// Null handling strategy:
// - Contract layer declares nullability to match wire format
// - Shape layer transforms null → safe defaults for frontend consumption
// - Required form fields (client_id, display_name) → empty string
// - Optional form fields (tenant_id, issuer) → null (form uses undefined)

import {
  domainSsoConfigCanonical,
  ssoProviderTypeSchema,
} from '@/schemas/contracts/sso-config';
import { transforms } from '@/schemas/transforms';
import { z } from 'zod';

// Re-export contracts for type access
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
 * - Timestamps: number (Unix epoch seconds) → Date
 * - Required field normalization: null → empty string (client_id)
 * - Optional field normalization: null preserved for tenant_id, issuer
 * - Array normalization: null → empty array (allowed_domains)
 *
 * Form layer converts null → undefined for optional fields; this shape
 * ensures required fields are never null.
 *
 * @example
 * ```typescript
 * const config = domainSsoConfigSchema.parse({
 *   domain_id: 'domain123',
 *   provider_type: 'entra_id',
 *   enabled: true,
 *   display_name: 'Acme Corp SSO',
 *   client_id: null,  // → '' after transform
 *   client_secret_masked: '••••5678',
 *   tenant_id: null,  // → null (form converts to undefined)
 *   issuer: null,
 *   allowed_domains: null,  // → []
 *   created_at: 1609459200,
 *   updated_at: 1609545600,
 * });
 *
 * console.log(config.client_id); // ''
 * console.log(config.created_at instanceof Date); // true
 * ```
 */
export const domainSsoConfigSchema = domainSsoConfigCanonical
  .extend({
    // Timestamp transforms
    ...timestampOverrides,

    // Required field normalization: null → empty string
    // These fields are required for form submission; null breaks .trim() calls
    client_id: z.string().nullable().transform((v) => v ?? ''),

    // Optional field normalization: keep null (form layer converts to undefined)
    tenant_id: z.string().nullish().transform((v) => v ?? null),
    issuer: z.string().nullish().transform((v) => v ?? null),

    // Array normalization: null → empty array
    allowed_domains: z.array(z.string()).nullish().transform((v) => v ?? []),
  });

export type DomainSsoConfig = z.infer<typeof domainSsoConfigSchema>;

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

/**
 * @deprecated Use domainSsoConfigSummarySchema. SSO config moved from per-org to per-domain.
 */
export const orgSsoConfigSummarySchema = domainSsoConfigSummarySchema;

/**
 * @deprecated Use DomainSsoConfigSummary. SSO config moved from per-org to per-domain.
 */
export type OrgSsoConfigSummary = DomainSsoConfigSummary;
