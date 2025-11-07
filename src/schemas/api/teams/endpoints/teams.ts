/**
 * Teams API endpoint schemas
 * Defines request/response schemas for team management endpoints
 */

import { teamWithRoleSchema, teamMemberSchema } from '@/types/team';
import { z } from 'zod';

/**
 * Single team response
 * POST /api/teams
 * GET /api/teams/:teamid
 * PUT /api/teams/:teamid
 */
export const teamResponseSchema = z.object({
  record: teamWithRoleSchema,
});

export type TeamResponse = z.infer<typeof teamResponseSchema>;

/**
 * Teams list response
 * GET /api/teams
 */
export const teamsResponseSchema = z.object({
  records: z.array(teamWithRoleSchema),
  count: z.number().int().min(0),
});

export type TeamsResponse = z.infer<typeof teamsResponseSchema>;

/**
 * Team members list response
 * GET /api/teams/:teamid/members
 */
export const teamMembersResponseSchema = z.object({
  records: z.array(teamMemberSchema),
  count: z.number().int().min(0),
});

export type TeamMembersResponse = z.infer<typeof teamMembersResponseSchema>;

/**
 * Single member response
 * POST /api/teams/:teamid/members
 */
export const teamMemberResponseSchema = z.object({
  record: teamMemberSchema,
});

export type TeamMemberResponse = z.infer<typeof teamMemberResponseSchema>;

/**
 * Delete response
 * DELETE /api/teams/:teamid
 * DELETE /api/teams/:teamid/members/:custid
 */
export const deleteResponseSchema = z.object({
  success: z.boolean(),
  message: z.string().optional(),
});

export type DeleteResponse = z.infer<typeof deleteResponseSchema>;
