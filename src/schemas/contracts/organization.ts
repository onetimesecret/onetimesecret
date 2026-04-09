// src/schemas/contracts/organization.ts
//
// Organization contracts defining field names and wire format types.
// Shapes transform these to runtime types (e.g., timestamps → Date).
//
// Architecture: contract → shape → API

/**
 * Organization record contracts defining field names and wire format.
 *
 * Organizations (workspaces) represent multi-user accounts that can own
 * secrets, domains, and receipts.
 *
 * This file contains:
 * - organizationCanonical: Canonical field names matching Ruby model
 * - Supporting schemas: limits, entitlements, invitations, members, payloads
 *
 * @module contracts/organization
 * @category Contracts
 * @see {@link "shapes/organizations/organization"} - Shapes with transforms
 */

import { z } from 'zod';

// ─────────────────────────────────────────────────────────────────────────────
// Organization canonical schema
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Canonical organization record contract.
 *
 * Defines field names matching the Ruby Organization model and wire format types.
 * Shapes transform timestamps (number → Date) for runtime use.
 *
 * Organization records track:
 * - Identity: identifier, objid (internal UUID), extid (user-facing ID)
 * - Display: display_name, description
 * - Ownership: owner_id (Customer objid)
 * - Contact: contact_email (primary billing/contact)
 * - Status: is_default (auto-created workspace flag), planid
 * - Timestamps: created, updated (Unix epoch seconds)
 *
 * @see src/tests/stores/organizationStore.spec.ts - Test fixtures for this schema
 * @category Contracts
 */
export const organizationCanonical = z.object({
  /** Object ID (internal UUID, primary key). */
  objid: z.string(),

  /** External ID (user-facing, format: on%<id>s). */
  extid: z.string(),

  /** Organization display name. */
  display_name: z.string(),

  /** Organization description (optional). */
  description: z.string().nullable(),

  /** Owner's Customer objid (nullish: bootstrap payload omits this field). */
  owner_id: z.string().nullish(),

  /** Primary billing/contact email (optional). */
  contact_email: z.string().nullable(),

  /** Whether this is an auto-created default workspace (prevents deletion). */
  is_default: z.boolean(),

  /** Subscription plan ID (defaults to 'free'). */
  planid: z.string(),

  /** Organization creation timestamp (Unix epoch seconds). */
  created: z.number(),

  /** Last update timestamp (Unix epoch seconds). */
  updated: z.number(),
});

// ─────────────────────────────────────────────────────────────────────────────
// Type exports
// ─────────────────────────────────────────────────────────────────────────────

/** TypeScript type for organization record. */
export type OrganizationCanonical = z.infer<typeof organizationCanonical>;

// ─────────────────────────────────────────────────────────────────────────────
// Supporting schemas
// ─────────────────────────────────────────────────────────────────────────────

import { membershipRoleSchema } from '@/schemas/contracts/organization-membership';
import { lenientExtIdSchema, lenientObjIdSchema } from '@/types/identifiers';

/**
 * Organization limits schema
 */
export const organizationLimitsSchema = z.object({
  teams: z.number().optional(),
  members_per_team: z.number().optional(),
  custom_domains: z.number().optional(),
});

export type OrganizationLimits = z.infer<typeof organizationLimitsSchema>;

/**
 * Organization role schema
 *
 * Re-exported from contracts for backwards compatibility.
 * New code should import directly from @/schemas/contracts/organization-membership.
 */
export const organizationRoleSchema = membershipRoleSchema;

export type OrganizationRole = z.infer<typeof organizationRoleSchema>;

/**
 * Entitlement schema
 *
 * Maps to STANDALONE_ENTITLEMENTS in backend (lib/onetime/billing/catalog.rb)
 */
export const entitlementSchema = z.enum([
  // Core entitlements (standalone mode)
  'api_access',
  'custom_domains',
  'custom_privacy_defaults',
  'extended_default_expiration',
  'custom_mail_sender',
  'flexible_from_domain',
  'custom_branding',
  'incoming_secrets',
  'manage_orgs',
  'manage_teams',
  'manage_members',
  'manage_sso',
  'audit_logs',
  // Free tier entitlements (from billing.yaml free_v1 plan)
  'create_secrets',
  'view_receipt',
  // Paid plan entitlements (from billing.yaml)
  'homepage_secrets',
]);

export type Entitlement = z.infer<typeof entitlementSchema>;

/**
 * Invitation status schema
 */
export const invitationStatusSchema = z.enum(['pending', 'accepted', 'declined', 'expired']);

export type InvitationStatus = z.infer<typeof invitationStatusSchema>;

/**
 * Create organization request payload schema
 */
export const createOrganizationPayloadSchema = z.object({
  display_name: z
    .string()
    .min(1, 'Organization name is required')
    .max(100, 'Organization name is too long'),
  description: z.string().max(500, 'Description is too long').optional(),
  contact_email: z.email('Valid email required').optional(),
});

export type CreateOrganizationPayload = z.infer<typeof createOrganizationPayloadSchema>;

/**
 * Update organization request payload schema
 */
export const updateOrganizationPayloadSchema = z.object({
  display_name: z.string().min(1).max(100).optional(),
  description: z.string().max(500).optional(),
  billing_email: z.email('Valid email required').optional(),
});

export type UpdateOrganizationPayload = z.infer<typeof updateOrganizationPayloadSchema>;

/**
 * Organization invitation contract schema
 *
 * Wire format for invitation data from API responses.
 *
 * ID Fields:
 * - id: ObjId - Internal invitation ID (for store lookups)
 * - organization_id: ExtId - External org ID (backend returns org.extid)
 * - invited_by: ObjId - Internal ID of the user who sent the invitation
 *
 * @see src/tests/stores/organizationStore.spec.ts - Test fixtures for this schema
 */
export const organizationInvitationContractSchema = z.object({
  id: lenientObjIdSchema,
  organization_id: lenientExtIdSchema,
  email: z.email(),
  role: z.enum(['member', 'admin']),
  status: invitationStatusSchema,
  invited_by: lenientObjIdSchema,
  invited_at: z.number(),
  expires_at: z.number(),
  resend_count: z.number().int().min(0),
  token: z.string().optional(),
});

export type OrganizationInvitationContract = z.infer<typeof organizationInvitationContractSchema>;

/**
 * Create invitation request payload schema
 */
export const createInvitationPayloadSchema = z.object({
  email: z.email('Valid email required'),
  role: z.enum(['member', 'admin']),
});

export type CreateInvitationPayload = z.infer<typeof createInvitationPayloadSchema>;

/**
 * Organization member contract schema
 *
 * Wire format for GET /api/organizations/:extid/members
 */
export const organizationMemberContractSchema = z.object({
  extid: lenientExtIdSchema,
  email: z.email(),
  role: organizationRoleSchema,
  joined_at: z.number(),
  is_owner: z.boolean(),
  is_current_user: z.boolean(),
});

export type OrganizationMemberContract = z.infer<typeof organizationMemberContractSchema>;

/**
 * Update member role request payload schema
 */
export const updateMemberRolePayloadSchema = z.object({
  role: z.enum(['admin', 'member']),
});

export type UpdateMemberRolePayload = z.infer<typeof updateMemberRolePayloadSchema>;
