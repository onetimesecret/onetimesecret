// src/schemas/api/v1/requests/authcheck.ts
//
// Request schema for V1::Controllers::Index#authcheck
// GET /authcheck
//
// No request params. Returns auth status for current session.

import { z } from 'zod';

// This endpoint accepts no request parameters.
// Path params (if any) are handled by the OpenAPI generator.
export const authcheckRequestSchema = z.object({});

export type AuthcheckRequest = z.infer<typeof authcheckRequestSchema>;
