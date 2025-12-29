// src/schemas/api/organizations/endpoints/organizations.ts

/**
 * Organizations API endpoint schemas
 * Defines request/response schemas for organization management endpoints
 */

import { organizationMemberSchema, organizationSchema } from '@/types/organization';
import { z } from 'zod';

/**
 * Single organization response
 * POST /api/organizations
 * GET /api/organizations/:extid
 * PUT /api/organizations/:extid
 */
export const organizationResponseSchema = z.object({
  record: organizationSchema,
});

export type OrganizationResponse = z.infer<typeof organizationResponseSchema>;

/**
 * Organizations list response
 * GET /api/organizations
 */
export const organizationsResponseSchema = z.object({
  records: z.array(organizationSchema),
  count: z.number().int().min(0),
});

export type OrganizationsResponse = z.infer<typeof organizationsResponseSchema>;

/**
 * Delete response
 * DELETE /api/organizations/:extid
 *
 * Returns minimal confirmation payload with deleted flag and organization ID
 */
export const deleteResponseSchema = z.object({
  user_id: z.string(),
  deleted: z.boolean(),
  id: z.string(),  // External ID (extid) of deleted organization
});

export type DeleteResponse = z.infer<typeof deleteResponseSchema>;

/**
 * Members list response
 * GET /api/v2/org/:extid/members
 */
export const membersResponseSchema = z.object({
  records: z.array(organizationMemberSchema),
  count: z.number().int().min(0),
});

export type MembersResponse = z.infer<typeof membersResponseSchema>;

/**
 * Single member response
 * PATCH /api/v2/org/:extid/members/:member_extid
 */
export const memberResponseSchema = z.object({
  record: organizationMemberSchema,
});

export type MemberResponse = z.infer<typeof memberResponseSchema>;

/**
 * Member delete response
 * DELETE /api/v2/org/:extid/members/:member_extid
 */
export const memberDeleteResponseSchema = z.object({
  deleted: z.boolean(),
  member_extid: z.string(),
});

export type MemberDeleteResponse = z.infer<typeof memberDeleteResponseSchema>;
