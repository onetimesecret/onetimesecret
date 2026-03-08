// src/schemas/api/v1/requests/status.ts
//
// Request schema for V1::Controllers::Index#status
// GET /status
//
// No request params. Returns system status.

import { z } from 'zod';

// This endpoint accepts no request parameters.
// Path params (if any) are handled by the OpenAPI generator.
export const statusRequestSchema = z.object({});

export type StatusRequest = z.infer<typeof statusRequestSchema>;
