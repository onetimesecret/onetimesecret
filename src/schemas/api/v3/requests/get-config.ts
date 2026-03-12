// src/schemas/api/v3/requests/get-config.ts
//
// Request schema for V3::Logic::Incoming::GetConfig
// GET /incoming/config
//
//
// GET — no body. Returns incoming config.

import { z } from 'zod';

// This endpoint accepts no request parameters.
// Path params (if any) are handled by the OpenAPI generator.
export const getConfigRequestSchema = z.object({});

export type GetConfigRequest = z.infer<typeof getConfigRequestSchema>;
