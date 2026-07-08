// src/schemas/api/internal/responses/colonel-audit.ts
//
// Wrapped response schema for the colonel Audit Log screen (observability).
// Internal-only; consumed by the Vue admin console, never exposed publicly.
//
// The view + store import this DIRECTLY (CONTRACT 3) so they typecheck
// independently of the registry; the registry key (`colonelAuditEvents`) links
// it to the ListAuditEvents logic class for OpenAPI generation.

import { createApiResponseSchema } from '@/schemas/api/base';
import { colonelAuditEventsDetailsSchema } from '@/schemas/api/account/responses/colonel-audit';
import { z } from 'zod';

// GET /api/colonel/audit → ListAuditEvents
export const colonelAuditEventsResponseSchema = createApiResponseSchema(
  z.object({}),
  colonelAuditEventsDetailsSchema
);

export type ColonelAuditEventsResponse = z.infer<typeof colonelAuditEventsResponseSchema>;
