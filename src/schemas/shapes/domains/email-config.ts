// src/schemas/shapes/domains/email-config.ts
//
// CustomDomain::EmailConfig shapes with runtime transforms.
// Derives from contracts, adding timestamp transforms and null normalization.
//
// Architecture: contract -> shape -> API
// - contracts/email-config.ts: Canonical schema (pure fields, nullable types)
// - This file: Shapes with transforms for API responses
//
// Null handling strategy:
// - Contract layer declares nullability to match wire format
// - Shape layer transforms null -> safe defaults for frontend consumption
// - Required form fields (from_address, from_name) -> empty string
// - Optional form fields (reply_to, provider_domain_id) -> null

import {
  customDomainEmailConfigCanonical,
  emailProviderTypeSchema,
  emailVerificationStatusSchema,
} from '@/schemas/contracts/email-config';
import { transforms } from '@/schemas/transforms';
import { z } from 'zod';

// Re-export contracts for type access
export * from '@/schemas/contracts/email-config';

// ---------------------------------------------------------------------------
// Timestamp transforms
// ---------------------------------------------------------------------------

/**
 * Timestamp field overrides.
 * API sends timestamps as Unix epoch numbers; these transform to Date objects.
 */
const timestampOverrides = {
  created_at: transforms.fromNumber.toDate,
  updated_at: transforms.fromNumber.toDate,
};

// ---------------------------------------------------------------------------
// CustomDomain::EmailConfig schema
// ---------------------------------------------------------------------------

/**
 * CustomDomain::EmailConfig schema with transforms.
 *
 * Derives from customDomainEmailConfigCanonical contract, applies:
 * - Timestamps: number (Unix epoch seconds) -> Date
 * - Required field normalization: null -> empty string (from_address, from_name)
 * - Optional field normalization: null preserved for reply_to, provider_domain_id
 * - last_validated_at: nullable number -> nullable Date
 *
 * @example
 * ```typescript
 * const config = customDomainEmailConfigSchema.parse({
 *   domain_id: 'domain123',
 *   provider: 'ses',
 *   from_address: null,         // -> '' after transform
 *   from_name: null,            // -> '' after transform
 *   reply_to: null,             // -> null (form converts to undefined)
 *   verification_status: 'pending',
 *   dns_records: [],
 *   last_validated_at: null,    // -> null
 *   provider_domain_id: null,   // -> null
 *   created_at: 1609459200,
 *   updated_at: 1609545600,
 * });
 *
 * console.log(config.from_address); // ''
 * console.log(config.created_at instanceof Date); // true
 * ```
 */
export const customDomainEmailConfigSchema = customDomainEmailConfigCanonical
  .extend({
    // Timestamp transforms
    ...timestampOverrides,

    // Required field normalization: null -> empty string
    // These fields are required for form submission; null breaks .trim() calls
    from_address: z.string().nullable().transform((v) => v ?? ''),
    from_name: z.string().nullable().transform((v) => v ?? ''),

    // Optional field normalization: keep null (form layer converts to undefined)
    reply_to: z.string().nullish().transform((v) => v ?? null),
    provider_domain_id: z.string().nullish().transform((v) => v ?? null),

    // Nullable timestamp -> nullable Date
    last_validated_at: z.number().nullable().transform((v) =>
      v !== null ? new Date(v * 1000) : null
    ),

    dns_check_completed_at: z.number().nullable().transform((v) =>
      v !== null ? new Date(v * 1000) : null
    ),

    provider_check_completed_at: z.number().nullable().transform((v) =>
      v !== null ? new Date(v * 1000) : null
    ),
  });

export type CustomDomainEmailConfig = z.infer<typeof customDomainEmailConfigSchema>;

// ---------------------------------------------------------------------------
// Summary schema (for list views)
// ---------------------------------------------------------------------------

/**
 * CustomDomain::EmailConfig summary schema for list views.
 *
 * Contains only essential fields needed for displaying email configs in lists
 * without exposing all configuration details.
 */
export const customDomainEmailConfigSummarySchema = z.object({
  domain_id: z.string(),
  provider: emailProviderTypeSchema,
  from_address: z.string(),
  verification_status: emailVerificationStatusSchema,
  created_at: transforms.fromNumber.toDate,
  updated_at: transforms.fromNumber.toDate,
});

export type CustomDomainEmailConfigSummary = z.infer<typeof customDomainEmailConfigSummarySchema>;
