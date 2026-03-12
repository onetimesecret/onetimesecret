// src/schemas/api/account/requests/confirm-email-change.ts
//
// Request schema for AccountAPI::Logic::Account::ConfirmEmailChange
// POST /confirm-email-change
//

import { z } from 'zod';

export const confirmEmailChangeRequestSchema = z.object({
  /** Email change confirmation token */
  token: z.string(),
});

export type ConfirmEmailChangeRequest = z.infer<typeof confirmEmailChangeRequestSchema>;
