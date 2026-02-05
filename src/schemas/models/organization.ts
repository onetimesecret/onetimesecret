// src/schemas/models/organization.ts

/**
 * Organization Zod schemas and derived types
 *
 * Schemas are the source of truth for organization data structures.
 * Types are inferred from schemas using z.infer<>.
 *
 * Constants (ENTITLEMENTS, ORGANIZATION_ROLES, etc.) remain in
 * @/types/organization to avoid circular dependencies.
 */

import { z } from 'zod';

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
 */
export const organizationRoleSchema = z.enum(['owner', 'admin', 'member']);

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
  'custom_mail_defaults',
  'custom_branding',
  'branded_homepage',
  'incoming_secrets',
  'manage_orgs',
  'manage_teams',
  'manage_members',
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
 * Organization schema
 *
 * Validates organization data from API responses.
 * Uses lenient ID schemas during migration phase.
 *
 * ID Fields:
 * - id: ObjId - Internal database ID (use for Vue :key, store lookups)
 * - extid: ExtId - External identifier (use for URLs, API paths)
 * - owner_extid: ExtId - External ID of the organization owner (Customer#extid)
 */
export const organizationSchema = z.object({
  id: lenientObjIdSchema,
  extid: lenientExtIdSchema,
  display_name: z.string().min(1).max(100),
  description: z.string().max(500).nullish(),
  contact_email: z.email().nullish(),
  billing_email: z.email().nullish(),
  is_default: z.preprocess((v) => v ?? false, z.boolean()),
  // Backend returns timestamps as strings from Redis, coerce to number then Date
  created: z.coerce.number().transform((val) => new Date(val * 1000)),
  updated: z.coerce.number().transform((val) => new Date(val * 1000)),
  owner_extid: lenientExtIdSchema.nullish(),
  member_count: z.number().int().min(0).nullish(),
  current_user_role: organizationRoleSchema.nullish(),
  planid: z.string().nullish(),
  entitlements: z.array(entitlementSchema).nullish(),
  limits: organizationLimitsSchema.nullish(),
  domain_count: z.number().int().min(0).nullish(),
});

export type Organization = z.infer<typeof organizationSchema>;

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
 * Organization invitation schema
 *
 * Validates invitation data from API responses.
 *
 * ID Fields:
 * - id: ObjId - Internal invitation ID (for store lookups)
 * - organization_id: ExtId - External org ID (backend returns org.extid)
 * - invited_by: ObjId - Internal ID of the user who sent the invitation
 */
export const organizationInvitationSchema = z.object({
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

export type OrganizationInvitation = z.infer<typeof organizationInvitationSchema>;

/**
 * Create invitation request payload schema
 */
export const createInvitationPayloadSchema = z.object({
  email: z.email('Valid email required'),
  role: z.enum(['member', 'admin']),
});

export type CreateInvitationPayload = z.infer<typeof createInvitationPayloadSchema>;

/**
 * Organization member schema
 *
 * Validates response from GET /api/organizations/:extid/members
 */
export const organizationMemberSchema = z.object({
  extid: lenientExtIdSchema,
  email: z.email(),
  role: organizationRoleSchema,
  joined_at: z.number(),
  is_owner: z.boolean(),
  is_current_user: z.boolean(),
});

export type OrganizationMember = z.infer<typeof organizationMemberSchema>;

/**
 * Update member role request payload schema
 */
export const updateMemberRolePayloadSchema = z.object({
  role: z.enum(['admin', 'member']),
});

export type UpdateMemberRolePayload = z.infer<typeof updateMemberRolePayloadSchema>;
