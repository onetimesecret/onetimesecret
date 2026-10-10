// src/schemas/api/internal/responses/colonel-queue.ts
//
// Per-resource colonel/admin schemas for the DLQ endpoints.
//
// The original DLQ console screen was removed by design review; the DLQ console
// is BACK as part of the Jobs screen (#4343, src/apps/admin/views/AdminJobs.vue):
// queue list → peek drawer → per-message inspect / replay / discard. The frozen
// colonel contracts in ./colonel.ts (including the existing read-only
// `queueMetrics`) are untouched (the Zod tripwire, epic non-goal):
//
//   - ListDlqs          → GET  /api/colonel/queues/dlq                 (summary list)
//   - GetDlqMessages    → GET  /api/colonel/queues/dlq/:queue          (peek)
//   - ReplayDlq         → POST /api/colonel/queues/dlq/:queue/replay   (bulk replay)
//   - PurgeDlq          → POST /api/colonel/queues/dlq/:queue/purge    (purge)
//
// Per-message verbs (#4343), under /api/colonel/queues/dlq/:queue/messages:
//
//   - GetDlqMessage     → GET  …/:message_id          (inspect)
//   - ReplayDlqMessage  → POST …/:message_id/replay   (replay one)
//   - DiscardDlqMessage → POST …/:message_id/discard  (discard one)
//
// The first four shapes are verified against the live logic classes
// (apps/api/colonel/logic/colonel/{list_dlqs,get_dlq_messages,replay_dlq,purge_dlq}.rb),
// which are thin adapters over Onetime::Operations::Dlq::{List,Peek,Replay,Purge}.
// The three per-message shapes are the #4343 contract the backend builds to.

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

// ============================================================================
// Per-message ops (#4343) — inspect / replay / discard one message by id
// ============================================================================
//
// All three verbs locate the message with a BOUNDED scan from the head of the
// queue. Two facts every response carries, because a miss is ambiguous:
//
//   - `scanned`   how many messages the server looked at before giving up.
//   - `truncated` true when the scan hit its bound before reaching the end of
//                 the queue, so the message may simply be deeper than looked.
//
// A miss on a VALID queue is NOT a 404: it is HTTP 200 with `found: false` and
// `outcome: 'not_visible'`. "Not visible" rather than "absent" because a
// consumer may be holding the delivery unacked (the email DLQ consumer holds
// for minutes), or another operator may have replayed it first. 404 is reserved
// for an unknown queue name.

/**
 * Values the server may put in `outcome`. Kept as a documented constant rather
 * than a Zod enum on the wire: the UI branches on `found`, and an unforeseen
 * outcome string must not fail the whole response.
 */
export const DLQ_MESSAGE_OUTCOME_NOT_VISIBLE = 'not_visible';

/** Scan facts shared by the three per-message records. */
const dlqMessageScanShape = {
  /** Message id the operator addressed (the AMQP `message_id`). */
  message_id: z.string(),
  /** False on a miss — see `outcome`. */
  found: z.boolean(),
  /** `'not_visible'` on a miss; absent or null on a hit. */
  outcome: z.string().nullable().optional(),
  /** Messages examined by the bounded scan. */
  scanned: z.number(),
  /** True when the scan stopped at its bound before the end of the queue. */
  truncated: z.boolean(),
};

/**
 * The `x-death` diagnosis for one message (`Store.build_message_detail`
 * `death_info`). Every field is nullable: a message published straight into a
 * DLQ has no `x-death` header at all.
 */
export const colonelDlqDeathInfoSchema = z.object({
  original_queue: z.string().nullable(),
  original_exchange: z.string().nullable(),
  reason: z.string().nullable(),
  count: z.number().nullable(),
  time: z.string().nullable(),
  routing_keys: z.array(z.string()).nullable(),
});

/**
 * The full detail of one dead-lettered message (`Store.build_message_detail`
 * verbatim). Unlike the peek row, `payload` is the whole parsed body (JSON when
 * the content type says so, else the raw string) — it can carry a customer's
 * email address on `dlq.email.message`, which is why the server records an
 * access observation per inspect.
 */
export const colonelDlqMessageDetailSchema = z.object({
  delivery_tag: z.union([z.string(), z.number()]).nullable().optional(),
  message_id: z.string().nullable(),
  /** ISO-8601 publish time, or null when the publisher set none. */
  timestamp: z.string().nullable(),
  content_type: z.string().nullable(),
  headers: z.record(z.string(), z.unknown()),
  death_info: colonelDlqDeathInfoSchema,
  payload: z.unknown(),
});

/** GetDlqMessage `record`: which message was asked for and how the scan went. */
export const colonelDlqMessageInspectRecordSchema = z.object({
  queue: z.string(),
  ...dlqMessageScanShape,
});

/** GetDlqMessage `details`: the message, or null on a miss. */
export const colonelDlqMessageInspectDetailsSchema = z.object({
  message: colonelDlqMessageDetailSchema.nullable(),
});

/** ReplayDlqMessage `record`: per-message replay counts (0/1) + scan facts. */
export const colonelDlqMessageReplayRecordSchema = z.object({
  queue: z.string(),
  ...dlqMessageScanShape,
  replayed: z.number(),
  failed: z.number(),
  would_replay: z.number(),
  dry_run: z.boolean(),
});

/** ReplayDlqMessage `details`: same as the bulk replay ack. */
export const colonelDlqMessageReplayDetailsSchema = colonelDlqReplayDetailsSchema;

/** DiscardDlqMessage `record`: whether the message was dropped + scan facts. */
export const colonelDlqMessageDiscardRecordSchema = z.object({
  queue: z.string(),
  ...dlqMessageScanShape,
  discarded: z.boolean(),
  /** The queue the message originally failed on, from its `x-death` header. */
  original_queue: z.string().nullable(),
  dry_run: z.boolean(),
});

/** DiscardDlqMessage `details`: a human-readable ack message. */
export const colonelDlqMessageDiscardDetailsSchema = z.object({
  message: z.string(),
});

export type ColonelDlqDeathInfo = z.infer<typeof colonelDlqDeathInfoSchema>;
export type ColonelDlqMessageDetail = z.infer<typeof colonelDlqMessageDetailSchema>;
export type ColonelDlqMessageInspectRecord = z.infer<typeof colonelDlqMessageInspectRecordSchema>;
export type ColonelDlqMessageReplayRecord = z.infer<typeof colonelDlqMessageReplayRecordSchema>;
export type ColonelDlqMessageDiscardRecord = z.infer<typeof colonelDlqMessageDiscardRecordSchema>;

// Wrapped response schemas for the colonel DLQ endpoints. Internal-only; never
// exposed publicly.
//
// These envelopes are the registry/OpenAPI contract (list_dlqs.rb declares
// `SCHEMAS = { response: 'colonelDlqList' }`) and, since #4343, also what the
// Jobs screen parses.

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

// GET /api/colonel/queues/dlq/:queue/messages/:message_id → GetDlqMessage (#4343)
export const colonelDlqMessageDetailResponseSchema = createApiResponseSchema(
  colonelDlqMessageInspectRecordSchema,
  colonelDlqMessageInspectDetailsSchema
);

// POST /api/colonel/queues/dlq/:queue/messages/:message_id/replay → ReplayDlqMessage (#4343)
export const colonelDlqMessageReplayResponseSchema = createApiResponseSchema(
  colonelDlqMessageReplayRecordSchema,
  colonelDlqMessageReplayDetailsSchema
);

// POST /api/colonel/queues/dlq/:queue/messages/:message_id/discard → DiscardDlqMessage (#4343)
export const colonelDlqMessageDiscardResponseSchema = createApiResponseSchema(
  colonelDlqMessageDiscardRecordSchema,
  colonelDlqMessageDiscardDetailsSchema
);

export type ColonelDlqListResponse = z.infer<typeof colonelDlqListResponseSchema>;
export type ColonelDlqMessagesResponse = z.infer<typeof colonelDlqMessagesResponseSchema>;
export type ColonelDlqReplayResponse = z.infer<typeof colonelDlqReplayResponseSchema>;
export type ColonelDlqPurgeResponse = z.infer<typeof colonelDlqPurgeResponseSchema>;
export type ColonelDlqMessageDetailResponse = z.infer<typeof colonelDlqMessageDetailResponseSchema>;
export type ColonelDlqMessageReplayResponse = z.infer<typeof colonelDlqMessageReplayResponseSchema>;
export type ColonelDlqMessageDiscardResponse = z.infer<
  typeof colonelDlqMessageDiscardResponseSchema
>;
