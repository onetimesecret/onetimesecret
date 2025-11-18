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
  invited_at?: Date;
  joined_at?: Date;
  created_at: Date;
  updated_at: Date;
}

/**
 * Team interface
 */
export interface Team {
  id: string; // Internal identifier (UUID) - same as identifier/objid from API
  identifier: string; // Alias for id - from API response
  objid: string; // Object ID - from API response
  extid: string; // External identifier (e.g., tm123456) - used in URLs
  display_name: string;
  description?: string;
  owner_id: string;
  org_id?: string;
  member_count: number;
  is_default: boolean;
  created_at: Date;
  updated_at: Date;
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

// API member schema (matches API response)
const teamMemberApiSchema = z.object({
  id: z.string(),
  team_extid: z.string(), // API uses team_extid, not team_id
  user_id: z.string(),
  email: z.string().email(),
  role: teamRoleSchema,
  status: teamMemberStatusSchema,
  invited_at: z.number().optional(),
  joined_at: z.number().optional(),
  created_at: z.number(),
  updated_at: z.number(),
});

// Transform to frontend format
export const teamMemberSchema = teamMemberApiSchema.transform((data): TeamMember => ({
  id: data.id,
  team_id: data.team_extid, // Map team_extid to team_id
  user_id: data.user_id,
  email: data.email,
  role: data.role,
  status: data.status,
  invited_at: data.invited_at ? new Date(data.invited_at * 1000) : undefined,
  joined_at: data.joined_at ? new Date(data.joined_at * 1000) : undefined,
  created_at: new Date(data.created_at * 1000),
  updated_at: new Date(data.updated_at * 1000),
}));

// Base schema matching API response
const teamApiSchema = z.object({
  identifier: z.string(), // Internal UUID from API
  objid: z.string(), // Object ID from API
  extid: z.string(), // External identifier (e.g., tm123456) - used in URLs
  display_name: z.string().min(1).max(100),
  description: z.string().max(500).optional().nullable(),
  owner_id: z.string(),
  org_id: z.string().optional().nullable(),
  member_count: z.number().int().min(0),
  is_default: z.boolean().nullable(),
  created: z.number(),
  updated: z.number(),
});

// Transform to frontend format
export const teamSchema = teamApiSchema.transform((data): Team => ({
  id: data.identifier, // Map identifier to id for convenience
  identifier: data.identifier,
  objid: data.objid,
  extid: data.extid,
  display_name: data.display_name,
  description: data.description ?? undefined,
  owner_id: data.owner_id,
  org_id: data.org_id ?? undefined,
  member_count: data.member_count,
  is_default: data.is_default ?? false, // Default to false if null
  created_at: new Date(data.created * 1000),
  updated_at: new Date(data.updated * 1000),
}));

export const teamWithRoleSchema = teamApiSchema.extend({
  current_user_role: teamRoleSchema,
}).transform((data): TeamWithRole => ({
  id: data.identifier, // Map identifier to id for convenience
  identifier: data.identifier,
  objid: data.objid,
  extid: data.extid,
  display_name: data.display_name,
  description: data.description ?? undefined,
  owner_id: data.owner_id,
  org_id: data.org_id ?? undefined,
  member_count: data.member_count,
  is_default: data.is_default ?? false, // Default to false if null
  created_at: new Date(data.created * 1000),
  updated_at: new Date(data.updated * 1000),
  current_user_role: data.current_user_role,
}));

/**
 * Request payload schemas
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
