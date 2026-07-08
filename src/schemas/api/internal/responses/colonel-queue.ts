// src/schemas/api/internal/responses/colonel-queue.ts
//
// Wrapped response schemas for the colonel DLQ endpoints. Internal-only; never
// exposed publicly.
//
// The DLQ console screen was removed by design review (YAGNI — `bin/ots queue
// dlq …` is the operator surface), but the four endpoints remain live, so
// these envelopes stay as their registry/OpenAPI contract (list_dlqs.rb
// declares `SCHEMAS = { response: 'colonelDlqList' }`).

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
