// src/types/organization.ts

/**
 * Organization management type definitions
 * Used across organization components, stores, and views
 */

import { z } from 'zod';

import {
  ExtId,
  ObjId,
  lenientExtIdSchema,
  lenientObjIdSchema,
} from './identifiers';

/**
 * Organization entitlement constants
 *
 * These map to STANDALONE_ENTITLEMENTS in the backend (lib/onetime/billing/catalog.rb)
 * Used for feature gating based on plan tier.
 */
export const ENTITLEMENTS = {
  // Infrastructure
  API_ACCESS: 'api_access',
  CUSTOM_DOMAINS: 'custom_domains',

  // Privacy & Defaults
  CUSTOM_PRIVACY_DEFAULTS: 'custom_privacy_defaults',
  EXTENDED_DEFAULT_EXPIRATION: 'extended_default_expiration',
  CUSTOM_MAIL_DEFAULTS: 'custom_mail_defaults',

  // Branding
  CUSTOM_BRANDING: 'custom_branding',
  BRANDED_HOMEPAGE: 'branded_homepage',

  // Secret Features
  INCOMING_SECRETS: 'incoming_secrets',

  // Organization Management
  MANAGE_ORGS: 'manage_orgs',
  MANAGE_TEAMS: 'manage_teams',
  MANAGE_MEMBERS: 'manage_members',

  // Advanced
  AUDIT_LOGS: 'audit_logs',
} as const;

export type Entitlement = (typeof ENTITLEMENTS)[keyof typeof ENTITLEMENTS];

/**
 * Organization limits interface
 */
export interface OrganizationLimits {
  teams?: number;
  members_per_team?: number;
  custom_domains?: number;
}

/**
 * Organization role constants
 */
export const ORGANIZATION_ROLES = {
  OWNER: 'owner',
  ADMIN: 'admin',
  MEMBER: 'member',
} as const;

export type OrganizationRole = (typeof ORGANIZATION_ROLES)[keyof typeof ORGANIZATION_ROLES];

/**
 * Organization interface
 *
 * Note: Fields use `| null` to match backend safe_dump which returns null for empty fields.
 *
 * ID Fields:
 * - id: ObjId - Internal database ID (use for Vue :key, store lookups)
 * - extid: ExtId - External identifier (use for URLs, API paths)
 * - owner_extid: ExtId - External ID of the organization owner (Customer#extid)
 */
export interface Organization {
  id: ObjId;
  extid: ExtId;
  display_name: string;
  description?: string | null;
  contact_email?: string | null;
  /** Whether this is the user's default organization. Always boolean (defaults to false). */
  is_default: boolean;
  created_at: Date;
  updated_at: Date;
  /** External ID of organization owner (Customer#extid) - use for display, not lookups */
  owner_extid?: ExtId | null;
  member_count?: number | null;
  current_user_role?: OrganizationRole | null;
  planid?: string | null;
  entitlements?: Entitlement[] | null;
  limits?: OrganizationLimits | null;
}

/**
 * Zod schemas for validation
 */

export const organizationSchema = z.object({
  // Use lenient schemas during migration - accepts any string but brands the output
  id: lenientObjIdSchema,
  extid: lenientExtIdSchema,
  display_name: z.string().min(1).max(100),
  description: z.string().max(500).nullish(),
  contact_email: z.email().nullish(),
  is_default: z.preprocess((v) => v ?? false, z.boolean()),
  created_at: z.number().transform((val) => new Date(val * 1000)),
  updated_at: z.number().transform((val) => new Date(val * 1000)),
  owner_extid: lenientExtIdSchema.nullish(),
  member_count: z.number().int().min(0).nullish(),
  current_user_role: z.enum(['owner', 'admin', 'member']).nullish(),
  planid: z.string().nullish(),
  entitlements: z.array(z.string() as z.ZodType<Entitlement>).nullish(),
  limits: z
    .object({
      teams: z.number().optional(),
      members_per_team: z.number().optional(),
      custom_domains: z.number().optional(),
    })
    .nullish(),
});

/**
 * Request payload schemas
 */

export const createOrganizationPayloadSchema = z.object({
  display_name: z
    .string()
    .min(1, 'Organization name is required')
    .max(100, 'Organization name is too long'),
  description: z.string().max(500, 'Description is too long').optional(),
  contact_email: z.email('Valid email required').optional(),
});

export const updateOrganizationPayloadSchema = z.object({
  display_name: z.string().min(1).max(100).optional(),
  description: z.string().max(500).optional(),
});

/**
 * Type exports from schemas
 */
export type CreateOrganizationPayload = z.infer<typeof createOrganizationPayloadSchema>;
export type UpdateOrganizationPayload = z.infer<typeof updateOrganizationPayloadSchema>;

/**
 * Organization invitation status constants
 */
export const INVITATION_STATUSES = {
  PENDING: 'pending',
  ACCEPTED: 'accepted',
  DECLINED: 'declined',
  EXPIRED: 'expired',
} as const;

export type InvitationStatus = (typeof INVITATION_STATUSES)[keyof typeof INVITATION_STATUSES];

/**
 * Organization invitation interface
 *
 * ID Fields:
 * - id: ObjId - Internal invitation ID (for store lookups)
 * - organization_id: ExtId - External org ID (backend returns org.extid)
 * - invited_by: ObjId - Internal ID of the user who sent the invitation
 */
export interface OrganizationInvitation {
  id: ObjId;
  organization_id: ExtId;
  email: string;
  role: 'member' | 'admin';
  status: InvitationStatus;
  invited_by: ObjId;
  invited_at: number;
  expires_at: number;
  resend_count: number;
  token?: string;
}

/**
 * Organization invitation schemas
 */
export const organizationInvitationSchema = z.object({
  id: lenientObjIdSchema,
  organization_id: lenientExtIdSchema, // Backend returns org.extid
  email: z.email(),
  role: z.enum(['member', 'admin']),
  status: z.enum(['pending', 'accepted', 'declined', 'expired']),
  invited_by: lenientObjIdSchema,
  invited_at: z.number(),
  expires_at: z.number(),
  resend_count: z.number().int().min(0),
  token: z.string().optional(),
});

export const createInvitationPayloadSchema = z.object({
  email: z.email('Valid email required'),
  role: z.enum(['member', 'admin']),
});

export type CreateInvitationPayload = z.infer<typeof createInvitationPayloadSchema>;

/**
 * Display helpers
 */

export function getOrganizationLabel(org: Organization): string {
  return org.display_name;
}

/**
 * Organization member interface
 *
 * Matches backend response from apps/api/organizations/logic/members/list_members.rb
 */
export interface OrganizationMember {
  /** Member's external ID - use in URLs and API calls */
  extid: ExtId;
  email: string;
  role: OrganizationRole;
  joined_at: number; // Unix timestamp
  is_owner: boolean;
  is_current_user: boolean;
}

/**
 * Organization member schema
 *
 * Validates response from GET /api/organizations/:extid/members
 */
export const organizationMemberSchema = z.object({
  extid: lenientExtIdSchema,
  email: z.email(),
  role: z.enum(['owner', 'admin', 'member']),
  joined_at: z.number(),
  is_owner: z.boolean(),
  is_current_user: z.boolean(),
});

/**
 * Update member role payload schema
 */
export const updateMemberRolePayloadSchema = z.object({
  role: z.enum(['admin', 'member']),
});

export type UpdateMemberRolePayload = z.infer<typeof updateMemberRolePayloadSchema>;
