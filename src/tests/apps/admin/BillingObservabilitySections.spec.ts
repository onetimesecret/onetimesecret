// src/tests/apps/admin/BillingObservabilitySections.spec.ts

import { flushPromises, mount, VueWrapper } from '@vue/test-utils';
import { createPinia, setActivePinia } from 'pinia';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const mockApi = { get: vi.fn() };
vi.mock('@/shared/composables/useApi', () => ({ useApi: () => mockApi }));
vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: { template: '<span />', props: ['collection', 'name', 'size', 'class'] },
}));

import PendingFederatedSubscriptionsSection from '@/apps/admin/components/billing/PendingFederatedSubscriptionsSection.vue';
import WebhookEventsSection from '@/apps/admin/components/billing/WebhookEventsSection.vue';
import { createTestI18n } from '@tests/setup';

const i18n = createTestI18n();
const webhookUrl = '/api/colonel/billing/webhook-events';
const pendingUrl = '/api/colonel/billing/pending-federated-subscriptions';
const pagination = { page: 1, per_page: 50, total_count: 1, total_pages: 1 };

const drawerStub = {
  props: ['open', 'title', 'subtitle', 'testid'],
  emits: ['update:open', 'close'],
  template: '<aside v-if="open" :data-testid="testid"><slot /></aside>',
};

function webhookList() {
  return {
    record: {},
    details: {
      events: [
        {
          event_id: 'evt_123',
          event_type: 'customer.subscription.updated',
          processing_status: 'failed',
          processing_outcome: 'Failed',
          received_at: 1_780_000_000,
          processed_at: null,
          attempt_count: 2,
          retryable: true,
        },
      ],
      pagination,
    },
  };
}

function pendingList(state: 'available' | 'no_correlation' | 'expired' = 'expired') {
  return {
    record: {},
    details: {
      subscriptions: [
        {
          subscription_status: 'active',
          planid: null,
          region: 'eu',
          received_at: 1_780_000_000,
          source_webhook: {
            state,
            processing_status: state === 'available' ? 'success' : null,
            outcome: state === 'available' ? 'Processed' : null,
          },
        },
      ],
      pagination: { ...pagination, capped: true },
    },
  };
}

describe('billing observability sections', () => {
  let wrapper: VueWrapper;

  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
  });
  afterEach(() => wrapper?.unmount());

  it('renders webhook event metadata and only fetches detail after explicit selection', async () => {
    mockApi.get.mockImplementation((url: string) => {
      if (url === webhookUrl) return Promise.resolve({ data: webhookList() });
      return Promise.resolve({
        data: {
          record: {
            ...webhookList().details.events[0],
            event_payload: { hidden: true },
          },
          details: {
            api_version: '2026-01-01',
            livemode: true,
            stripe_created_at: 1_779_999_000,
            pending_webhooks: 0,
            last_attempt_at: 1_780_000_030,
            retryable: true,
            max_attempts_reached: false,
            circuit_retry_at: null,
            circuit_retry_count: 0,
            error_present: true,
          },
        },
      });
    });
    wrapper = mount(WebhookEventsSection, {
      global: { plugins: [i18n], stubs: { DetailDrawer: drawerStub } },
    });
    await flushPromises();

    const table = wrapper.find('[data-testid="billing-webhook-events-table"]');
    expect(table.text()).toContain('evt_123');
    expect(table.text()).toContain('customer.subscription.updated');
    expect(mockApi.get).toHaveBeenCalledTimes(1);

    await wrapper.find('[data-testid="billing-webhook-event-detail-evt_123"]').trigger('click');
    await flushPromises();

    expect(mockApi.get).toHaveBeenLastCalledWith(`${webhookUrl}/evt_123`, undefined);
    const detail = wrapper.find('[data-testid="billing-webhook-event-detail-content"]');
    expect(detail.text()).toContain('Failed');
    expect(detail.text()).not.toContain('hidden');
    expect(wrapper.find('[data-testid="billing-webhook-events-retention"]').text()).toContain(
      'web.admin.billing.webhookEvents.retention'
    );
    expect(wrapper.text()).not.toMatch(/replay/i);
  });

  it('shows unresolved stored plan IDs and an explicit expired webhook correlation', async () => {
    mockApi.get.mockResolvedValue({ data: pendingList() });
    wrapper = mount(PendingFederatedSubscriptionsSection, { global: { plugins: [i18n] } });
    await flushPromises();

    const table = wrapper.find('[data-testid="billing-pending-federated-table"]');
    expect(table.text()).toContain('web.admin.billing.pendingFederated.unresolvedPlan');
    expect(table.text()).toContain('web.admin.billing.pendingFederated.webhook.expired');
    expect(wrapper.find('[data-testid="billing-pending-federated-webhook-expired"]').exists()).toBe(
      true
    );
    expect(wrapper.find('[data-testid="billing-pending-federated-capped"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="billing-pending-federated-retention"]').text()).toContain(
      'web.admin.billing.pendingFederated.correlationRetention'
    );
  });

  it('renders the no-correlation state without implying a processing outcome', async () => {
    mockApi.get.mockResolvedValue({ data: pendingList('no_correlation') });
    wrapper = mount(PendingFederatedSubscriptionsSection, { global: { plugins: [i18n] } });
    await flushPromises();

    expect(
      wrapper.find('[data-testid="billing-pending-federated-webhook-no_correlation"]').exists()
    ).toBe(true);
    expect(wrapper.text()).toContain('web.admin.billing.pendingFederated.webhook.no_correlation');
  });

  it('shows a retry control for a failed pending-subscription request', async () => {
    mockApi.get.mockRejectedValueOnce(new Error('Network Error'));
    wrapper = mount(PendingFederatedSubscriptionsSection, { global: { plugins: [i18n] } });
    await flushPromises();
    expect(wrapper.find('[data-testid="billing-pending-federated-error"]').exists()).toBe(true);

    mockApi.get.mockResolvedValueOnce({ data: pendingList('no_correlation') });
    await wrapper.find('[data-testid="billing-pending-federated-retry"]').trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-testid="billing-pending-federated-error"]').exists()).toBe(false);
  });
});
