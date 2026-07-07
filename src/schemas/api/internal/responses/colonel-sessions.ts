// src/schemas/api/internal/responses/colonel-sessions.ts
//
// Wrapped response schemas for the colonel Sessions console (ticket #40).
// Internal-only; consumed by the Vue admin console, never exposed publicly.
//
// The view + store import these DIRECTLY (CONTRACT 3) so they typecheck
// independently of the registry; the Integrate step adds the registry keys from
// wiringInstructions.

import { createApiResponseSchema } from '@/schemas/api/base';
import {
  colonelSessionsDetailsSchema,
  colonelSessionDetailRecordSchema,
  colonelSessionDetailDetailsSchema,
  colonelSessionDeleteRecordSchema,
  colonelSessionDeleteDetailsSchema,
} from '@/schemas/api/account/responses/colonel-sessions';
import { z } from 'zod';

// GET /api/colonel/sessions → ListSessions
export const colonelSessionsResponseSchema = createApiResponseSchema(
  z.object({}),
  colonelSessionsDetailsSchema
);

// GET /api/colonel/sessions/:session_id → GetSessionDetail
export const colonelSessionDetailResponseSchema = createApiResponseSchema(
  colonelSessionDetailRecordSchema,
  colonelSessionDetailDetailsSchema
);

// DELETE /api/colonel/sessions/:session_id → DeleteSession
export const colonelSessionDeleteResponseSchema = createApiResponseSchema(
  colonelSessionDeleteRecordSchema,
  colonelSessionDeleteDetailsSchema
);

export type ColonelSessionsResponse = z.infer<typeof colonelSessionsResponseSchema>;
export type ColonelSessionDetailResponse = z.infer<typeof colonelSessionDetailResponseSchema>;
export type ColonelSessionDeleteResponse = z.infer<typeof colonelSessionDeleteResponseSchema>;
