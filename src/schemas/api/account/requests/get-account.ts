// src/schemas/api/account/requests/get-account.ts
//
// Request schema for AccountAPI::Logic::Account::GetAccount
// GET /
//
// TODO: Review and adjust — this scaffold was auto-generated from
// the Ruby source parameter survey. Verify against the actual
// handler implementation before using in the OpenAPI pipeline.
//
// GET — no body. Returns account details.

import { z } from 'zod';

// This endpoint accepts no request parameters.
// Path params (if any) are handled by the OpenAPI generator.
export const getAccountRequestSchema = z.object({});

export type GetAccountRequest = z.infer<typeof getAccountRequestSchema>;
