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
 * `undefined`. The `augment` helper makes the fix trivial when a consumer
 * for partial overrides shows up: replace the `email: () => workerConfigShape.default({...})`
 * leaf with a sub-tree `{ threads: (n) => n.int().positive().default(4) }`.
 *
 * @see src/schemas/contracts/config/section/jobs.ts
 */

import {
  jobsSchema,
  jobsWorkersSchema,
  jobsSchedulerSchema,
  jobsPlanCacheRefreshSchema,
  jobsCatalogRetrySchema,
  jobsDlqConsumerSchema,
  jobsDomainRefreshSchema,
  jobsExpirationWarningsSchema,
  jobsMaintenanceSchema,
  workerConfigSchema,
} from '@/schemas/contracts/config/section/jobs';
import { augment, type AugmentTree } from '@/schemas/utils/augment';

export {
  jobsSchema,
  jobsWorkersSchema,
  jobsSchedulerSchema,
  jobsPlanCacheRefreshSchema,
  jobsCatalogRetrySchema,
  jobsDlqConsumerSchema,
  jobsDomainRefreshSchema,
  jobsExpirationWarningsSchema,
  jobsMaintenanceSchema,
  workerConfigSchema,
};

const workerConfigShape = augment(workerConfigSchema, {
  threads: (n) => n.int().positive(),
  prefetch: (n) => n.int().positive(),
});

const jobsWorkersShape = augment(jobsWorkersSchema, {
  email: () => workerConfigShape.default({ threads: 4, prefetch: 10 }),
  notifications: () => workerConfigShape.default({ threads: 2, prefetch: 10 }),
  billing: () => workerConfigShape.default({ threads: 2, prefetch: 5 }),
});

const jobsSchedulerShape = augment(jobsSchedulerSchema, {
  enabled: (b) => b.default(false),
});

const jobsPlanCacheRefreshShape = augment(jobsPlanCacheRefreshSchema, {
  enabled: (b) => b.default(false),
});

const jobsCatalogRetryShape = augment(jobsCatalogRetrySchema, {
  enabled: (b) => b.default(false),
});

const jobsDlqConsumerShape = augment(jobsDlqConsumerSchema, {
  enabled: (b) => b.default(true),
});

const jobsDomainRefreshShape = augment(jobsDomainRefreshSchema, {
  enabled: (b) => b.default(false),
  check_interval: (s) => s.default('30m'),
  batch_size: (n) => n.int().positive().default(200),
  rate_limit: (n) => n.nonnegative().default(0.5),
});

const jobsExpirationWarningsShape = augment(jobsExpirationWarningsSchema, {
  enabled: (b) => b.default(false),
  check_interval: (s) => s.default('1h'),
  warning_hours: (n) => n.int().positive().default(24),
  min_ttl_hours: (n) => n.int().positive().default(48),
  batch_size: (n) => n.int().positive().default(100),
});

const maintenancePhantomCleanupTree: AugmentTree = {
  enabled: (b) => b.default(false),
  interval: (s) => s.default('1h'),
  batch_size: (n) => n.int().positive().default(500),
  auto_repair: (b) => b.default(false),
};

const maintenanceDataAuditTree: AugmentTree = {
  enabled: (b) => b.default(false),
  interval: (s) => s.default('6h'),
  sample_size: (n) => n.int().positive().default(100),
};

const maintenanceParticipationGcTree: AugmentTree = {
  enabled: (b) => b.default(false),
  cron: (s) => s.default('0 5 * * *'),
  batch_size: (n) => n.int().positive().default(500),
  auto_repair: (b) => b.default(false),
};

const maintenanceIndexRebuildTree: AugmentTree = {
  enabled: (b) => b.default(false),
  cron: (s) => s.default('0 4 * * *'),
  auto_repair: (b) => b.default(false),
};

const maintenanceInstancesRebuildTree: AugmentTree = {
  enabled: (b) => b.default(false),
  cron: (s) => s.default('0 3 * * 0'),
  auto_repair: (b) => b.default(false),
};

const maintenanceHousekeepingTree: AugmentTree = {
  enabled: (b) => b.default(false),
  cron: (s) => s.default('0 2 * * *'),
};

const jobsMaintenanceShape = augment(jobsMaintenanceSchema, {
  enabled: (b) => b.default(false),
  phantom_cleanup: maintenancePhantomCleanupTree,
  data_audit: maintenanceDataAuditTree,
  participation_gc: maintenanceParticipationGcTree,
  index_rebuild: maintenanceIndexRebuildTree,
  instances_rebuild: maintenanceInstancesRebuildTree,
  housekeeping: maintenanceHousekeepingTree,
});

const jobsShape = augment(jobsSchema, {
  enabled: (b) => b.default(false),
  rabbitmq_url: (s) => s.default('amqp://guest:guest@localhost:5672/dev'),
  channel_pool_size: (n) => n.int().positive().default(5),
  fallback_to_sync: (b) => b.default(true),
  workers: {
    email: () => workerConfigShape.default({ threads: 4, prefetch: 10 }),
    notifications: () => workerConfigShape.default({ threads: 2, prefetch: 10 }),
    billing: () => workerConfigShape.default({ threads: 2, prefetch: 5 }),
  },
  scheduler: { enabled: (b) => b.default(false) },
  plan_cache_refresh: () => jobsPlanCacheRefreshShape.default({ enabled: false }),
  catalog_retry: () => jobsCatalogRetryShape.default({ enabled: false }),
  dlq_consumer: () => jobsDlqConsumerShape.default({ enabled: true }),
  domain_refresh: {
    enabled: (b) => b.default(false),
    check_interval: (s) => s.default('30m'),
    batch_size: (n) => n.int().positive().default(200),
    rate_limit: (n) => n.nonnegative().default(0.5),
  },
  expiration_warnings: {
    enabled: (b) => b.default(false),
    check_interval: (s) => s.default('1h'),
    warning_hours: (n) => n.int().positive().default(24),
    min_ttl_hours: (n) => n.int().positive().default(48),
    batch_size: (n) => n.int().positive().default(100),
  },
  maintenance: {
    enabled: (b) => b.default(false),
    phantom_cleanup: maintenancePhantomCleanupTree,
    data_audit: maintenanceDataAuditTree,
    participation_gc: maintenanceParticipationGcTree,
    index_rebuild: maintenanceIndexRebuildTree,
    instances_rebuild: maintenanceInstancesRebuildTree,
    housekeeping: maintenanceHousekeepingTree,
  },
});

export {
  jobsShape,
  jobsWorkersShape,
  jobsSchedulerShape,
  jobsPlanCacheRefreshShape,
  jobsCatalogRetryShape,
  jobsDlqConsumerShape,
  jobsDomainRefreshShape,
  jobsExpirationWarningsShape,
  jobsMaintenanceShape,
  workerConfigShape,
};
