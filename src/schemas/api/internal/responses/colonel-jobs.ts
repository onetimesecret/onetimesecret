// src/schemas/api/internal/responses/colonel-jobs.ts
//
// Per-resource colonel/admin schemas for the Jobs screen (#4343): the rufus
// scheduler read-out and the on-demand chore triggers. The per-message DLQ
// shapes the same screen uses live with the other DLQ envelopes in
// ./colonel-queue.ts.
//
//   - ListJobs   → GET  /api/colonel/jobs              (scheduler catalog)
//   - ListChores → GET  /api/colonel/chores            (chore allowlist)
//   - RunChore   → POST /api/colonel/chores/:chore/run (preview or bounded run)
//
// Timestamps are Unix SECONDS (the JobRun hashes store `Familia.now.to_i`);
// durations are milliseconds. Every per-run field is nullable because a job
// that has never run, or a scheduler that has never booted, has no record.

import { createApiResponseSchema } from '@/schemas/api/base';
import { z } from 'zod';

import { paginationSchema } from './colonel';

// ============================================================================
// Shared enums
// ============================================================================

/** Status of a job's (or chore's) most recent run. `never` = no run recorded. */
export const jobRunStatusSchema = z.enum(['never', 'running', 'success', 'error', 'skipped']);

/** Which scheduled-job directory a job class lives in. */
export const jobGroupSchema = z.enum(['scheduled', 'maintenance']);

/**
 * Whether the RUNNING scheduler registered this job: `scheduled` when it was
 * registered at or after the scheduler's last boot, `not_scheduled` when the
 * scheduler booted without it (disabled by config), `unknown` when there is no
 * scheduler record to compare against.
 */
export const jobStateSchema = z.enum(['scheduled', 'not_scheduled', 'unknown']);

/** Which ScheduledJob helper registered the job (`cron`/`every`/`in_time`/`at_time`). */
export const jobScheduleKindSchema = z.enum(['cron', 'every', 'in', 'at']);

/** Chore family: housekeeping model chores, or the billing entitlement run. */
export const choreKindSchema = z.enum(['housekeeping', 'billing']);

// ============================================================================
// ListJobs
// ============================================================================

/** One scheduled job (ListJobs `details.jobs[]`). */
export const colonelJobSchema = z.object({
  /** Class basename minus `Job`, snake_cased (HeartbeatJob → heartbeat). */
  job_id: z.string(),
  job_class: z.string(),
  group: jobGroupSchema,
  state: jobStateSchema,
  /** The rufus helper that registered the job; null when never registered. */
  schedule_kind: jobScheduleKindSchema.nullable(),
  /** The cron pattern / interval / delay / time as registered. */
  schedule_expression: z.string().nullable(),
  /** Next occurrence; null when the job is `not_scheduled`. */
  next_time: z.number().nullable(),
  registered_at: z.number().nullable(),
  /** An aborted run reports `error` with `last_error` = `"aborted: <reason>"`. */
  last_status: jobRunStatusSchema,
  last_started_at: z.number().nullable(),
  last_finished_at: z.number().nullable(),
  last_duration_ms: z.number().nullable(),
  /**
   * `"ErrorClass: message"` (truncated, email addresses masked server-side),
   * null when blank.
   */
  last_error: z.string().nullable(),
  run_count: z.number(),
  error_count: z.number(),
});

/**
 * The scheduler process (ListJobs `record.scheduler`). `alive` is computed
 * server-side: a heartbeat within the last three heartbeat intervals.
 */
export const colonelSchedulerSchema = z.object({
  alive: z.boolean(),
  started_at: z.number().nullable(),
  heartbeat_at: z.number().nullable(),
  host: z.string().nullable(),
  pid: z.number().nullable(),
  job_count: z.number().nullable(),
});

/** ListJobs `record`. */
export const colonelJobsRecordSchema = z.object({
  scheduler: colonelSchedulerSchema,
});

/** ListJobs `details`: the job rows + the shared pagination envelope. */
export const colonelJobsDetailsSchema = z.object({
  jobs: z.array(colonelJobSchema),
  pagination: paginationSchema,
});

// ============================================================================
// ListChores
// ============================================================================

/**
 * One runnable chore (ListChores `details.chores[]`). `id` is the allowlist key
 * and the confirmation token: `housekeeping.<model>.<chore>` for a single
 * housekeeping chore, or `entitlement_materialize` for the billing run.
 * `cli` is the equivalent full-fleet command — the console run is bounded.
 */
export const colonelChoreSchema = z.object({
  id: z.string(),
  kind: choreKindSchema,
  model: z.string(),
  chores: z.array(z.string()),
  /** True when the server can preview the chore without writing. */
  supports_dry_run: z.boolean(),
  cli: z.string(),
  last_status: jobRunStatusSchema,
  last_started_at: z.number().nullable(),
  last_finished_at: z.number().nullable(),
  last_duration_ms: z.number().nullable(),
  last_error: z.string().nullable(),
  run_count: z.number(),
});

/** ListChores `details`: the chore rows + the shared pagination envelope. */
export const colonelChoresDetailsSchema = z.object({
  chores: z.array(colonelChoreSchema),
  pagination: paginationSchema,
});

// ============================================================================
// RunChore
// ============================================================================

/**
 * RunChore `record`. A console run is synchronous and bounded twice: by
 * `limit` (records) and by a wall-clock budget. `capped` = stopped at the
 * record limit; `budget_exhausted` = stopped when the time budget ran out.
 * Either way the counts in `details.report` are PARTIAL.
 */
export const colonelChoreRunRecordSchema = z.object({
  chore: z.string(),
  kind: choreKindSchema,
  /** `success` | `dry_run` | `skipped` | `aborted` (rendered, not branched on). */
  status: z.string(),
  dry_run: z.boolean(),
  limit: z.number(),
  capped: z.boolean(),
  budget_exhausted: z.boolean(),
  duration_ms: z.number().nullable(),
});

/**
 * RunChore `details`. `report` is the chore's own count summary — its keys
 * differ per kind (housekeeping: `scanned` + per-chore `modified`/`errors`;
 * billing: the materialize counters; preview: `would_scan` /
 * `would_materialize`) — so it is typed as an open record and shown verbatim.
 */
export const colonelChoreRunDetailsSchema = z.object({
  report: z.record(z.string(), z.unknown()),
  cli: z.string(),
});

// ============================================================================
// Type Exports
// ============================================================================

export type JobRunStatus = z.infer<typeof jobRunStatusSchema>;
export type ColonelJob = z.infer<typeof colonelJobSchema>;
export type ColonelScheduler = z.infer<typeof colonelSchedulerSchema>;
export type ColonelChore = z.infer<typeof colonelChoreSchema>;
export type ColonelChoreRunRecord = z.infer<typeof colonelChoreRunRecordSchema>;
export type ColonelChoreRunDetails = z.infer<typeof colonelChoreRunDetailsSchema>;

// Wrapped response schemas. Internal-only; never exposed publicly.

// GET /api/colonel/jobs → ListJobs
export const colonelJobsResponseSchema = createApiResponseSchema(
  colonelJobsRecordSchema,
  colonelJobsDetailsSchema
);

// GET /api/colonel/chores → ListChores
export const colonelChoresResponseSchema = createApiResponseSchema(
  z.object({}),
  colonelChoresDetailsSchema
);

// POST /api/colonel/chores/:chore/run → RunChore
export const colonelChoreRunResponseSchema = createApiResponseSchema(
  colonelChoreRunRecordSchema,
  colonelChoreRunDetailsSchema
);

export type ColonelJobsResponse = z.infer<typeof colonelJobsResponseSchema>;
export type ColonelChoresResponse = z.infer<typeof colonelChoresResponseSchema>;
export type ColonelChoreRunResponse = z.infer<typeof colonelChoreRunResponseSchema>;
