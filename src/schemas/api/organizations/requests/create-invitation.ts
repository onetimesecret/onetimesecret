// src/schemas/api/organizations/requests/create-invitation.ts
//
// Request schema for OrganizationAPI::Logic::Invitations::CreateInvitation
// POST /:extid/invitations
//
// TODO: Review and adjust — this scaffold was auto-generated from
// the Ruby source parameter survey. Verify against the actual
// handler implementation before using in the OpenAPI pipeline.

import { z } from 'zod';

export const createInvitationRequestSchema = z.object({
  /** Invitee email address */
  email: z.string(),
  /** Role: "member" or "admin" (default: "member") */
  role: z.string().optional(),
});

export type CreateInvitationRequest = z.infer<typeof createInvitationRequestSchema>;
