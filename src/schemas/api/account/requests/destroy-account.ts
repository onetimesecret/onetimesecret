// src/schemas/api/account/requests/destroy-account.ts
//
// Request schema for AccountAPI::Logic::Account::DestroyAccount
// POST /destroy
//
// TODO: Review and adjust — this scaffold was auto-generated from
// the Ruby source parameter survey. Verify against the actual
// handler implementation before using in the OpenAPI pipeline.

import { z } from 'zod';

export const destroyAccountRequestSchema = z.object({
  /** Confirmation string to delete account */
  confirmation: z.string(),
});

export type DestroyAccountRequest = z.infer<typeof destroyAccountRequestSchema>;
