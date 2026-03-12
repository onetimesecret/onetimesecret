// src/schemas/api/organizations/requests/update-member-role.ts
//
// Request schema for OrganizationAPI::Logic::Members::UpdateMemberRole
// PATCH /:extid/members/:member_extid/role
//

import { z } from 'zod';

export const updateMemberRoleRequestSchema = z.object({
  /** New role: "member" or "admin" */
  role: z.string(),
});

export type UpdateMemberRoleRequest = z.infer<typeof updateMemberRoleRequestSchema>;
