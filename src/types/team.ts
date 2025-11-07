/**
 * Team management type definitions
 * Used across team components, stores, and views
 */

import { z } from 'zod';

/**
 * Team member role
 */
export enum TeamRole {
  OWNER = 'owner',
  ADMIN = 'admin',
  MEMBER = 'member',
}

/**
 * Team member status
 */
export enum TeamMemberStatus {
  ACTIVE = 'active',
  INVITED = 'invited',
  INACTIVE = 'inactive',
}

/**
 * Team member interface
 */
export interface TeamMember {
  id: string;
  team_id: string;
  user_id: string;
  email: string;
  role: TeamRole;
  status: TeamMemberStatus;
  invited_at?: string;
  joined_at?: string;
  created_at: string;
  updated_at: string;
}

/**
 * Team interface
 */
export interface Team {
  id: string;
  display_name: string;
  description?: string;
  owner_id: string;
  member_count: number;
  created_at: string;
  updated_at: string;
}

/**
 * Extended team with current user's role
 */
export interface TeamWithRole extends Team {
  current_user_role: TeamRole;
}

/**
 * Zod schemas for validation
 */

export const teamRoleSchema = z.nativeEnum(TeamRole);

export const teamMemberStatusSchema = z.nativeEnum(TeamMemberStatus);

export const teamMemberSchema = z.object({
  id: z.string(),
  team_id: z.string(),
  user_id: z.string(),
  email: z.string().email(),
  role: teamRoleSchema,
  status: teamMemberStatusSchema,
  invited_at: z.union([z.string(), z.number()]).transform(val => String(val)).optional(),
  joined_at: z.union([z.string(), z.number()]).transform(val => String(val)).optional(),
  created_at: z.union([z.string(), z.number()]).transform(val => String(val)),
  updated_at: z.union([z.string(), z.number()]).transform(val => String(val)),
});

export const teamSchema = z.object({
  id: z.string(),
  display_name: z.string().min(1).max(100),
  description: z.string().max(500).optional(),
  owner_id: z.string(),
  member_count: z.number().int().min(0),
  created_at: z.union([z.string(), z.number()]).transform(val => String(val)),
  updated_at: z.union([z.string(), z.number()]).transform(val => String(val)),
});

export const teamWithRoleSchema = teamSchema.extend({
  current_user_role: teamRoleSchema,
});

/**
 * Request payload schemas
 */

export const createTeamPayloadSchema = z.object({
  display_name: z.string().min(1, 'Team name is required').max(100, 'Team name is too long'),
  description: z.string().max(500, 'Description is too long').optional(),
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
 * Type exports from schemas
 */
export type CreateTeamPayload = z.infer<typeof createTeamPayloadSchema>;
export type UpdateTeamPayload = z.infer<typeof updateTeamPayloadSchema>;
export type InviteMemberPayload = z.infer<typeof inviteMemberPayloadSchema>;
export type UpdateMemberRolePayload = z.infer<typeof updateMemberRolePayloadSchema>;

/**
 * Type guards
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
 * Role display helpers
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
