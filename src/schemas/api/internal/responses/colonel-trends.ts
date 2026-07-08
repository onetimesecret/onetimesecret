// src/schemas/api/internal/responses/colonel-trends.ts
//
// Wrapped response schema for the colonel overview trends (observability).
// Internal-only; consumed by the Vue admin console, never exposed publicly.
//
// The view imports this DIRECTLY (CONTRACT 3) so it typechecks independently
// of the registry; the registry key (`colonelTrends`) links it to the
// GetTrends logic class for OpenAPI generation.

import { createApiResponseSchema } from '@/schemas/api/base';
import { colonelTrendsDetailsSchema } from '@/schemas/api/account/responses/colonel-trends';
import { z } from 'zod';

// GET /api/colonel/trends → GetTrends
export const colonelTrendsResponseSchema = createApiResponseSchema(
  z.object({}),
  colonelTrendsDetailsSchema
);

export type ColonelTrendsResponse = z.infer<typeof colonelTrendsResponseSchema>;
