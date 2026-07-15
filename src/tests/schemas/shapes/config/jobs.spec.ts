// src/tests/schemas/shapes/config/jobs.spec.ts
//
// Coverage for the jobs shape — top-level defaults, worker config bounds,
// scheduler/domain_refresh/expiration_warnings sub-trees, and the six
// maintenance jobs (phantom_cleanup, data_audit, participation_gc,
// index_rebuild, instances_rebuild, housekeeping).

import { describe, it, expect } from 'vitest';
import {
  jobsSchema,
  workerConfigSchema,
} from '@/schemas/contracts/config/section/jobs';
import {
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
} from '@/schemas/shapes/config/section/jobs';

describe('jobsShape — top-level defaults', () => {
  it('fills every documented default on empty input', () => {
    const result = jobsShape.parse({});
    expect(result.enabled).toBe(false);
    expect(result.rabbitmq_url).toBe('amqp://guest:guest@localhost:5672/dev');
    expect(result.channel_pool_size).toBe(5);
    expect(result.fallback_to_sync).toBe(true);
  });

  it('materializes nested job toggles with their enabled defaults on empty input', () => {
    // These blocks use the thunk+default pattern (like workers), so the whole
    // block materializes with its enabled default even when absent — unlike
    // domain_refresh (inline tree), which stays undefined when omitted. This
    // preserves the original flat-key semantics (a value on empty parse).
    const result = jobsShape.parse({});
    expect(result.plan_cache_refresh).toEqual({ enabled: false });
    expect(result.catalog_retry).toEqual({ enabled: false });
    expect(result.dlq_consumer).toEqual({ enabled: true });
  });

  it('applies nested enabled defaults when the block is present but empty', () => {
    const result = jobsShape.parse({
      plan_cache_refresh: {},
      catalog_retry: {},
      dlq_consumer: {},
    });
    expect(result.plan_cache_refresh?.enabled).toBe(false);
    expect(result.catalog_retry?.enabled).toBe(false);
    expect(result.dlq_consumer?.enabled).toBe(true);
  });

  it('contract leaves channel_pool_size undefined', () => {
    expect(jobsSchema.parse({}).channel_pool_size).toBeUndefined();
  });

  it('rejects non-positive channel_pool_size on the shape', () => {
    expect(() => jobsShape.parse({ channel_pool_size: 0 })).toThrow();
    expect(() => jobsShape.parse({ channel_pool_size: -1 })).toThrow();
  });

  it('rejects non-integer channel_pool_size on the shape', () => {
    expect(() => jobsShape.parse({ channel_pool_size: 1.5 })).toThrow();
  });
});

describe('workerConfigShape — positive-integer bounds', () => {
  it('accepts positive integers', () => {
    const result = workerConfigShape.parse({ threads: 4, prefetch: 10 });
    expect(result).toEqual({ threads: 4, prefetch: 10 });
  });

  it.each([
    ['threads', 0],
    ['threads', -3],
    ['threads', 1.5],
    ['prefetch', 0],
    ['prefetch', -2],
  ])('rejects %s = %s', (field, value) => {
    expect(() => workerConfigShape.parse({ threads: 1, prefetch: 1, [field]: value })).toThrow();
  });

  it('contract accepts the same bad values', () => {
    expect(() => workerConfigSchema.parse({ threads: 0, prefetch: -1 })).not.toThrow();
  });
});

describe('jobsWorkersShape — full worker defaults', () => {
  it('email worker defaults to { threads: 4, prefetch: 10 }', () => {
    expect(jobsWorkersShape.parse({}).email).toEqual({ threads: 4, prefetch: 10 });
  });

  it('notifications worker defaults to { threads: 2, prefetch: 10 }', () => {
    expect(jobsWorkersShape.parse({}).notifications).toEqual({ threads: 2, prefetch: 10 });
  });

  it('billing worker defaults to { threads: 2, prefetch: 5 }', () => {
    expect(jobsWorkersShape.parse({}).billing).toEqual({ threads: 2, prefetch: 5 });
  });

  it('partial worker overrides do NOT merge (Zod object default is all-or-nothing)', () => {
    // Documented foot-gun: `default({...})` on an object only fires when
    // the whole object is `undefined`, so passing a partial workers map
    // requires explicit override fields. The shape file explains the fix
    // when a partial-override consumer arrives.
    const result = jobsWorkersShape.parse({ email: { threads: 10, prefetch: 20 } });
    expect(result.email).toEqual({ threads: 10, prefetch: 20 });
  });
});

describe('jobsSchedulerShape', () => {
  it('enabled defaults to false', () => {
    expect(jobsSchedulerShape.parse({}).enabled).toBe(false);
  });
});

describe('scheduled-job enable toggles', () => {
  it('plan_cache_refresh.enabled defaults to false', () => {
    expect(jobsPlanCacheRefreshShape.parse({}).enabled).toBe(false);
  });

  it('catalog_retry.enabled defaults to false', () => {
    expect(jobsCatalogRetryShape.parse({}).enabled).toBe(false);
  });

  it('dlq_consumer.enabled defaults to true', () => {
    expect(jobsDlqConsumerShape.parse({}).enabled).toBe(true);
  });
});

describe('jobsDomainRefreshShape — defaults and bounds', () => {
  it('fills every default on empty input', () => {
    const result = jobsDomainRefreshShape.parse({});
    expect(result.enabled).toBe(false);
    expect(result.check_interval).toBe('30m');
    expect(result.batch_size).toBe(200);
    expect(result.rate_limit).toBe(0.5);
  });

  it('rejects non-positive batch_size', () => {
    expect(() => jobsDomainRefreshShape.parse({ batch_size: 0 })).toThrow();
  });

  it('accepts zero rate_limit (nonnegative bound)', () => {
    expect(() => jobsDomainRefreshShape.parse({ rate_limit: 0 })).not.toThrow();
  });

  it('rejects negative rate_limit', () => {
    expect(() => jobsDomainRefreshShape.parse({ rate_limit: -0.1 })).toThrow();
  });
});

describe('jobsExpirationWarningsShape — defaults and bounds', () => {
  it('fills every default on empty input', () => {
    const result = jobsExpirationWarningsShape.parse({});
    expect(result.enabled).toBe(false);
    expect(result.check_interval).toBe('1h');
    expect(result.warning_hours).toBe(24);
    expect(result.min_ttl_hours).toBe(48);
    expect(result.batch_size).toBe(100);
  });

  it.each([
    ['warning_hours', 0],
    ['min_ttl_hours', -1],
    ['batch_size', 0],
  ])('rejects %s = %s on the shape', (field, value) => {
    expect(() => jobsExpirationWarningsShape.parse({ [field]: value })).toThrow();
  });
});

describe('jobsMaintenanceShape — every sub-job tree applies defaults', () => {
  it('phantom_cleanup defaults', () => {
    const result = jobsMaintenanceShape.parse({ phantom_cleanup: {} });
    expect(result.phantom_cleanup).toEqual({
      enabled: false,
      interval: '1h',
      batch_size: 500,
      auto_repair: false,
    });
  });

  it('data_audit defaults', () => {
    const result = jobsMaintenanceShape.parse({ data_audit: {} });
    expect(result.data_audit).toEqual({
      enabled: false,
      interval: '6h',
      sample_size: 100,
    });
  });

  it('participation_gc defaults', () => {
    const result = jobsMaintenanceShape.parse({ participation_gc: {} });
    expect(result.participation_gc).toEqual({
      enabled: false,
      cron: '0 5 * * *',
      batch_size: 500,
      auto_repair: false,
    });
  });

  it('index_rebuild defaults', () => {
    const result = jobsMaintenanceShape.parse({ index_rebuild: {} });
    expect(result.index_rebuild).toEqual({
      enabled: false,
      cron: '0 4 * * *',
      auto_repair: false,
    });
  });

  it('instances_rebuild defaults', () => {
    const result = jobsMaintenanceShape.parse({ instances_rebuild: {} });
    expect(result.instances_rebuild).toEqual({
      enabled: false,
      cron: '0 3 * * 0',
      auto_repair: false,
    });
  });

  it('housekeeping defaults', () => {
    const result = jobsMaintenanceShape.parse({ housekeeping: {} });
    expect(result.housekeeping).toEqual({
      enabled: false,
      cron: '0 2 * * *',
    });
  });

  it('enabled toggle on the top-level maintenance object defaults to false', () => {
    expect(jobsMaintenanceShape.parse({}).enabled).toBe(false);
  });

  it('rejects non-positive batch_size on phantom_cleanup', () => {
    expect(() =>
      jobsMaintenanceShape.parse({ phantom_cleanup: { batch_size: 0 } })
    ).toThrow();
  });
});

describe('jobsShape — composed sub-trees', () => {
  it('applies maintenance subtree defaults when nested objects are empty', () => {
    const result = jobsShape.parse({
      maintenance: { phantom_cleanup: {}, data_audit: {}, housekeeping: {} },
    });
    expect(result.maintenance?.phantom_cleanup?.interval).toBe('1h');
    expect(result.maintenance?.data_audit?.sample_size).toBe(100);
    expect(result.maintenance?.housekeeping?.cron).toBe('0 2 * * *');
  });
});
