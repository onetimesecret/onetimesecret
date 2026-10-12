// src/schemas/api/invite/responses/accept-invite.ts
//
// Response schema for InviteAPI::Logic::Invites::AcceptInvite
// POST /api/invite/:token/accept
//

import { z } from 'zod';

/**
 * The organization the user just joined. `id` is its extid. Accepting also
 * selects it in the server session (see `organization_selected`), so the
 * client only has to bring the tab into line with it.
 */
export const acceptInviteOrganizationSchema = z.object({
  id: z.string(),
  /** Optional for deploy skew with a backend that sends only the extid. */
  objid: z.string().optional(),
  display_name: z.string().nullish(),
});

/**
 * Only the fields the client reads are validated; the rest of the body
 * (user_id, role, joined_at) is stripped.
 */
export const acceptInviteResponseSchema = z.object({
  organization: acceptInviteOrganizationSchema,
  /**
   * Whether the server session now holds the joined organization. Accepting
   * still succeeds when the selection is refused. Optional for deploy skew;
   * absent is treated as not selected.
   */
  organization_selected: z.boolean().optional(),
});

export type AcceptInviteResponse = z.infer<typeof acceptInviteResponseSchema>;
