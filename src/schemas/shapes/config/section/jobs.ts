// src/schemas/shapes/config/section/jobs.ts

/**
 * Jobs Configuration Shape
 *
 * Adds runtime defaults and value constraints (positive/int) on top of the
 * type-only jobs contract from PR #3206.
 *
 * Workers (email/notifications/billing) and maintenance sub-jobs remain
 * `.optional()` deliberately. Per the contract-side rationale, defaulting
 * nested objects to `{}` conflates type description with runtime defaulting;
 * the parent decides whether sub-jobs exist. Partial worker overrides
 * (`workers: { email: { threads: 10 } }`) are still NOT supported by this
 * shape — `default({...})` on an object only fires when the whole object is
 * `undefined`. Adding field-level defaults here is the right fix only once
 * a partial-override consumer exists on main.
 *
 * @see src/schemas/contracts/config/section/jobs.ts
 */

import { z } from 'zod';

export {
  jobsSchema,
  jobsWorkersSchema,
  jobsSchedulerSchema,
  jobsDomainRefreshSchema,
  jobsExpirationWarningsSchema,
  jobsMaintenanceSchema,
  workerConfigSchema,
} from '@/schemas/contracts/config/section/jobs';

const workerConfigShape = z.object({
  threads: z.number().int().positive(),
  prefetch: z.number().int().positive(),
});

const jobsWorkersShape = z.object({
  email: workerConfigShape.default({ threads: 4, prefetch: 10 }),
  notifications: workerConfigShape.default({ threads: 2, prefetch: 10 }),
  billing: workerConfigShape.default({ threads: 2, prefetch: 5 }),
});

const jobsSchedulerShape = z.object({
  enabled: z.boolean().default(false),
});

const jobsDomainRefreshShape = z.object({
  enabled: z.boolean().default(false),
  check_interval: z.string().default('30m'),
  batch_size: z.number().int().positive().default(200),
  rate_limit: z.number().nonnegative().default(0.5),
});

const jobsExpirationWarningsShape = z.object({
  enabled: z.boolean().default(false),
  check_interval: z.string().default('1h'),
  warning_hours: z.number().int().positive().default(24),
  min_ttl_hours: z.number().int().positive().default(48),
  batch_size: z.number().int().positive().default(100),
});

const jobsPhantomCleanupShape = z.object({
  enabled: z.boolean().default(false),
  interval: z.string().default('1h'),
  batch_size: z.number().int().positive().default(500),
  auto_repair: z.boolean().default(false),
});

const jobsDataAuditShape = z.object({
  enabled: z.boolean().default(false),
  interval: z.string().default('6h'),
  sample_size: z.number().int().positive().default(100),
});

const jobsParticipationGcShape = z.object({
  enabled: z.boolean().default(false),
  cron: z.string().default('0 5 * * *'),
  batch_size: z.number().int().positive().default(500),
  auto_repair: z.boolean().default(false),
});

const jobsIndexRebuildShape = z.object({
  enabled: z.boolean().default(false),
  cron: z.string().default('0 4 * * *'),
  auto_repair: z.boolean().default(false),
});

const jobsInstancesRebuildShape = z.object({
  enabled: z.boolean().default(false),
  cron: z.string().default('0 3 * * 0'),
  auto_repair: z.boolean().default(false),
});

const jobsHousekeepingShape = z.object({
  enabled: z.boolean().default(false),
  cron: z.string().default('0 2 * * *'),
});

const jobsMaintenanceShape = z.object({
  enabled: z.boolean().default(false),
  phantom_cleanup: jobsPhantomCleanupShape.optional(),
  data_audit: jobsDataAuditShape.optional(),
  participation_gc: jobsParticipationGcShape.optional(),
  index_rebuild: jobsIndexRebuildShape.optional(),
  instances_rebuild: jobsInstancesRebuildShape.optional(),
  housekeeping: jobsHousekeepingShape.optional(),
});

const jobsShape = z.object({
  enabled: z.boolean().default(false),
  rabbitmq_url: z.string().default('amqp://guest:guest@localhost:5672/dev'),
  channel_pool_size: z.number().int().positive().default(5),
  fallback_to_sync: z.boolean().default(true),
  workers: jobsWorkersShape.optional(),
  scheduler: jobsSchedulerShape.optional(),
  plan_cache_refresh_enabled: z.boolean().default(false),
  catalog_retry_enabled: z.boolean().default(false),
  dlq_consumer_enabled: z.boolean().default(true),
  domain_refresh: jobsDomainRefreshShape.optional(),
  expiration_warnings: jobsExpirationWarningsShape.optional(),
  maintenance: jobsMaintenanceShape.optional(),
});

export {
  jobsShape,
  jobsWorkersShape,
  jobsSchedulerShape,
  jobsDomainRefreshShape,
  jobsExpirationWarningsShape,
  jobsMaintenanceShape,
  workerConfigShape,
};
