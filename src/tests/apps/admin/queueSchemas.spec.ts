// src/tests/apps/admin/queueSchemas.spec.ts

import { describe, expect, it } from 'vitest';

import {
  colonelDlqListResponseSchema,
  colonelDlqMessagesResponseSchema,
  colonelDlqReplayResponseSchema,
  colonelDlqPurgeResponseSchema,
} from '@/schemas/api/internal/responses/colonel-queue';

/**
 * Zod tripwire (CONTRACT 3) for the four DLQ endpoint contracts. The DLQ
 * console screen was removed by design review, but the endpoints stay live and
 * these envelopes remain their registry/OpenAPI contract. Payloads are shaped
 * exactly as the live logic classes emit them — verified against
 * apps/api/colonel/logic/colonel/{list_dlqs,get_dlq_messages,replay_dlq,
 * purge_dlq}.rb, thin adapters over Onetime::Operations::Dlq::*. If a backend
 * response drifts, these fail rather than the contract silently rotting.
 */

// ListDlqs `success_data` — a healthy queue + one not-yet-declared queue.
function listPayload() {
  return {
    shrimp: '',
    record: {},
    details: {
      dlqs: [
        { queue: 'dlq.billing.event', messages: 3, consumers: 1 },
        { queue: 'dlq.email.message', messages: 0, error: 'not declared' },
      ],
      pagination: { page: 1, per_page: 50, total_count: 2, total_pages: 1 },
      connected: true,
    },
  };
}

// GetDlqMessages `success_data` — one peeked message with full death diagnosis.
function messagesPayload() {
  return {
    shrimp: '',
    record: { queue: 'dlq.billing.event', total_messages: 3, showing: 1 },
    details: {
      messages: [
        {
          delivery_tag: 1,
          message_id: 'm1',
          timestamp: 1700000000,
          age: '1m ago',
          original_queue: 'billing.event.process',
          death_reason: 'rejected',
          death_count: 2,
          error: null,
          content_type: 'application/json',
          payload_preview: '{"n":1}',
        },
      ],
    },
  };
}

describe('colonel Queue DLQ schemas (ticket #42, CONTRACT 3)', () => {
  it('accepts a ListDlqs payload (healthy + not-declared rows)', () => {
    const parsed = colonelDlqListResponseSchema.safeParse(listPayload());
    expect(parsed.success).toBe(true);
    if (parsed.success) {
      expect(parsed.data.details?.dlqs).toHaveLength(2);
      expect(parsed.data.details?.dlqs[1].error).toBe('not declared');
    }
  });

  it('accepts a GetDlqMessages payload with null death fields', () => {
    const parsed = colonelDlqMessagesResponseSchema.safeParse(messagesPayload());
    expect(parsed.success).toBe(true);
    if (parsed.success) {
      expect(parsed.data.record?.total_messages).toBe(3);
      expect(parsed.data.details?.messages[0].original_queue).toBe('billing.event.process');
    }
  });

  it('accepts a ReplayDlq ack (counts + dry-run flag)', () => {
    const parsed = colonelDlqReplayResponseSchema.safeParse({
      shrimp: '',
      record: { queue: 'dlq.billing.event', replayed: 3, failed: 0, would_replay: 0, dry_run: false },
      details: { message: 'Replayed 3 message(s), 0 failed', errors: [] },
    });
    expect(parsed.success).toBe(true);
  });

  it('accepts a PurgeDlq ack (count + purged)', () => {
    const parsed = colonelDlqPurgeResponseSchema.safeParse({
      shrimp: '',
      record: { queue: 'dlq.billing.event', count: 6, purged: 6, dry_run: false },
      details: { message: 'Purged 6 message(s)' },
    });
    expect(parsed.success).toBe(true);
  });

  it('rejects a DLQ summary row missing the required message count (drift tripwire)', () => {
    const bad = listPayload();
    // @ts-expect-error — deliberately drop the required `messages` field.
    delete bad.details.dlqs[0].messages;
    expect(colonelDlqListResponseSchema.safeParse(bad).success).toBe(false);
  });
});
