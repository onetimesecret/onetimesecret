// src/tests/apps/admin/jobsSchemas.spec.ts

import { describe, expect, it } from 'vitest';

import {
  colonelChoreRunResponseSchema,
  colonelChoresResponseSchema,
  colonelJobsResponseSchema,
} from '@/schemas/api/internal/responses/colonel-jobs';
import {
  colonelDlqMessageDetailResponseSchema,
  colonelDlqMessageDiscardResponseSchema,
  colonelDlqMessageReplayResponseSchema,
  DLQ_DISCARD_OUTCOME_UNCONFIRMED,
  DLQ_REPLAY_OUTCOME_NO_ORIGINAL_QUEUE,
  DLQ_REPLAY_OUTCOME_UNROUTABLE,
} from '@/schemas/api/internal/responses/colonel-queue';
import { responseSchemas } from '@/schemas/api/internal/responses/registry';

/**
 * Zod tripwire for the #4343 Jobs-screen contracts: ListJobs, ListChores,
 * RunChore, and the per-message DLQ inspect / replay / discard acks.
 *
 * Payloads are WIRE-shaped (Unix-second numbers, ISO strings, JSON nulls) —
 * exactly what the Ruby logic classes serialise — so a schema that quietly
 * expects a parsed type (a Date, say) fails here rather than in production.
 */

const NOW = 1_700_000_000;

function job(overrides: Record<string, unknown> = {}) {
  return {
    job_id: 'heartbeat',
    job_class: 'Onetime::Jobs::Scheduled::HeartbeatJob',
    group: 'scheduled',
    state: 'scheduled',
    schedule_kind: 'every',
    schedule_expression: '5m',
    next_time: NOW + 300,
    registered_at: NOW - 7200,
    last_status: 'success',
    last_started_at: NOW - 60,
    last_finished_at: NOW - 59,
    last_duration_ms: 42,
    last_error: null,
    run_count: 12,
    error_count: 0,
    ...overrides,
  };
}

function jobsPayload(jobs = [job()]) {
  return {
    shrimp: '',
    record: {
      scheduler: {
        alive: true,
        started_at: NOW - 7200,
        heartbeat_at: NOW - 30,
        host: 'scheduler-1',
        pid: 4242,
        job_count: 16,
      },
    },
    details: {
      jobs,
      pagination: { page: 1, per_page: 50, total_count: jobs.length, total_pages: 1 },
    },
  };
}

/** A job the scheduler never registered and that never ran: every per-run field null. */
const neverRan = job({
  job_id: 'participation_gc',
  job_class: 'Onetime::Jobs::Scheduled::Maintenance::ParticipationGCJob',
  group: 'maintenance',
  state: 'not_scheduled',
  schedule_kind: null,
  schedule_expression: null,
  next_time: null,
  registered_at: null,
  last_status: 'never',
  last_started_at: null,
  last_finished_at: null,
  last_duration_ms: null,
  run_count: 0,
});

const errored = job({
  job_id: 'entitlement_materialize',
  group: 'maintenance',
  schedule_kind: 'cron',
  schedule_expression: '0 3 * * *',
  last_status: 'error',
  last_error: 'Redis::TimeoutError: Connection timed out',
  error_count: 2,
});

function chore(overrides: Record<string, unknown> = {}) {
  return {
    id: 'housekeeping.organization.standardize_owner_id',
    kind: 'housekeeping',
    model: 'Onetime::Organization',
    chores: ['standardize_owner_id'],
    supports_dry_run: false,
    cli: 'bin/ots housekeeping run Onetime::Organization',
    last_status: 'never',
    last_started_at: null,
    last_finished_at: null,
    last_duration_ms: null,
    last_error: null,
    run_count: 0,
    ...overrides,
  };
}

function choreRunPayload(record: Record<string, unknown> = {}) {
  return {
    shrimp: '',
    record: {
      chore: 'housekeeping.organization.standardize_owner_id',
      kind: 'housekeeping',
      status: 'success',
      dry_run: false,
      limit: 100,
      capped: false,
      budget_exhausted: false,
      duration_ms: 812,
      ...record,
    },
    details: {
      report: {
        model: 'Onetime::Organization',
        scanned: 100,
        chores: { standardize_owner_id: { modified: 3, errors: 0 } },
      },
      cli: 'bin/ots housekeeping run Onetime::Organization',
    },
  };
}

function messageDetail() {
  return {
    delivery_tag: 1,
    message_id: 'm1',
    timestamp: '2023-11-14T22:13:20Z',
    content_type: 'application/json',
    headers: { 'x-death': [{ queue: 'billing.event.process', count: 2 }] },
    death_info: {
      original_queue: 'billing.event.process',
      original_exchange: '',
      reason: 'rejected',
      count: 2,
      time: '2023-11-14T22:13:21Z',
      routing_keys: ['billing.event.process'],
    },
    payload: { event: 'invoice.paid' },
  };
}

describe('colonel Jobs schemas (#4343)', () => {
  describe('ListJobs', () => {
    it('accepts a payload with a never-ran row and an error row', () => {
      const parsed = colonelJobsResponseSchema.safeParse(jobsPayload([job(), neverRan, errored]));
      expect(parsed.success).toBe(true);
      if (parsed.success) {
        expect(parsed.data.record.scheduler.alive).toBe(true);
        expect(parsed.data.details?.jobs).toHaveLength(3);
        expect(parsed.data.details?.jobs[1].last_status).toBe('never');
        expect(parsed.data.details?.jobs[2].last_error).toContain('TimeoutError');
      }
    });

    it('accepts a scheduler that has never booted (every field null, alive false)', () => {
      const payload = jobsPayload([neverRan]);
      payload.record.scheduler = {
        alive: false,
        started_at: null,
        heartbeat_at: null,
        host: null,
        pid: null,
        job_count: null,
      } as unknown as typeof payload.record.scheduler;
      expect(colonelJobsResponseSchema.safeParse(payload).success).toBe(true);
    });

    it('rejects an unknown last_status', () => {
      const parsed = colonelJobsResponseSchema.safeParse(
        jobsPayload([job({ last_status: 'bogus' })])
      );
      expect(parsed.success).toBe(false);
    });

    it('accepts an aborted run (reported as error with an "aborted:" reason)', () => {
      const parsed = colonelJobsResponseSchema.safeParse(
        jobsPayload([job({ last_status: 'error', last_error: 'aborted: catalog pull failed' })])
      );
      expect(parsed.success).toBe(true);
    });

    it.each(['cron', 'every', 'in', 'at'])('accepts schedule_kind %s', (kind) => {
      const parsed = colonelJobsResponseSchema.safeParse(
        jobsPayload([job({ schedule_kind: kind })])
      );
      expect(parsed.success).toBe(true);
    });

    it('rejects an unknown schedule_kind', () => {
      const parsed = colonelJobsResponseSchema.safeParse(
        jobsPayload([job({ schedule_kind: 'interval' })])
      );
      expect(parsed.success).toBe(false);
    });

    it('rejects an unknown state', () => {
      const parsed = colonelJobsResponseSchema.safeParse(jobsPayload([job({ state: 'paused' })]));
      expect(parsed.success).toBe(false);
    });

    it('rejects a millisecond Date object where a Unix-second number is expected', () => {
      const parsed = colonelJobsResponseSchema.safeParse(
        jobsPayload([job({ next_time: new Date(NOW * 1000) })])
      );
      expect(parsed.success).toBe(false);
    });
  });

  describe('ListChores', () => {
    it('accepts per-chore housekeeping ids and the entitlement chore', () => {
      const parsed = colonelChoresResponseSchema.safeParse({
        shrimp: '',
        record: {},
        details: {
          chores: [
            chore(),
            chore({
              id: 'entitlement_materialize',
              kind: 'billing',
              chores: [],
              supports_dry_run: true,
              cli: 'bin/ots billing plans materialize --all --include-memberships --run',
              last_status: 'success',
              last_started_at: NOW - 600,
              last_finished_at: NOW - 590,
              last_duration_ms: 9800,
              run_count: 3,
            }),
          ],
          pagination: { page: 1, per_page: 50, total_count: 2, total_pages: 1 },
        },
      });
      expect(parsed.success).toBe(true);
      if (parsed.success) {
        const ids = parsed.data.details?.chores.map((c) => c.id);
        expect(ids).toEqual([
          'housekeeping.organization.standardize_owner_id',
          'entitlement_materialize',
        ]);
      }
    });

    it('rejects an unknown chore kind', () => {
      const parsed = colonelChoresResponseSchema.safeParse({
        shrimp: '',
        record: {},
        details: {
          chores: [chore({ kind: 'vhost' })],
          pagination: { page: 1, per_page: 50, total_count: 1, total_pages: 1 },
        },
      });
      expect(parsed.success).toBe(false);
    });
  });

  describe('RunChore', () => {
    it('accepts a bounded run that stopped on both bounds (partial counts)', () => {
      const parsed = colonelChoreRunResponseSchema.safeParse(
        choreRunPayload({ capped: true, budget_exhausted: true })
      );
      expect(parsed.success).toBe(true);
      if (parsed.success) {
        expect(parsed.data.record.budget_exhausted).toBe(true);
        expect(parsed.data.details?.report.scanned).toBe(100);
      }
    });

    it('accepts a preview ack (dry_run, null duration)', () => {
      const parsed = colonelChoreRunResponseSchema.safeParse(
        choreRunPayload({ status: 'dry_run', dry_run: true, duration_ms: null })
      );
      expect(parsed.success).toBe(true);
    });

    it('requires budget_exhausted (the #4343 response delta)', () => {
      const payload = choreRunPayload();
      delete (payload.record as Record<string, unknown>).budget_exhausted;
      expect(colonelChoreRunResponseSchema.safeParse(payload).success).toBe(false);
    });
  });

  describe('per-message DLQ ops', () => {
    it('accepts an inspect hit with the full message detail', () => {
      const parsed = colonelDlqMessageDetailResponseSchema.safeParse({
        shrimp: '',
        record: {
          queue: 'dlq.billing.event',
          message_id: 'm1',
          found: true,
          scanned: 1,
          truncated: false,
        },
        details: { message: messageDetail() },
      });
      expect(parsed.success).toBe(true);
      if (parsed.success) {
        expect(parsed.data.details?.message?.death_info.original_queue).toBe(
          'billing.event.process'
        );
      }
    });

    it('accepts an inspect MISS as a 200: found false, not_visible, null message', () => {
      const parsed = colonelDlqMessageDetailResponseSchema.safeParse({
        shrimp: '',
        record: {
          queue: 'dlq.email.message',
          message_id: 'm9',
          found: false,
          outcome: 'not_visible',
          scanned: 500,
          truncated: true,
        },
        details: { message: null },
      });
      expect(parsed.success).toBe(true);
      if (parsed.success) {
        expect(parsed.data.record.outcome).toBe('not_visible');
        expect(parsed.data.record.truncated).toBe(true);
      }
    });

    it('accepts a message published straight into a DLQ (no x-death: all nulls)', () => {
      const detail = messageDetail();
      detail.death_info = {
        original_queue: null,
        original_exchange: null,
        reason: null,
        count: null,
        time: null,
        routing_keys: null,
      } as unknown as typeof detail.death_info;
      const parsed = colonelDlqMessageDetailResponseSchema.safeParse({
        shrimp: '',
        record: {
          queue: 'dlq.billing.event',
          message_id: 'm1',
          found: true,
          scanned: 3,
          truncated: false,
        },
        details: { message: detail },
      });
      expect(parsed.success).toBe(true);
    });

    it('requires scanned and truncated on every per-message record', () => {
      const base = { queue: 'dlq.billing.event', message_id: 'm1', found: true };
      const inspect = (record: Record<string, unknown>) =>
        colonelDlqMessageDetailResponseSchema.safeParse({
          shrimp: '',
          record,
          details: { message: null },
        }).success;
      expect(inspect({ ...base, truncated: false })).toBe(false);
      expect(inspect({ ...base, scanned: 1 })).toBe(false);
      expect(inspect({ ...base, scanned: 1, truncated: false })).toBe(true);
    });

    it('accepts replay acks for a hit and a not-visible miss', () => {
      const ack = (record: Record<string, unknown>) =>
        colonelDlqMessageReplayResponseSchema.safeParse({
          shrimp: '',
          record: {
            queue: 'dlq.billing.event',
            message_id: 'm1',
            scanned: 1,
            truncated: false,
            replayed: 0,
            failed: 0,
            would_replay: 0,
            dry_run: false,
            ...record,
          },
          details: { message: 'Replayed message', errors: [] },
        });
      expect(ack({ found: true, replayed: 1 }).success).toBe(true);
      expect(
        ack({ found: false, outcome: 'not_visible', scanned: 500, truncated: true }).success
      ).toBe(true);
      expect(ack({}).success).toBe(false); // `found` is required
    });

    it('accepts discard acks for a hit and a not-visible miss', () => {
      const ack = (record: Record<string, unknown>) =>
        colonelDlqMessageDiscardResponseSchema.safeParse({
          shrimp: '',
          record: {
            queue: 'dlq.billing.event',
            message_id: 'm1',
            scanned: 1,
            truncated: false,
            discarded: false,
            original_queue: null,
            dry_run: false,
            ...record,
          },
          details: { message: 'Discarded message' },
        });
      expect(
        ack({ found: true, discarded: true, original_queue: 'billing.event.process' }).success
      ).toBe(true);
      expect(ack({ found: false, outcome: 'not_visible' }).success).toBe(true);
    });
  });

  describe('registry', () => {
    // The backend logic classes declare `SCHEMAS = { response: '<key>' }` with
    // exactly these keys; schema-scanner.spec.ts pairs them with this map.
    it.each([
      ['colonelJobs', colonelJobsResponseSchema],
      ['colonelChores', colonelChoresResponseSchema],
      ['colonelChoreRun', colonelChoreRunResponseSchema],
      ['colonelDlqMessageDetail', colonelDlqMessageDetailResponseSchema],
      ['colonelDlqMessageReplay', colonelDlqMessageReplayResponseSchema],
      ['colonelDlqMessageDiscard', colonelDlqMessageDiscardResponseSchema],
    ])('registers %s', (key, schema) => {
      expect(responseSchemas[key as keyof typeof responseSchemas]).toBe(schema);
    });
  });
});

/**
 * Refusal outcomes and run statuses (#4343 R1-2/R1-3/R1-4/R2-2). The server
 * sends these as plain strings; the schemas must accept them so the console
 * can branch on them instead of falling back to "response unreadable".
 */
describe('colonel Jobs schemas: refusal outcomes and run statuses (#4343)', () => {
  it.each(['success', 'partial', 'dry_run', 'skipped', 'aborted', 'something_new'])(
    'accepts RunChore status %s (a plain string, so a new value still parses)',
    (status) => {
      expect(colonelChoreRunResponseSchema.safeParse(choreRunPayload({ status })).success).toBe(
        true
      );
    }
  );

  it.each([
    DLQ_REPLAY_OUTCOME_NO_ORIGINAL_QUEUE,
    DLQ_REPLAY_OUTCOME_UNROUTABLE,
    'already_replayed',
    'replay_in_progress',
  ])('accepts a found replay ack KEPT in the DLQ with outcome %s', (outcome) => {
    const parsed = colonelDlqMessageReplayResponseSchema.safeParse({
      shrimp: '',
      record: {
        queue: 'dlq.billing.event',
        message_id: 'm1',
        found: true,
        outcome,
        scanned: 1,
        truncated: false,
        replayed: 0,
        failed: 0,
        would_replay: 0,
        dry_run: false,
      },
      details: {
        message: 'Not replayed',
        errors: [{ message_id: 'm1', error: 'Message kept in the DLQ.' }],
      },
    });
    expect(parsed.success).toBe(true);
    if (parsed.success) {
      expect(parsed.data.record.outcome).toBe(outcome);
      expect(parsed.data.details?.errors[0].error).toBe('Message kept in the DLQ.');
    }
  });

  it('accepts an unconfirmed discard ack (discarded false, outcome unknown)', () => {
    const parsed = colonelDlqMessageDiscardResponseSchema.safeParse({
      shrimp: '',
      record: {
        queue: 'dlq.billing.event',
        message_id: 'm1',
        found: true,
        outcome: DLQ_DISCARD_OUTCOME_UNCONFIRMED,
        scanned: 1,
        truncated: false,
        discarded: false,
        original_queue: 'billing.event.process',
        dry_run: false,
      },
      details: { message: 'The broker did not confirm the commit.' },
    });
    expect(parsed.success).toBe(true);
    if (parsed.success) {
      expect(parsed.data.record.outcome).toBe('unconfirmed');
      expect(parsed.data.details?.message).toBe('The broker did not confirm the commit.');
    }
  });

  it('pins the wire strings of the outcome constants the console branches on', () => {
    expect(DLQ_REPLAY_OUTCOME_NO_ORIGINAL_QUEUE).toBe('no_original_queue');
    expect(DLQ_REPLAY_OUTCOME_UNROUTABLE).toBe('unroutable');
    expect(DLQ_DISCARD_OUTCOME_UNCONFIRMED).toBe('unconfirmed');
  });
});
