// src/types/organization.ts

/**
 * Organization management type definitions
 * Used across organization components, stores, and views
 */

import { z } from 'zod';

/**
 * Organization entitlement constants
 */
export const ENTITLEMENTS = {
  // Core
  CREATE_SECRETS: 'create_secrets',
  VIEW_METADATA: 'view_metadata',
  EXTENDED_DEFAULT_EXPIRATION: 'extended_default_expiration',

  // Infrastructure
  API_ACCESS: 'api_access',
  CUSTOM_DOMAINS: 'custom_domains',

  // Collaboration
  MANAGE_TEAMS: 'manage_teams',
  MANAGE_MEMBERS: 'manage_members',

  // Branding
  CUSTOM_BRANDING: 'custom_branding',
  BRANDED_HOMEPAGE: 'branded_homepage',

  // Advanced
  AUDIT_LOGS: 'audit_logs',
  SSO: 'sso',

  // Support
  PRIORITY_SUPPORT: 'priority_support',
  SLA: 'sla',
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
 * Display helpers
 */

export function getOrganizationLabel(org: Organization): string {
  return org.display_name;
}
