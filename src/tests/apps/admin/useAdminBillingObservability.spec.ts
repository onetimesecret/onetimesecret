// src/tests/apps/admin/useAdminBillingObservability.spec.ts

import { createPinia, setActivePinia } from 'pinia';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const mockApi = { get: vi.fn() };
vi.mock('@/shared/composables/useApi', () => ({ useApi: () => mockApi }));

import {
  PENDING_FEDERATED_SUBSCRIPTIONS_URL,
  useAdminPendingFederatedSubscriptions,
} from '@/apps/admin/stores/useAdminPendingFederatedSubscriptions';
import {
  WEBHOOK_EVENTS_URL,
  useAdminWebhookEvents,
} from '@/apps/admin/stores/useAdminWebhookEvents';

const pagination = { page: 1, per_page: 50, total_count: 1, total_pages: 1 };

describe('billing observability stores', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
  });
  afterEach(() => vi.clearAllMocks());

  it('fetches one webhook-event page and retains the capped signal', async () => {
    mockApi.get.mockResolvedValue({
      data: {
        record: {},
        details: {
          events: [
            {
              event_id: 'evt_123',
              event_type: 'invoice.paid',
              processing_status: 'success',
              processing_outcome: 'Processed',
              received_at: 1_780_000_000,
              processed_at: 1_780_000_001,
              attempt_count: 1,
              retryable: false,
            },
          ],
          pagination: { ...pagination, capped: true, stale_count: 3 },
        },
      },
    });
    const store = useAdminWebhookEvents();

    await store.fetchPage(1);

    expect(mockApi.get).toHaveBeenCalledWith(WEBHOOK_EVENTS_URL, {
      params: { page: 1, per_page: 50 },
    });
    expect(store.events[0].event_id).toBe('evt_123');
    expect(store.capped).toBe(true);
    expect(store.staleCount).toBe(3);
  });

  it('reads staleCount from details root when pagination omits it', async () => {
    mockApi.get.mockResolvedValue({
      data: {
        record: {},
        details: {
          events: [],
          pagination,
          stale_count: 5,
        },
      },
    });
    const store = useAdminWebhookEvents();

    await store.fetchPage(1);

    expect(store.staleCount).toBe(5);
  });

  it('fetches pending subscriptions without accumulating pages', async () => {
    mockApi.get.mockResolvedValue({
      data: {
        record: {},
        details: {
          subscriptions: [
            {
              subscription_status: 'active',
              planid: null,
              region: 'us',
              received_at: 1_780_000_000,
              source_webhook: {
                state: 'no_correlation',
                processing_status: null,
                outcome: null,
              },
            },
          ],
          pagination: { ...pagination, stale_count: 2 },
        },
      },
    });
    const store = useAdminPendingFederatedSubscriptions();

    await store.fetchPage(1);

    expect(mockApi.get).toHaveBeenCalledWith(PENDING_FEDERATED_SUBSCRIPTIONS_URL, {
      params: { page: 1, per_page: 50 },
    });
    expect(store.subscriptions).toHaveLength(1);
    expect(store.subscriptions[0].source_webhook.state).toBe('no_correlation');
    expect(store.staleCount).toBe(2);
  });

  it('resets pending staleCount on a failed page fetch', async () => {
    mockApi.get.mockResolvedValueOnce({
      data: {
        record: {},
        details: {
          subscriptions: [],
          pagination: { ...pagination, stale_count: 4 },
        },
      },
    });
    const store = useAdminPendingFederatedSubscriptions();
    await store.fetchPage(1);
    expect(store.staleCount).toBe(4);

    mockApi.get.mockRejectedValueOnce(new Error('Network Error'));
    await expect(store.fetchPage(2)).rejects.toThrow('Network Error');
    expect(store.staleCount).toBe(0);
  });

  it('clears stale rows after a failed response', async () => {
    mockApi.get.mockResolvedValue({ data: { record: {}, details: { events: [], pagination } } });
    const store = useAdminWebhookEvents();
    await store.fetchPage(1);

    mockApi.get.mockRejectedValue(new Error('Network Error'));
    await expect(store.fetchPage(2)).rejects.toThrow('Network Error');

    expect(store.events).toEqual([]);
    expect(store.pagination).toBeNull();
  });
});
