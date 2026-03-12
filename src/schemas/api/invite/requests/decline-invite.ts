// src/schemas/api/invite/requests/decline-invite.ts
//
// Request schema for InviteAPI::Logic::Invites::DeclineInvite
// POST /:token/decline
//
//
// POST — token in path. No body params.

import { z } from 'zod';

// TODO: Add request parameters for this endpoint.
// Path params: token
export const declineInviteRequestSchema = z.object({
  // TODO: fill in from InviteAPI::Logic::Invites::DeclineInvite raise_concerns / process
});

export type DeclineInviteRequest = z.infer<typeof declineInviteRequestSchema>;
