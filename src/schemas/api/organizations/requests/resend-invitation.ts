// src/schemas/api/organizations/requests/resend-invitation.ts
//
// Request schema for OrganizationAPI::Logic::Invitations::ResendInvitation
// POST /:extid/invitations/:token/resend
//
//
// POST — org extid + token in path.

import { z } from 'zod';

// TODO: Add request parameters for this endpoint.
// Path params: extid, token
export const resendInvitationRequestSchema = z.object({
  // TODO: fill in from OrganizationAPI::Logic::Invitations::ResendInvitation raise_concerns / process
});

export type ResendInvitationRequest = z.infer<typeof resendInvitationRequestSchema>;
