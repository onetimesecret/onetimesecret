// src/schemas/api/account/requests/confirm-email-change.ts
//
// Request schema for AccountAPI::Logic::Account::ConfirmEmailChange
// POST /confirm-email-change
//
// TODO: Review and adjust — this scaffold was auto-generated from
// the Ruby source parameter survey. Verify against the actual
// handler implementation before using in the OpenAPI pipeline.

import { z } from 'zod';

export const confirmEmailChangeRequestSchema = z.object({
  /** Email change confirmation token */
  token: z.string(),
});

export type ConfirmEmailChangeRequest = z.infer<typeof confirmEmailChangeRequestSchema>;
