// src/schemas/api/account/requests/request-email-change.ts
//
// Request schema for AccountAPI::Logic::Account::RequestEmailChange
// POST /change-email
//

import { z } from 'zod';

export const requestEmailChangeRequestSchema = z.object({
  /** New email address */
  newemail: z.string(),
});

export type RequestEmailChangeRequest = z.infer<typeof requestEmailChangeRequestSchema>;
