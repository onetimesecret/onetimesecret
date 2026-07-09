// src/schemas/api/internal/responses/colonel-queue.ts
//
// Per-resource colonel/admin schemas for the DLQ endpoints.
//
// The DLQ console screen was removed by design review (YAGNI — `bin/ots queue
// dlq …` is the operator surface), but the endpoints remain live, so these
// shapes stay as their registry/OpenAPI contract. The frozen colonel contracts
// in ./colonel.ts (including the existing read-only `queueMetrics`) are
// untouched (the Zod tripwire, epic non-goal):
//
//   - ListDlqs        → GET  /api/colonel/queues/dlq                  (summary list)
//   - GetDlqMessages  → GET  /api/colonel/queues/dlq/:queue           (peek)
//   - ReplayDlq       → POST /api/colonel/queues/dlq/:queue/replay    (replay)
//   - PurgeDlq        → POST /api/colonel/queues/dlq/:queue/purge      (purge)
//
// Shapes verified against the live logic classes
// (apps/api/colonel/logic/colonel/{list_dlqs,get_dlq_messages,replay_dlq,purge_dlq}.rb),
// which are thin adapters over Onetime::Operations::Dlq::{List,Peek,Replay,Purge}.

import { createApiResponseSchema } from '@/schemas/api/base';
import { paginationSchema } from './colonel';
import { z } from 'zod';

// ============================================================================
// ListDlqs — per-queue summary row + details
// ============================================================================

/**
 * A single dead-letter queue summary row (ListDlqs `details.dlqs[]`). `queue` is
 * the full DLQ name (e.g. `dlq.billing.event`); `consumers` is absent on a
 * queue that is configured but not yet declared in the broker (surfaced instead
 * as `error: 'not declared'`), so both are optional/nullable.
 */
export const colonelDlqSummarySchema = z.object({
  queue: z.string(),
  messages: z.number(),
  consumers: z.number().optional(),
  error: z.string().optional(),
});

/** DLQ summary list details: rows + the shared pagination envelope + broker flag. */
export const colonelDlqListDetailsSchema = z.object({
  dlqs: z.array(colonelDlqSummarySchema),
  pagination: paginationSchema,
  connected: z.boolean().nullable().optional(),
});

// ============================================================================
// GetDlqMessages — peeked messages for the detail drawer
// ============================================================================

/**
 * One peeked dead-letter message (GetDlqMessages `details.messages[]`). All the
 * death-diagnosis fields are nullable because a raw message may lack an `x-death`
 * header. `payload_preview` is truncated to ~200 chars by the op (a sample for
 * triage — the CLI `queue dlq show` exposes the full payload).
 */
export const colonelDlqMessageSchema = z.object({
  delivery_tag: z.union([z.string(), z.number()]).nullable().optional(),
  message_id: z.string().nullable(),
  timestamp: z.number().nullable(),
  age: z.string(),
  original_queue: z.string().nullable(),
  death_reason: z.string().nullable(),
  death_count: z.number().nullable(),
  error: z.string().nullable(),
  content_type: z.string().nullable(),
  payload_preview: z.string().nullable(),
});

/** GetDlqMessages `record`: the queue id + its depth and how many are shown. */
export const colonelDlqMessagesRecordSchema = z.object({
  queue: z.string(),
  total_messages: z.number(),
  showing: z.number(),
});

/** GetDlqMessages `details`: the peeked messages. */
export const colonelDlqMessagesDetailsSchema = z.object({
  messages: z.array(colonelDlqMessageSchema),
});

// ============================================================================
// ReplayDlq — guarded retry ack
// ============================================================================

/** ReplayDlq `record`: the counts (+ dry-run preview) for a replay. */
export const colonelDlqReplayRecordSchema = z.object({
  queue: z.string(),
  replayed: z.number(),
  failed: z.number(),
  would_replay: z.number(),
  dry_run: z.boolean(),
});

/** A single per-message replay error entry. */
export const colonelDlqReplayErrorSchema = z.object({
  message_id: z.string().nullable().optional(),
  error: z.string(),
});

/** ReplayDlq `details`: a human-readable ack message + any per-message errors. */
export const colonelDlqReplayDetailsSchema = z.object({
  message: z.string(),
  errors: z.array(colonelDlqReplayErrorSchema),
});

// ============================================================================
// PurgeDlq — guarded purge ack
// ============================================================================

/** PurgeDlq `record`: the measured count and how many were purged (0 on dry-run). */
export const colonelDlqPurgeRecordSchema = z.object({
  queue: z.string(),
  count: z.number(),
  purged: z.number(),
  dry_run: z.boolean(),
});

/** PurgeDlq `details`: a human-readable ack message. */
export const colonelDlqPurgeDetailsSchema = z.object({
  message: z.string(),
});

// ============================================================================
// Type Exports
// ============================================================================

export type ColonelDlqSummary = z.infer<typeof colonelDlqSummarySchema>;
export type ColonelDlqMessage = z.infer<typeof colonelDlqMessageSchema>;
export type ColonelDlqMessagesRecord = z.infer<typeof colonelDlqMessagesRecordSchema>;
export type ColonelDlqReplayRecord = z.infer<typeof colonelDlqReplayRecordSchema>;
export type ColonelDlqPurgeRecord = z.infer<typeof colonelDlqPurgeRecordSchema>;

// Wrapped response schemas for the colonel DLQ endpoints. Internal-only; never
// exposed publicly.
//
// The DLQ console screen was removed by design review (YAGNI — `bin/ots queue
// dlq …` is the operator surface), but the four endpoints remain live, so
// these envelopes stay as their registry/OpenAPI contract (list_dlqs.rb
// declares `SCHEMAS = { response: 'colonelDlqList' }`).

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
