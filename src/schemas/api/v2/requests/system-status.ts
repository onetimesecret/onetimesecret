// src/schemas/api/v2/requests/system-status.ts
//
// Request schema for V2::Logic::Meta.system_status
// GET /status
//
// TODO: Review and adjust — this scaffold was auto-generated from
// the Ruby source parameter survey. Verify against the actual
// handler implementation before using in the OpenAPI pipeline.
//
// GET — no params. Returns status.

import { z } from 'zod';

// This endpoint accepts no request parameters.
// Path params (if any) are handled by the OpenAPI generator.
export const systemStatusRequestSchema = z.object({});

export type SystemStatusRequest = z.infer<typeof systemStatusRequestSchema>;
