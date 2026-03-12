// src/schemas/api/organizations/requests/list-members.ts
//
// Request schema for OrganizationAPI::Logic::Members::ListMembers
// GET /:extid/members
//
//
// GET — org extid in path.

import { z } from 'zod';

// TODO: Add request parameters for this endpoint.
// Path params: extid
export const listMembersRequestSchema = z.object({
  // TODO: fill in from OrganizationAPI::Logic::Members::ListMembers raise_concerns / process
});

export type ListMembersRequest = z.infer<typeof listMembersRequestSchema>;
