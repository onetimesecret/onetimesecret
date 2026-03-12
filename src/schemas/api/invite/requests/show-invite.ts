// src/schemas/api/invite/requests/show-invite.ts
//
// Request schema for InviteAPI::Logic::Invites::ShowInvite
// GET /:token
//
//
// GET — token in path.

import { z } from 'zod';

// TODO: Add request parameters for this endpoint.
// Path params: token
export const showInviteRequestSchema = z.object({
  // TODO: fill in from InviteAPI::Logic::Invites::ShowInvite raise_concerns / process
});

export type ShowInviteRequest = z.infer<typeof showInviteRequestSchema>;
