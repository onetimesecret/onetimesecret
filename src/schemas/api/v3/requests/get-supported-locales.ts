// src/schemas/api/v3/requests/get-supported-locales.ts
//
// Request schema for V3::Logic::Meta.get_supported_locales
// GET /supported-locales
//
// TODO: Review and adjust — this scaffold was auto-generated from
// the Ruby source parameter survey. Verify against the actual
// handler implementation before using in the OpenAPI pipeline.
//
// GET — no params. Returns locale list.

import { z } from 'zod';

// This endpoint accepts no request parameters.
// Path params (if any) are handled by the OpenAPI generator.
export const getSupportedLocalesRequestSchema = z.object({});

export type GetSupportedLocalesRequest = z.infer<typeof getSupportedLocalesRequestSchema>;
