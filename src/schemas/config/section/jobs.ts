// src/schemas/config/section/jobs.ts

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
 * Workers configuration
 */
const jobsWorkersSchema = z.object({
  email: workerConfigSchema.default({ threads: 4, prefetch: 10 }),
  notifications: workerConfigSchema.default({ threads: 2, prefetch: 10 }),
  billing: workerConfigSchema.default({ threads: 2, prefetch: 5 }),
});

/**
 * Scheduler configuration
 */
const jobsSchedulerSchema = z.object({
  enabled: z.boolean().default(false),
});

/**
 * Expiration warnings configuration
 */
const jobsExpirationWarningsSchema = z.object({
  enabled: z.boolean().default(false),
  check_interval: z.string().default('1h'),
  warning_hours: z.number().int().positive().default(24),
  min_ttl_hours: z.number().int().positive().default(48),
  batch_size: z.number().int().positive().default(100),
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
  expiration_warnings: jobsExpirationWarningsSchema.optional(),
});

export { jobsSchema, jobsWorkersSchema, jobsSchedulerSchema, jobsExpirationWarningsSchema };
