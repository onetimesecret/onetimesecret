// src/tests/apps/admin/useAdminJobs.spec.ts

import { createPinia, setActivePinia } from 'pinia';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const mockApi = {
  get: vi.fn(),
  post: vi.fn(),
  delete: vi.fn(),
};

vi.mock('@/shared/composables/useApi', () => ({
  useApi: () => mockApi,
}));

import { useAdminJobs } from '@/apps/admin/stores/useAdminJobs';

const NOW = 1_700_000_000;

// Wire-shaped ListJobs response (Unix-second numbers, JSON nulls) so the REAL
// colonelJobsResponseSchema runs unchanged.
function jobsPayload(overrides: { page?: number; per_page?: number } = {}) {
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
      jobs: [
        {
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
        },
      ],
      pagination: {
        page: overrides.page ?? 1,
        per_page: overrides.per_page ?? 50,
        total_count: 1,
        total_pages: 1,
      },
    },
  };
}

describe('useAdminJobs', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  it('uses its own store id', () => {
    expect(useAdminJobs().$id).toBe('adminJobs');
  });

  it('starts empty with initial fetch state', () => {
    const store = useAdminJobs();
    expect(store.jobs).toEqual([]);
    expect(store.scheduler).toBeNull();
    expect(store.pagination).toBeNull();
    expect(store.loading).toBe(false);
    expect(store.error).toBeNull();
    expect(store.validationError).toBeNull();
    expect(store.page).toBe(1);
    expect(store.perPage).toBe(50);
  });

  it('fetches the jobs endpoint with page/per_page and keeps the scheduler in lockstep', async () => {
    mockApi.get.mockResolvedValue({ data: jobsPayload() });
    const store = useAdminJobs();

    const result = await store.fetchPage(1);

    expect(mockApi.get).toHaveBeenCalledWith('/api/colonel/jobs', {
      params: { page: 1, per_page: 50 },
    });
    expect(result).not.toBeNull();
    expect(store.jobs).toHaveLength(1);
    expect(store.jobs[0].job_id).toBe('heartbeat');
    expect(store.scheduler).toEqual(
      expect.objectContaining({ alive: true, host: 'scheduler-1', pid: 4242, job_count: 16 })
    );
    expect(store.pagination).toEqual({ page: 1, per_page: 50, total_count: 1, total_pages: 1 });
  });

  it('reconciles page/per_page to what the server echoed', async () => {
    mockApi.get.mockResolvedValue({ data: jobsPayload({ page: 2, per_page: 10 }) });
    const store = useAdminJobs();

    await store.fetchPage(2);

    expect(store.page).toBe(2);
    expect(store.perPage).toBe(10);
  });

  it('degrades to empty on a schema mismatch without throwing', async () => {
    const payload = jobsPayload();
    (payload.details.jobs[0] as Record<string, unknown>).last_status = 'bogus';
    mockApi.get.mockResolvedValue({ data: payload });
    const store = useAdminJobs();

    const result = await store.fetchPage(1);

    expect(result).toBeNull();
    expect(store.jobs).toEqual([]);
    expect(store.scheduler).toBeNull();
    expect(store.pagination).toBeNull();
    expect(store.validationError).toBe('ColonelJobsResponse');
    expect(store.error).toBeNull();
  });

  it('clears rows and the scheduler, then rethrows, on a network/HTTP error', async () => {
    mockApi.get.mockResolvedValueOnce({ data: jobsPayload() });
    const store = useAdminJobs();
    await store.fetchPage(1);
    expect(store.scheduler).not.toBeNull();

    mockApi.get.mockRejectedValueOnce(new Error('Network Error'));
    await expect(store.fetchPage(1)).rejects.toThrow('Network Error');

    expect(store.jobs).toEqual([]);
    expect(store.scheduler).toBeNull();
    expect(store.pagination).toBeNull();
    expect(store.error?.message).toBe('Network Error');
  });

  it('$reset restores initial state', async () => {
    mockApi.get.mockResolvedValue({ data: jobsPayload({ page: 3, per_page: 25 }) });
    const store = useAdminJobs();
    await store.fetchPage(3);

    store.$reset();

    expect(store.jobs).toEqual([]);
    expect(store.scheduler).toBeNull();
    expect(store.pagination).toBeNull();
    expect(store.page).toBe(1);
    expect(store.perPage).toBe(50);
  });
});
