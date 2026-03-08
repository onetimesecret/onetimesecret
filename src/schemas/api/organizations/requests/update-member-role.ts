// src/schemas/api/organizations/requests/update-member-role.ts
//
// Request schema for OrganizationAPI::Logic::Members::UpdateMemberRole
// PATCH /:extid/members/:member_extid/role
//
// TODO: Review and adjust — this scaffold was auto-generated from
// the Ruby source parameter survey. Verify against the actual
// handler implementation before using in the OpenAPI pipeline.

import { z } from 'zod';

export const updateMemberRoleRequestSchema = z.object({
  /** New role: "member" or "admin" */
  role: z.string(),
});

export type UpdateMemberRoleRequest = z.infer<typeof updateMemberRoleRequestSchema>;
