// src/schemas/api/account/requests/generate-api-token.ts
//
// Request schema for AccountAPI::Logic::Account::GenerateAPIToken
// POST /apitoken
//
//
// POST — no body params. Generates and returns a new API token.

import { z } from 'zod';

// This endpoint accepts no request parameters.
// Path params (if any) are handled by the OpenAPI generator.
export const generateAPITokenRequestSchema = z.object({});

export type GenerateAPITokenRequest = z.infer<typeof generateAPITokenRequestSchema>;
