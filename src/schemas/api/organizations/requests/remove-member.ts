// src/schemas/api/organizations/requests/remove-member.ts
//
// Request schema for OrganizationAPI::Logic::Members::RemoveMember
// DELETE /:extid/members/:member_extid
//
//
// DELETE — org extid + member extid in path.

import { z } from 'zod';

// TODO: Add request parameters for this endpoint.
// Path params: extid, member_extid
export const removeMemberRequestSchema = z.object({
  // TODO: fill in from OrganizationAPI::Logic::Members::RemoveMember raise_concerns / process
});

export type RemoveMemberRequest = z.infer<typeof removeMemberRequestSchema>;
