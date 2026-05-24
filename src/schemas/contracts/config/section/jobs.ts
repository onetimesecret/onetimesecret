// src/schemas/contracts/config/section/jobs.ts

/**
 * Jobs Configuration Schema
 *
 * Maps to the `jobs:` section in config.defaults.yaml
 * Async processing for emails, notifications, webhooks, and scheduled tasks.
 */

import { z } from 'zod';

/**
 * Worker thread/prefetch configuration
 */
const workerConfigSchema = z.object({
  threads: z.number().int().positive(),
  prefetch: z.number().int().positive(),
});

/**
 * Workers configuration (consumer processes)
 */
const jobsWorkersSchema = z.object({
  email: workerConfigSchema.default({ threads: 4, prefetch: 10 }),
  notifications: workerConfigSchema.default({ threads: 2, prefetch: 10 }),
  billing: workerConfigSchema.default({ threads: 2, prefetch: 5 }),
});

/**
 * Scheduler configuration (rufus-scheduler daemon)
 */
const jobsSchedulerSchema = z.object({
  enabled: z.boolean().default(false),
});

/**
 * Domain refresh job configuration
 */
const jobsDomainRefreshSchema = z.object({
  enabled: z.boolean().default(false),
  check_interval: z.string().default('30m'),
  batch_size: z.number().int().positive().default(200),
  rate_limit: z.number().nonnegative().default(0.5),
});

/**
 * Expiration warning email job configuration
 */
const jobsExpirationWarningsSchema = z.object({
  enabled: z.boolean().default(false),
  check_interval: z.string().default('1h'),
  warning_hours: z.number().int().positive().default(24),
  min_ttl_hours: z.number().int().positive().default(48),
  batch_size: z.number().int().positive().default(100),
});

/**
 * Maintenance phase configurations
 *
 * All maintenance jobs ship with auto_repair: false — enable only after
 * reviewing audit reports over multiple cycles.
 */
const jobsPhantomCleanupSchema = z.object({
  enabled: z.boolean().default(false),
  interval: z.string().default('1h'),
  batch_size: z.number().int().positive().default(500),
  auto_repair: z.boolean().default(false),
});

const jobsDataAuditSchema = z.object({
  enabled: z.boolean().default(false),
  interval: z.string().default('6h'),
  sample_size: z.number().int().positive().default(100),
});

const jobsParticipationGcSchema = z.object({
  enabled: z.boolean().default(false),
  cron: z.string().default('0 5 * * *'),
  batch_size: z.number().int().positive().default(500),
  auto_repair: z.boolean().default(false),
});

const jobsIndexRebuildSchema = z.object({
  enabled: z.boolean().default(false),
  cron: z.string().default('0 4 * * *'),
  auto_repair: z.boolean().default(false),
});

const jobsInstancesRebuildSchema = z.object({
  enabled: z.boolean().default(false),
  cron: z.string().default('0 3 * * 0'),
  auto_repair: z.boolean().default(false),
});

const jobsHousekeepingSchema = z.object({
  enabled: z.boolean().default(false),
  cron: z.string().default('0 2 * * *'),
});

/**
 * Maintenance jobs configuration (Redis data consistency checks and repairs)
 */
const jobsMaintenanceSchema = z.object({
  enabled: z.boolean().default(false),
  phantom_cleanup: jobsPhantomCleanupSchema.optional(),
  data_audit: jobsDataAuditSchema.optional(),
  participation_gc: jobsParticipationGcSchema.optional(),
  index_rebuild: jobsIndexRebuildSchema.optional(),
  instances_rebuild: jobsInstancesRebuildSchema.optional(),
  housekeeping: jobsHousekeepingSchema.optional(),
});

/**
 * Complete jobs schema
 */
const jobsSchema = z.object({
  enabled: z.boolean().default(false),
  rabbitmq_url: z.string().default('amqp://guest:guest@localhost:5672/dev'),
  channel_pool_size: z.number().int().positive().default(5),
  fallback_to_sync: z.boolean().default(true),
  workers: jobsWorkersSchema.optional(),
  scheduler: jobsSchedulerSchema.optional(),
  plan_cache_refresh_enabled: z.boolean().default(false),
  catalog_retry_enabled: z.boolean().default(false),
  dlq_consumer_enabled: z.boolean().default(true),
  domain_refresh: jobsDomainRefreshSchema.optional(),
  expiration_warnings: jobsExpirationWarningsSchema.optional(),
  maintenance: jobsMaintenanceSchema.optional(),
});

export {
  jobsSchema,
  jobsWorkersSchema,
  jobsSchedulerSchema,
  jobsDomainRefreshSchema,
  jobsExpirationWarningsSchema,
  jobsMaintenanceSchema,
  workerConfigSchema,
};
