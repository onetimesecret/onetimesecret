// src/schemas/api/account/requests/get-entitlements.ts
//
// Request schema for AccountAPI::Logic::Account::GetEntitlements
// GET /entitlements
//
//
// GET — no body. Returns entitlement list.

import { z } from 'zod';

// This endpoint accepts no request parameters.
// Path params (if any) are handled by the OpenAPI generator.
export const getEntitlementsRequestSchema = z.object({});

export type GetEntitlementsRequest = z.infer<typeof getEntitlementsRequestSchema>;
