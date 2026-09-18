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
          pagination: { ...pagination, capped: true },
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
          pagination,
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
