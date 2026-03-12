// src/schemas/api/organizations/requests/list-invitations.ts
//
// Request schema for OrganizationAPI::Logic::Invitations::ListInvitations
// GET /:extid/invitations
//
//
// GET — org extid in path.

import { z } from 'zod';

// TODO: Add request parameters for this endpoint.
// Path params: extid
export const listInvitationsRequestSchema = z.object({
  // TODO: fill in from OrganizationAPI::Logic::Invitations::ListInvitations raise_concerns / process
});

export type ListInvitationsRequest = z.infer<typeof listInvitationsRequestSchema>;
