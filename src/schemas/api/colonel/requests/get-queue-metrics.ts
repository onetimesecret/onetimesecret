// src/schemas/api/colonel/requests/get-queue-metrics.ts
//
// Request schema for ColonelAPI::Logic::Colonel::GetQueueMetrics
// GET /queue
//
// TODO: Review and adjust — this scaffold was auto-generated from
// the Ruby source parameter survey. Verify against the actual
// handler implementation before using in the OpenAPI pipeline.
//
// GET — no params.

import { z } from 'zod';

// This endpoint accepts no request parameters.
// Path params (if any) are handled by the OpenAPI generator.
export const getQueueMetricsRequestSchema = z.object({});

export type GetQueueMetricsRequest = z.infer<typeof getQueueMetricsRequestSchema>;
