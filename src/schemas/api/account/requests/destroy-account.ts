// src/schemas/api/account/requests/destroy-account.ts
//
// Request schema for AccountAPI::Logic::Account::DestroyAccount
// POST /destroy
//

import { z } from 'zod';

export const destroyAccountRequestSchema = z.object({
  /** Confirmation string to delete account */
  confirmation: z.string(),
});

export type DestroyAccountRequest = z.infer<typeof destroyAccountRequestSchema>;
