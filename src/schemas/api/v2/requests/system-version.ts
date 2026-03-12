// src/schemas/api/v2/requests/system-version.ts
//
// Request schema for V2::Logic::Meta.system_version
// GET /version
//
//
// GET — no params. Returns version.

import { z } from 'zod';

// This endpoint accepts no request parameters.
// Path params (if any) are handled by the OpenAPI generator.
export const systemVersionRequestSchema = z.object({});

export type SystemVersionRequest = z.infer<typeof systemVersionRequestSchema>;
