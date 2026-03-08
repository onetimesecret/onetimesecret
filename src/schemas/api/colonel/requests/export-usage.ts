// src/schemas/api/colonel/requests/export-usage.ts
//
// Request schema for ColonelAPI::Logic::Colonel::ExportUsage
// GET /usage/export
//
// TODO: Review and adjust — this scaffold was auto-generated from
// the Ruby source parameter survey. Verify against the actual
// handler implementation before using in the OpenAPI pipeline.
//
// GET — no params. Returns CSV/JSON export.

import { z } from 'zod';

// This endpoint accepts no request parameters.
// Path params (if any) are handled by the OpenAPI generator.
export const exportUsageRequestSchema = z.object({});

export type ExportUsageRequest = z.infer<typeof exportUsageRequestSchema>;
