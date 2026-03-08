// src/schemas/api/colonel/requests/get-database-metrics.ts
//
// Request schema for ColonelAPI::Logic::Colonel::GetDatabaseMetrics
// GET /system/database
//
// TODO: Review and adjust — this scaffold was auto-generated from
// the Ruby source parameter survey. Verify against the actual
// handler implementation before using in the OpenAPI pipeline.
//
// GET — no params.

import { z } from 'zod';

// This endpoint accepts no request parameters.
// Path params (if any) are handled by the OpenAPI generator.
export const getDatabaseMetricsRequestSchema = z.object({});

export type GetDatabaseMetricsRequest = z.infer<typeof getDatabaseMetricsRequestSchema>;
