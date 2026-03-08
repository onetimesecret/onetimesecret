// src/schemas/api/v3/requests/system-version.ts
//
// Request schema for V3::Logic::Meta.system_version
// GET /version
//
// TODO: Review and adjust — this scaffold was auto-generated from
// the Ruby source parameter survey. Verify against the actual
// handler implementation before using in the OpenAPI pipeline.
//
// GET — no params. Returns version.

import { z } from 'zod';

// This endpoint accepts no request parameters.
// Path params (if any) are handled by the OpenAPI generator.
export const systemVersionRequestSchema = z.object({});

export type SystemVersionRequest = z.infer<typeof systemVersionRequestSchema>;
