// src/schemas/api/internal/responses/colonel-queue.ts
//
// Wrapped response schemas for the colonel Queue DLQ console (ticket #42).
// Internal-only; consumed by the Vue admin console, never exposed publicly.
//
// The view + store import these DIRECTLY (CONTRACT 3) so they typecheck
// independently of the registry; the Integrate step adds the registry keys from
// wiringInstructions.

import { createApiResponseSchema } from '@/schemas/api/base';
import {
  colonelDlqListDetailsSchema,
  colonelDlqMessagesRecordSchema,
  colonelDlqMessagesDetailsSchema,
  colonelDlqReplayRecordSchema,
  colonelDlqReplayDetailsSchema,
  colonelDlqPurgeRecordSchema,
  colonelDlqPurgeDetailsSchema,
} from '@/schemas/api/account/responses/colonel-queue';
import { z } from 'zod';

// GET /api/colonel/queues/dlq → ListDlqs
export const colonelDlqListResponseSchema = createApiResponseSchema(
  z.object({}),
  colonelDlqListDetailsSchema
);

// GET /api/colonel/queues/dlq/:queue → GetDlqMessages
export const colonelDlqMessagesResponseSchema = createApiResponseSchema(
  colonelDlqMessagesRecordSchema,
  colonelDlqMessagesDetailsSchema
);

// POST /api/colonel/queues/dlq/:queue/replay → ReplayDlq
export const colonelDlqReplayResponseSchema = createApiResponseSchema(
  colonelDlqReplayRecordSchema,
  colonelDlqReplayDetailsSchema
);

// POST /api/colonel/queues/dlq/:queue/purge → PurgeDlq
export const colonelDlqPurgeResponseSchema = createApiResponseSchema(
  colonelDlqPurgeRecordSchema,
  colonelDlqPurgeDetailsSchema
);

export type ColonelDlqListResponse = z.infer<typeof colonelDlqListResponseSchema>;
export type ColonelDlqMessagesResponse = z.infer<typeof colonelDlqMessagesResponseSchema>;
export type ColonelDlqReplayResponse = z.infer<typeof colonelDlqReplayResponseSchema>;
export type ColonelDlqPurgeResponse = z.infer<typeof colonelDlqPurgeResponseSchema>;
