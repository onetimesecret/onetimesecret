// src/schemas/api/organizations/requests/revoke-invitation.ts
//
// Request schema for OrganizationAPI::Logic::Invitations::RevokeInvitation
// DELETE /:extid/invitations/:token
//
//
// DELETE — org extid + token in path.

import { z } from 'zod';

// TODO: Add request parameters for this endpoint.
// Path params: extid, token
export const revokeInvitationRequestSchema = z.object({
  // TODO: fill in from OrganizationAPI::Logic::Invitations::RevokeInvitation raise_concerns / process
});

export type RevokeInvitationRequest = z.infer<typeof revokeInvitationRequestSchema>;
