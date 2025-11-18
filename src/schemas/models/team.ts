// src/schemas/models/team.ts

import { transforms } from '@/schemas/transforms';
import { withFeatureFlags } from '@/schemas/utils/feature_flags';
import { z } from 'zod';

import { createModelSchema } from './base';

/**
 * @fileoverview Team and TeamMember schemas following established patterns
 *
 * Architecture:
 * 1. Uses createModelSchema() for base fields (identifier, created, updated)
 * 2. Transforms API string data to proper types
 * 3. Exports both Zod schemas and TypeScript types
 * 4. Includes feature flags support via withFeatureFlags()
 */

/**
 * Team member role enum
 */
export const TeamRole = {
  OWNER: 'owner',
  ADMIN: 'admin',
  MEMBER: 'member',
} as const;

export type TeamRole = (typeof TeamRole)[keyof typeof TeamRole];

/**
 * Team member status enum
 */
export const TeamMemberStatus = {
  ACTIVE: 'active',
  INVITED: 'invited',
  INACTIVE: 'inactive',
} as const;

export type TeamMemberStatus = (typeof TeamMemberStatus)[keyof typeof TeamMemberStatus];

// Create reusable schemas for enums
export const teamRoleSchema = z.enum([TeamRole.OWNER, TeamRole.ADMIN, TeamRole.MEMBER]);

export const teamMemberStatusSchema = z.enum([
  TeamMemberStatus.ACTIVE,
  TeamMemberStatus.INVITED,
  TeamMemberStatus.INACTIVE,
]);

/**
 * Team member info schema (simplified member data in team responses)
 * Used in the members array of team API responses
 */
export const teamMemberInfoSchema = z.object({
  custid: z.string(),
  email: z.string().email(),
  role: teamRoleSchema,
});

/**
 * Team schema
 * Maps API response to frontend Team model
 */
export const teamSchema = withFeatureFlags(
  createModelSchema({
    // Identifiers
    objid: z.string(),
    extid: z.string(),

    // Core fields
    display_name: z.string().min(1).max(100),
    description: z.string().max(500).optional().nullable(),
    owner_id: z.string(),
    org_id: z.string().optional().nullable(),

    // Metadata
    member_count: transforms.fromString.number.default(0),
    is_default: transforms.fromString.boolean.nullable(),
  }).strict()
);

/**
 * Team with current user's role
 * Extended schema for team views that include role context
 */
export const teamWithRoleSchema = teamSchema.extend({
  current_user_role: teamRoleSchema,
  members: z.array(teamMemberInfoSchema).optional(),
});

/**
 * Team member schema
 * Maps API response to frontend TeamMember model
 *
 * Note: Members API uses different field names than teams API:
 * - Uses 'created_at'/'updated_at' instead of 'created'/'updated'
 * - Uses 'id' instead of 'identifier'
 * - Returns 'team_extid' which we transform to 'team_id'
 */
export const teamMemberSchema = z
  .object({
    // Identifiers
    id: z.string(),
    team_extid: z.string(),
    user_id: z.string(),

    // User info
    email: z.string().email(),

    // Role and status
    role: teamRoleSchema,
    status: teamMemberStatusSchema,

    // Timestamps - API uses created_at/updated_at for members
    invited_at: z.number().optional(),
    joined_at: z.number().optional(),
    created_at: z.number(),
    updated_at: z.number(),
  })
  .transform((data) => ({
    id: data.id,
    team_id: data.team_extid, // Transform team_extid to team_id for frontend
    user_id: data.user_id,
    email: data.email,
    role: data.role,
    status: data.status,
    invited_at: data.invited_at ? new Date(data.invited_at * 1000) : undefined,
    joined_at: data.joined_at ? new Date(data.joined_at * 1000) : undefined,
    created: new Date(data.created_at * 1000), // Map created_at to created
    updated: new Date(data.updated_at * 1000), // Map updated_at to updated
  }));

/**
 * Request payload schemas
 * Used for validating data sent to API endpoints
 */

export const createTeamPayloadSchema = z.object({
  display_name: z.string().min(1, 'Team name is required').max(100, 'Team name is too long'),
  description: z.string().max(500, 'Description is too long').optional(),
  org_id: z.string().optional(),
});

export const updateTeamPayloadSchema = z.object({
  display_name: z.string().min(1).max(100).optional(),
  description: z.string().max(500).optional(),
});

export const inviteMemberPayloadSchema = z.object({
  email: z.string().email('Invalid email address'),
  role: teamRoleSchema.default(TeamRole.MEMBER),
});

export const updateMemberRolePayloadSchema = z.object({
  role: teamRoleSchema,
});

/**
 * TypeScript types derived from schemas
 */

// Team types with proper Date typing
export type Team = Omit<z.infer<typeof teamSchema>, 'created' | 'updated'> & {
  created: Date;
  updated: Date;
};

export type TeamWithRole = Omit<z.infer<typeof teamWithRoleSchema>, 'created' | 'updated'> & {
  created: Date;
  updated: Date;
};

export type TeamMemberInfo = z.infer<typeof teamMemberInfoSchema>;

// TeamMember type with proper Date typing
export type TeamMember = {
  id: string;
  team_id: string;
  user_id: string;
  email: string;
  role: TeamRole;
  status: TeamMemberStatus;
  invited_at?: Date;
  joined_at?: Date;
  created: Date;
  updated: Date;
};

// Payload types
export type CreateTeamPayload = z.infer<typeof createTeamPayloadSchema>;
export type UpdateTeamPayload = z.infer<typeof updateTeamPayloadSchema>;
export type InviteMemberPayload = z.infer<typeof inviteMemberPayloadSchema>;
export type UpdateMemberRolePayload = z.infer<typeof updateMemberRolePayloadSchema>;

/**
 * Type guards and permission helpers
 */

export function isTeamOwner(team: TeamWithRole): boolean {
  return team.current_user_role === TeamRole.OWNER;
}

export function isTeamAdmin(team: TeamWithRole): boolean {
  return team.current_user_role === TeamRole.ADMIN || team.current_user_role === TeamRole.OWNER;
}

export function canManageMembers(team: TeamWithRole): boolean {
  return isTeamAdmin(team);
}

export function canDeleteTeam(team: TeamWithRole): boolean {
  return isTeamOwner(team);
}

export function canUpdateTeamSettings(team: TeamWithRole): boolean {
  return isTeamOwner(team);
}

/**
 * Role and status display helpers
 */

export function getRoleBadgeColor(role: TeamRole): string {
  switch (role) {
    case TeamRole.OWNER:
      return 'bg-purple-100 text-purple-800 dark:bg-purple-900 dark:text-purple-300';
    case TeamRole.ADMIN:
      return 'bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-300';
    case TeamRole.MEMBER:
      return 'bg-gray-100 text-gray-800 dark:bg-gray-700 dark:text-gray-300';
    default:
      return 'bg-gray-100 text-gray-800 dark:bg-gray-700 dark:text-gray-300';
  }
}

export function getRoleLabel(role: TeamRole): string {
  return `web.teams.roles.${role}`;
}

export function getStatusBadgeColor(status: TeamMemberStatus): string {
  switch (status) {
    case TeamMemberStatus.ACTIVE:
      return 'bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-300';
    case TeamMemberStatus.INVITED:
      return 'bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-300';
    case TeamMemberStatus.INACTIVE:
      return 'bg-gray-100 text-gray-800 dark:bg-gray-700 dark:text-gray-300';
    default:
      return 'bg-gray-100 text-gray-800 dark:bg-gray-700 dark:text-gray-300';
  }
}

export function getStatusLabel(status: TeamMemberStatus): string {
  return `web.teams.statuses.${status}`;
}
