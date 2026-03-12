// src/schemas/api/account/requests/get-account.ts
//
// Request schema for AccountAPI::Logic::Account::GetAccount
// GET /
//
//
// GET — no body. Returns account details.

import { z } from 'zod';

// This endpoint accepts no request parameters.
// Path params (if any) are handled by the OpenAPI generator.
export const getAccountRequestSchema = z.object({});

export type GetAccountRequest = z.infer<typeof getAccountRequestSchema>;
