// src/tests/apps/admin/useAdminDlq.spec.ts

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

import { useAdminDlq } from '@/apps/admin/stores/useAdminDlq';

// ListDlqs `success_data`: a healthy queue + a configured-but-undeclared one.
function dlqPayload(
  overrides: { connected?: boolean | null; page?: number; queues?: string[] } = {}
) {
  const dlqs = overrides.queues
    ? overrides.queues.map((queue) => ({ queue, messages: 1, consumers: 0 }))
    : [
        { queue: 'dlq.billing.event', messages: 3, consumers: 0 },
        { queue: 'dlq.email.message', messages: 0, error: 'not declared' },
      ];
  return {
    shrimp: '',
    record: {},
    details: {
      dlqs,
      pagination: {
        page: overrides.page ?? 1,
        per_page: 50,
        total_count: dlqs.length,
        total_pages: 1,
      },
      connected: overrides.connected === undefined ? true : overrides.connected,
    },
  };
}

/** Manually-settled promise so a test controls the order responses arrive. */
function deferred<T>() {
  let resolve!: (value: T) => void;
  let reject!: (reason?: unknown) => void;
  const promise = new Promise<T>((res, rej) => {
    resolve = res;
    reject = rej;
  });
  return { promise, resolve, reject };
}

describe('useAdminDlq', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  it('uses its own store id', () => {
    expect(useAdminDlq().$id).toBe('adminDlq');
  });

  it('starts empty with initial fetch state', () => {
    const store = useAdminDlq();
    expect(store.dlqs).toEqual([]);
    expect(store.connected).toBeNull();
    expect(store.pagination).toBeNull();
    expect(store.loading).toBe(false);
    expect(store.error).toBeNull();
    expect(store.validationError).toBeNull();
  });

  it('fetches the DLQ list and records the broker flag', async () => {
    mockApi.get.mockResolvedValue({ data: dlqPayload() });
    const store = useAdminDlq();

    await store.fetchPage(1);

    expect(mockApi.get).toHaveBeenCalledWith('/api/colonel/queues/dlq', {
      params: { page: 1, per_page: 50 },
    });
    expect(store.dlqs.map((d) => d.queue)).toEqual(['dlq.billing.event', 'dlq.email.message']);
    expect(store.dlqs[1].error).toBe('not declared');
    expect(store.connected).toBe(true);
  });

  it('reports a disconnected broker as false, not as unknown', async () => {
    mockApi.get.mockResolvedValue({ data: dlqPayload({ connected: false }) });
    const store = useAdminDlq();

    await store.fetchPage(1);

    expect(store.connected).toBe(false);
  });

  it('degrades to empty on a schema mismatch without throwing', async () => {
    mockApi.get.mockResolvedValue({ data: { record: {}, details: { dlqs: 'nope' } } });
    const store = useAdminDlq();

    const result = await store.fetchPage(1);

    expect(result).toBeNull();
    expect(store.dlqs).toEqual([]);
    expect(store.connected).toBeNull();
    expect(store.validationError).toBe('ColonelDlqListResponse');
    expect(store.error).toBeNull();
  });

  it('clears rows and the broker flag, then rethrows, on a network/HTTP error', async () => {
    mockApi.get.mockResolvedValueOnce({ data: dlqPayload() });
    const store = useAdminDlq();
    await store.fetchPage(1);

    mockApi.get.mockRejectedValueOnce(new Error('Network Error'));
    await expect(store.fetchPage(1)).rejects.toThrow('Network Error');

    expect(store.dlqs).toEqual([]);
    expect(store.connected).toBeNull();
    expect(store.pagination).toBeNull();
    expect(store.error?.message).toBe('Network Error');
  });

  describe('overlapping requests', () => {
    it('a stale page response never replaces the newer page or its broker flag', async () => {
      const slow = deferred<{ data: unknown }>();
      const fast = deferred<{ data: unknown }>();
      mockApi.get
        .mockImplementationOnce(() => slow.promise)
        .mockImplementationOnce(() => fast.promise);
      const store = useAdminDlq();

      const first = store.fetchPage(1);
      const second = store.fetchPage(2);

      fast.resolve({ data: dlqPayload({ page: 2, queues: ['dlq.page2'] }) });
      await second;
      expect(store.dlqs.map((d) => d.queue)).toEqual(['dlq.page2']);
      expect(store.connected).toBe(true);

      // Page 1 settles late, with a disconnected broker. Nothing may land.
      slow.resolve({ data: dlqPayload({ page: 1, queues: ['dlq.page1'], connected: false }) });
      await first;

      expect(store.dlqs.map((d) => d.queue)).toEqual(['dlq.page2']);
      expect(store.connected).toBe(true);
      expect(store.pagination?.page).toBe(2);
      expect(store.page).toBe(2);
    });

    it('a stale failure neither blanks the newer rows nor clears the broker flag', async () => {
      const slow = deferred<{ data: unknown }>();
      const fast = deferred<{ data: unknown }>();
      mockApi.get
        .mockImplementationOnce(() => slow.promise)
        .mockImplementationOnce(() => fast.promise);
      const store = useAdminDlq();

      const first = store.fetchPage(1);
      const second = store.fetchPage(2);

      fast.resolve({ data: dlqPayload({ page: 2, queues: ['dlq.page2'] }) });
      await second;

      slow.reject(new Error('socket hang up'));
      // The caller of the stale request still sees its own failure.
      await expect(first).rejects.toThrow('socket hang up');

      expect(store.dlqs.map((d) => d.queue)).toEqual(['dlq.page2']);
      expect(store.connected).toBe(true);
      expect(store.pagination?.page).toBe(2);
      expect(store.error).toBeNull();
      expect(store.loading).toBe(false);
    });

    it('a stale schema mismatch does not empty the newer page', async () => {
      const slow = deferred<{ data: unknown }>();
      const fast = deferred<{ data: unknown }>();
      mockApi.get
        .mockImplementationOnce(() => slow.promise)
        .mockImplementationOnce(() => fast.promise);
      const store = useAdminDlq();

      const first = store.fetchPage(1);
      const second = store.fetchPage(2);

      fast.resolve({ data: dlqPayload({ page: 2, queues: ['dlq.page2'] }) });
      await second;

      slow.resolve({ data: { record: {}, details: { dlqs: 'nope' } } });
      expect(await first).toBeNull();

      expect(store.dlqs.map((d) => d.queue)).toEqual(['dlq.page2']);
      expect(store.connected).toBe(true);
      expect(store.validationError).toBeNull();
    });

    it('$reset invalidates an in-flight request', async () => {
      const slow = deferred<{ data: unknown }>();
      mockApi.get.mockImplementationOnce(() => slow.promise);
      const store = useAdminDlq();

      const pending = store.fetchPage(2);
      store.$reset();

      slow.resolve({ data: dlqPayload({ page: 2 }) });
      await pending;

      expect(store.dlqs).toEqual([]);
      expect(store.connected).toBeNull();
      expect(store.pagination).toBeNull();
      expect(store.page).toBe(1);
    });
  });

  it('$reset restores initial state', async () => {
    mockApi.get.mockResolvedValue({ data: dlqPayload({ page: 2 }) });
    const store = useAdminDlq();
    await store.fetchPage(2);

    store.$reset();

    expect(store.dlqs).toEqual([]);
    expect(store.connected).toBeNull();
    expect(store.pagination).toBeNull();
    expect(store.page).toBe(1);
  });
});
