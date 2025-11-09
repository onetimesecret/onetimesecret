/**
 * Organization management type definitions
 * Used across organization components, stores, and views
 */

import { z } from 'zod';

/**
 * Organization capability constants
 */
export const CAPABILITIES = {
  CREATE_SECRETS: 'create_secrets',
  BASIC_SHARING: 'basic_sharing',
  CREATE_TEAM: 'create_team',
  CREATE_TEAMS: 'create_teams',
  CUSTOM_DOMAINS: 'custom_domains',
  API_ACCESS: 'api_access',
  PRIORITY_SUPPORT: 'priority_support',
  AUDIT_LOGS: 'audit_logs',
} as const;

export type Capability = (typeof CAPABILITIES)[keyof typeof CAPABILITIES];

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
  capabilities?: Capability[];
  limits?: OrganizationLimits;
}

/**
 * Zod schemas for validation
 */

export const organizationSchema = z.object({
  id: z.string(),
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
  capabilities: z.array(z.string() as z.ZodType<Capability>).optional(),
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
