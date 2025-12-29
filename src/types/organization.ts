// src/types/organization.ts

/**
 * Organization management type definitions
 * Used across organization components, stores, and views
 */

import { z } from 'zod';

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
 */
export interface Organization {
  id: string;
  extid?: string;
  display_name: string;
  description?: string;
  contact_email?: string;
  is_default: boolean;
  created_at: Date;
  updated_at: Date;
  owner_id?: string;
  member_count?: number;
  current_user_role?: OrganizationRole;
  planid?: string;
  entitlements?: Entitlement[];
  limits?: OrganizationLimits;
}

/**
 * Zod schemas for validation
 */

export const organizationSchema = z.object({
  id: z.string(),
  extid: z.string().optional(),
  display_name: z.string().min(1).max(100),
  description: z.string().max(500).optional(),
  contact_email: z.string().email().optional(),
  is_default: z.boolean(),
  created_at: z.number().transform((val) => new Date(val * 1000)),
  updated_at: z.number().transform((val) => new Date(val * 1000)),
  owner_id: z.string().optional(),
  member_count: z.number().int().min(0).optional(),
  current_user_role: z.enum(['owner', 'admin', 'member']).optional(),
  planid: z.string().optional(),
  entitlements: z.array(z.string() as z.ZodType<Entitlement>).optional(),
  limits: z
    .object({
      teams: z.number().optional(),
      members_per_team: z.number().optional(),
      custom_domains: z.number().optional(),
    })
    .optional(),
});

/**
 * Request payload schemas
 */

export const createOrganizationPayloadSchema = z.object({
  display_name: z.string().min(1, 'Organization name is required').max(100, 'Organization name is too long'),
  description: z.string().max(500, 'Description is too long').optional(),
  contact_email: z.string().email('Valid email required').optional(),
});

export const updateOrganizationPayloadSchema = z.object({
  display_name: z.string().min(1).max(100).optional(),
  description: z.string().max(500).optional(),
  contact_email: z.string().email().optional(),
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
 */
export interface OrganizationInvitation {
  id: string;
  organization_id: string;
  email: string;
  role: 'member' | 'admin';
  status: InvitationStatus;
  invited_by: string;
  invited_at: number;
  expires_at: number;
  resend_count: number;
  token?: string;
}

/**
 * Organization invitation schemas
 */
export const organizationInvitationSchema = z.object({
  id: z.string(),
  organization_id: z.string(),
  email: z.string().email(),
  role: z.enum(['member', 'admin']),
  status: z.enum(['pending', 'accepted', 'declined', 'expired']),
  invited_by: z.string(),
  invited_at: z.number(),
  expires_at: z.number(),
  resend_count: z.number().int().min(0),
  token: z.string().optional(),
});

export const createInvitationPayloadSchema = z.object({
  email: z.string().email('Valid email required'),
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
 */
export interface OrganizationMember {
  id: string;
  extid: string;
  user_id: string;
  organization_id: string;
  email: string;
  display_name?: string;
  role: OrganizationRole;
  joined_at: Date;
  updated_at: Date;
}

/**
 * Organization member schema
 */
export const organizationMemberSchema = z.object({
  id: z.string(),
  extid: z.string(),
  user_id: z.string(),
  organization_id: z.string(),
  email: z.string().email(),
  display_name: z.string().optional(),
  role: z.enum(['owner', 'admin', 'member']),
  joined_at: z.number().transform((val) => new Date(val * 1000)),
  updated_at: z.number().transform((val) => new Date(val * 1000)),
});

/**
 * Update member role payload schema
 */
export const updateMemberRolePayloadSchema = z.object({
  role: z.enum(['admin', 'member']),
});

export type UpdateMemberRolePayload = z.infer<typeof updateMemberRolePayloadSchema>;
