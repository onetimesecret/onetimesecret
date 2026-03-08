// src/schemas/api/colonel/requests/get-available-plans.ts
//
// Request schema for ColonelAPI::Logic::Colonel::GetAvailablePlans
// GET /available-plans
//
// TODO: Review and adjust — this scaffold was auto-generated from
// the Ruby source parameter survey. Verify against the actual
// handler implementation before using in the OpenAPI pipeline.
//
// GET — no params.

import { z } from 'zod';

// This endpoint accepts no request parameters.
// Path params (if any) are handled by the OpenAPI generator.
export const getAvailablePlansRequestSchema = z.object({});

export type GetAvailablePlansRequest = z.infer<typeof getAvailablePlansRequestSchema>;
