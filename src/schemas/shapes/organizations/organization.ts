// src/schemas/shapes/organizations/organization.ts
//
// Organization shapes with runtime transforms.
// Derives from contracts, adding timestamp transforms and API-response fields.
//
// Architecture: contract → shape → API
// - contracts/organization.ts: Canonical schema + supporting schemas
// - This file: Shapes with transforms for API responses

import {
  organizationCanonical,
  organizationInvitationContractSchema,
  organizationLimitsSchema,
  organizationMemberContractSchema,
  organizationRoleSchema,
  entitlementSchema,
} from '@/schemas/contracts/organization';
import { transforms } from '@/schemas/transforms';
import { z } from 'zod';

// Re-export contracts for backwards compatibility
export * from '@/schemas/contracts/organization';

// ─────────────────────────────────────────────────────────────────────────────
// Timestamp transforms
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Timestamp field overrides.
 * API sends timestamps as Unix epoch numbers; these transform to Date objects.
 */
const timestampOverrides = {
  created: transforms.fromNumber.toDate,
  updated: transforms.fromNumber.toDate,
};

// ─────────────────────────────────────────────────────────────────────────────
// Organization schema
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Organization schema with transforms.
 *
 * Derives from organizationCanonical contract, applies:
 * - Timestamps: number (Unix epoch seconds) -> Date
 * - Nullish normalization: is_default defaults to false
 *
 * Also extends with API-response fields not in the canonical model:
 * - billing_email: Secondary billing contact
 * - member_count: Computed member count
 * - current_user_role: Requesting user's role in this org
 * - entitlements: Plan entitlements array
 * - limits: Plan limits object
 * - domain_count: Computed custom domain count
 *
 * @example
 * ```typescript
 * const org = organizationSchema.parse({
 *   identifier: 'acme-corp',
 *   objid: 'org123',
 *   extid: 'on%org123',
 *   display_name: 'Acme Corporation',
 *   description: 'A great company',
 *   owner_id: 'cust456',
 *   contact_email: 'admin@acme.com',
 *   is_default: false,
 *   planid: 'free',
 *   created: 1609459200,
 *   updated: 1609545600,
 * });
 *
 * console.log(org.created instanceof Date); // true
 * ```
 */
export const organizationSchema = organizationCanonical
  .extend({
    // Timestamp transforms
    ...timestampOverrides,

    // Nullish normalization
    is_default: z.boolean().nullish().transform((v) => v ?? false),

    // API-response fields (not in canonical model)
    billing_email: z.string().email().nullish(),
    member_count: z.number().int().min(0).nullish(),
    current_user_role: organizationRoleSchema.nullish(),
    entitlements: z.array(entitlementSchema).nullish(),
    limits: organizationLimitsSchema.nullish(),
    domain_count: z.number().int().min(0).nullish(),
  });

export type Organization = z.infer<typeof organizationSchema>;

// ─────────────────────────────────────────────────────────────────────────────
// Organization invitation schema
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Organization invitation schema.
 *
 * Currently no transforms - re-exports contract directly.
 * Kept as separate export for backwards compatibility.
 */
export const organizationInvitationSchema = organizationInvitationContractSchema;

export type OrganizationInvitation = z.infer<typeof organizationInvitationSchema>;

// ─────────────────────────────────────────────────────────────────────────────
// Organization member schema
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Organization member schema.
 *
 * Currently no transforms - re-exports contract directly.
 * Kept as separate export for backwards compatibility.
 */
export const organizationMemberSchema = organizationMemberContractSchema;

export type OrganizationMember = z.infer<typeof organizationMemberSchema>;
