// src/schemas/api/organizations/requests/list-members.ts
//
// Request schema for OrganizationAPI::Logic::Members::ListMembers
// GET /:extid/members
//
// TODO: Review and adjust — this scaffold was auto-generated from
// the Ruby source parameter survey. Verify against the actual
// handler implementation before using in the OpenAPI pipeline.
//
// GET — org extid in path.

import { z } from 'zod';

// TODO: Add request parameters for this endpoint.
// Path params: extid
export const listMembersRequestSchema = z.object({
  // TODO: fill in from OrganizationAPI::Logic::Members::ListMembers raise_concerns / process
});

export type ListMembersRequest = z.infer<typeof listMembersRequestSchema>;
