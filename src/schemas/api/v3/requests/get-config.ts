// src/schemas/api/v3/requests/get-config.ts
//
// Request schema for V3::Logic::Incoming::GetConfig
// GET /incoming/config
//
// TODO: Review and adjust — this scaffold was auto-generated from
// the Ruby source parameter survey. Verify against the actual
// handler implementation before using in the OpenAPI pipeline.
//
// GET — no body. Returns incoming config.

import { z } from 'zod';

// This endpoint accepts no request parameters.
// Path params (if any) are handled by the OpenAPI generator.
export const getConfigRequestSchema = z.object({});

export type GetConfigRequest = z.infer<typeof getConfigRequestSchema>;
