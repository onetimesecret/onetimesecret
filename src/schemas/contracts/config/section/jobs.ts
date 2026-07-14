// src/schemas/contracts/config/section/jobs.ts

/**
 * Jobs Configuration Schema
 *
 * Maps to the `jobs:` section in config.defaults.yaml
 * Async processing for emails, notifications, webhooks, and scheduled tasks.
 *
 * Per contracts convention, this schema describes field names and types only.
 * Defaults, value constraints (positive/int/min/max), and runtime validation
 * belong in shapes — not here.
 */

import { z } from 'zod';

const workerConfigSchema = z.object({
  threads: z.number(),
  prefetch: z.number(),
});

const jobsWorkersSchema = z.object({
  email: workerConfigSchema.optional(),
  notifications: workerConfigSchema.optional(),
  billing: workerConfigSchema.optional(),
});

const jobsSchedulerSchema = z.object({
  enabled: z.boolean(),
});

const jobsDomainRefreshSchema = z.object({
  enabled: z.boolean().optional(),
  check_interval: z.string().optional(),
  batch_size: z.number().optional(),
  rate_limit: z.number().optional(),
});

const jobsExpirationWarningsSchema = z.object({
  enabled: z.boolean().optional(),
  check_interval: z.string().optional(),
  warning_hours: z.number().optional(),
  min_ttl_hours: z.number().optional(),
  batch_size: z.number().optional(),
});

const jobsFaviconFetchSchema = z.object({
  enabled: z.boolean().optional(),
  timeout: z.number().optional(),
  max_response_bytes: z.number().optional(),
  max_redirects: z.number().optional(),
  allowed_content_types: z.array(z.string()).optional(),
});

const jobsPhantomCleanupSchema = z.object({
  enabled: z.boolean().optional(),
  interval: z.string().optional(),
  batch_size: z.number().optional(),
  auto_repair: z.boolean().optional(),
});

const jobsDataAuditSchema = z.object({
  enabled: z.boolean().optional(),
  interval: z.string().optional(),
  sample_size: z.number().optional(),
});

const jobsParticipationGcSchema = z.object({
  enabled: z.boolean().optional(),
  cron: z.string().optional(),
  batch_size: z.number().optional(),
  auto_repair: z.boolean().optional(),
});

const jobsIndexRebuildSchema = z.object({
  enabled: z.boolean().optional(),
  cron: z.string().optional(),
  auto_repair: z.boolean().optional(),
});

const jobsInstancesRebuildSchema = z.object({
  enabled: z.boolean().optional(),
  cron: z.string().optional(),
  auto_repair: z.boolean().optional(),
});

const jobsHousekeepingSchema = z.object({
  enabled: z.boolean().optional(),
  cron: z.string().optional(),
});

const jobsMaintenanceSchema = z.object({
  enabled: z.boolean().optional(),
  phantom_cleanup: jobsPhantomCleanupSchema.optional(),
  data_audit: jobsDataAuditSchema.optional(),
  participation_gc: jobsParticipationGcSchema.optional(),
  index_rebuild: jobsIndexRebuildSchema.optional(),
  instances_rebuild: jobsInstancesRebuildSchema.optional(),
  housekeeping: jobsHousekeepingSchema.optional(),
});

const jobsSchema = z.object({
  enabled: z.boolean().optional(),
  rabbitmq_url: z.string().optional(),
  channel_pool_size: z.number().optional(),
  fallback_to_sync: z.boolean().optional(),
  workers: jobsWorkersSchema.optional(),
  scheduler: jobsSchedulerSchema.optional(),
  plan_cache_refresh_enabled: z.boolean().optional(),
  catalog_retry_enabled: z.boolean().optional(),
  dlq_consumer_enabled: z.boolean().optional(),
  domain_refresh: jobsDomainRefreshSchema.optional(),
  expiration_warnings: jobsExpirationWarningsSchema.optional(),
  favicon_fetch: jobsFaviconFetchSchema.optional(),
  maintenance: jobsMaintenanceSchema.optional(),
});

export {
  jobsSchema,
  jobsWorkersSchema,
  jobsSchedulerSchema,
  jobsDomainRefreshSchema,
  jobsExpirationWarningsSchema,
  jobsFaviconFetchSchema,
  jobsMaintenanceSchema,
  workerConfigSchema,
};
