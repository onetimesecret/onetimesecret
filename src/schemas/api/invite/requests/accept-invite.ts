// src/schemas/api/invite/requests/accept-invite.ts
//
// Request schema for InviteAPI::Logic::Invites::AcceptInvite
// POST /:token/accept
//
//
// POST — token in path. No body params (auth validates identity).

import { z } from 'zod';

// TODO: Add request parameters for this endpoint.
// Path params: token
export const acceptInviteRequestSchema = z.object({
  // TODO: fill in from InviteAPI::Logic::Invites::AcceptInvite raise_concerns / process
});

export type AcceptInviteRequest = z.infer<typeof acceptInviteRequestSchema>;
