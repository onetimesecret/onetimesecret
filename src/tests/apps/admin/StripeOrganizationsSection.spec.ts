// src/tests/apps/admin/StripeOrganizationsSection.spec.ts

import { AxiosError } from 'axios';
import { createPinia, setActivePinia } from 'pinia';
import { flushPromises, mount, RouterLinkStub, VueWrapper } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

/** Build a real AxiosError so the store can read `response.status`. */
function axiosError(status: number, data: unknown, message = 'Request failed'): AxiosError {
  const err = new AxiosError(message);
  err.response = { status, data, statusText: '', headers: {}, config: {} as never };
  return err;
}

const mockApi = { get: vi.fn(), post: vi.fn(), delete: vi.fn() };
vi.mock('@/shared/composables/useApi', () => ({ useApi: () => mockApi }));

vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="o-icon" :data-name="name" />',
    props: ['collection', 'name', 'class', 'size', 'aria-label'],
  },
}));

import { FilterBar } from '@/apps/admin/components/kit';
import StripeOrganizationsSection from '@/apps/admin/components/billing/StripeOrganizationsSection.vue';
import { createTestI18n } from '@tests/setup';

const i18n = createTestI18n();

const LIST_URL = '/api/colonel/billing/stripe-organizations';

function org(overrides: Record<string, unknown> = {}) {
  return {
    org_id: 'org_internal_1',
    extid: 'og_acme',
    display_name: 'Acme Inc',
    owner_email: 'owner@acme.example',
    billing_email: 'billing@acme.example',
    planid: 'identity_plus_v1',
    stripe_customer_id: 'cus_ACME001',
    stripe_subscription_id: 'sub_ACME001',
    subscription_status: 'active',
    subscription_period_end: '2026-08-01',
    sync_status: 'synced',
    ...overrides,
  };
}

function listPayload(overrides: Record<string, unknown> = {}) {
  return {
    shrimp: '',
    record: {},
    details: {
      organizations: [
        org(),
        org({
          extid: 'og_globex',
          display_name: 'Globex',
          owner_email: 'ops@globex.example',
          stripe_customer_id: 'cus_GLOBEX9',
          subscription_status: 'past_due',
          planid: null,
        }),
      ],
      pagination: { page: 1, per_page: 50, total_count: 2, total_pages: 1 },
      filters: { search: null },
      ...overrides,
    },
  };
}

// CopyButton drives the real clipboard API; stub it and assert on the payload.
const copyButtonStub = {
  name: 'CopyButton',
  props: ['text', 'tooltip', 'testid', 'interval'],
  template: '<button :data-testid="testid" :data-text="text" type="button" />',
};

const mountSection = () =>
  mount(StripeOrganizationsSection, {
    global: {
      plugins: [i18n],
      stubs: { RouterLink: RouterLinkStub, CopyButton: copyButtonStub },
    },
  });

describe('StripeOrganizationsSection (billing → Stripe customers roster)', () => {
  let wrapper: VueWrapper;

  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
  });
  afterEach(() => wrapper?.unmount());

  it('fetches the first page on mount', async () => {
    mockApi.get.mockResolvedValue({ data: listPayload() });
    wrapper = mountSection();
    await flushPromises();

    expect(mockApi.get).toHaveBeenCalledWith(LIST_URL, {
      params: { page: 1, per_page: 50 },
    });
  });

  it('renders one row per Stripe-linked organization', async () => {
    mockApi.get.mockResolvedValue({ data: listPayload() });
    wrapper = mountSection();
    await flushPromises();

    const table = wrapper.find('[data-testid="billing-stripe-orgs-table"]');
    expect(table.exists()).toBe(true);
    expect(table.text()).toContain('Acme Inc');
    expect(table.text()).toContain('cus_ACME001');
    expect(table.text()).toContain('Globex');
    expect(table.text()).toContain('cus_GLOBEX9');
    expect(wrapper.find('[data-testid="billing-stripe-orgs-count"]').text()).toContain('2');
  });

  it('links each row to the owning organization detail page', async () => {
    mockApi.get.mockResolvedValue({ data: listPayload() });
    wrapper = mountSection();
    await flushPromises();

    expect(wrapper.find('[data-testid="stripe-org-link-og_acme"]').exists()).toBe(true);

    const targets = wrapper.findAllComponents(RouterLinkStub).map((l) => l.props('to'));
    expect(targets).toContainEqual({
      name: 'AdminOrganizationDetail',
      params: { id: 'og_acme' },
    });
    expect(targets).toContainEqual({
      name: 'AdminOrganizationDetail',
      params: { id: 'og_globex' },
    });
  });

  it('offers the Stripe customer id in a copyable form', async () => {
    mockApi.get.mockResolvedValue({ data: listPayload() });
    wrapper = mountSection();
    await flushPromises();

    const copy = wrapper.find('[data-testid="stripe-org-copy-og_acme"]');
    expect(copy.exists()).toBe(true);
    expect(copy.attributes('data-text')).toBe('cus_ACME001');
  });

  it('debounces the search box into a single filtered fetch', async () => {
    vi.useFakeTimers();
    try {
      mockApi.get.mockResolvedValue({ data: listPayload() });
      wrapper = mountSection();
      await flushPromises();
      const before = mockApi.get.mock.calls.length;

      await wrapper
        .find('[data-testid="billing-stripe-orgs-filterbar"] input[type="search"]')
        .setValue('cus_ACME');
      expect(mockApi.get.mock.calls.length).toBe(before);

      vi.advanceTimersByTime(300);
      await flushPromises();

      expect(mockApi.get.mock.calls.length).toBe(before + 1);
      expect(mockApi.get).toHaveBeenLastCalledWith(LIST_URL, {
        params: { page: 1, per_page: 50, search: 'cus_ACME' },
      });
    } finally {
      vi.runOnlyPendingTimers();
      vi.useRealTimers();
    }
  });

  it('issues exactly one fetch when clearing the search (no debounce double-fetch)', async () => {
    vi.useFakeTimers();
    try {
      mockApi.get.mockResolvedValue({ data: listPayload() });
      wrapper = mountSection();
      await flushPromises();

      await wrapper
        .find('[data-testid="billing-stripe-orgs-filterbar"] input[type="search"]')
        .setValue('cus_ACME');
      vi.advanceTimersByTime(300);
      await flushPromises();

      const before = mockApi.get.mock.calls.length;

      wrapper.findComponent(FilterBar).vm.$emit('clear');
      vi.advanceTimersByTime(300);
      await flushPromises();

      expect(mockApi.get.mock.calls.length).toBe(before + 1);
      expect(mockApi.get).toHaveBeenLastCalledWith(LIST_URL, {
        params: { page: 1, per_page: 50 },
      });
    } finally {
      vi.runOnlyPendingTimers();
      vi.useRealTimers();
    }
  });

  it('surfaces the bounded-scan caveat so the count is not read as exact', async () => {
    const payload = listPayload();
    payload.details.pagination = {
      page: 1,
      per_page: 50,
      total_count: 5000,
      total_pages: 100,
      capped: true,
      stale_count: 2,
    } as never;
    mockApi.get.mockResolvedValue({ data: payload });
    wrapper = mountSection();
    await flushPromises();

    const caveat = wrapper.find('[data-testid="billing-stripe-orgs-caveat"]');
    expect(caveat.exists()).toBe(true);
    expect(caveat.text()).toContain('web.admin.billing.stripeOrgs.capped');
    expect(caveat.text()).toContain('web.admin.billing.stripeOrgs.stale');
  });

  it('omits the caveat on an unbounded page', async () => {
    mockApi.get.mockResolvedValue({ data: listPayload() });
    wrapper = mountSection();
    await flushPromises();

    expect(wrapper.find('[data-testid="billing-stripe-orgs-caveat"]').exists()).toBe(false);
  });

  it('shows an informational notice (not an error) when the endpoint 404s', async () => {
    mockApi.get.mockRejectedValue(axiosError(404, { error: 'Not Found' }));
    wrapper = mountSection();
    await flushPromises();

    expect(wrapper.find('[data-testid="billing-stripe-orgs-unavailable"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="billing-stripe-orgs-error"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="billing-stripe-orgs-table"]').exists()).toBe(false);
  });

  it('shows an error banner with retry on a network failure', async () => {
    mockApi.get.mockRejectedValue(new Error('Network Error'));
    wrapper = mountSection();
    await flushPromises();

    expect(wrapper.find('[data-testid="billing-stripe-orgs-error"]').exists()).toBe(true);

    mockApi.get.mockResolvedValue({ data: listPayload() });
    await wrapper.find('[data-testid="billing-stripe-orgs-retry"]').trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-testid="billing-stripe-orgs-error"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="billing-stripe-orgs-table"]').text()).toContain('Acme Inc');
  });

  it('degrades to an empty table (no throw) when the payload fails the contract', async () => {
    mockApi.get.mockResolvedValue({ data: { shrimp: '', record: {}, details: { nope: true } } });
    wrapper = mountSection();
    await flushPromises();

    expect(wrapper.find('[data-testid="billing-stripe-orgs-error"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="billing-stripe-orgs-table-empty"]').exists()).toBe(true);
  });

  it('tolerates a sparse row shape (fields the backend has not filled in yet)', async () => {
    mockApi.get.mockResolvedValue({
      data: {
        shrimp: '',
        record: {},
        details: {
          organizations: [{ extid: 'og_minimal', stripe_customer_id: 'cus_MIN' }],
          pagination: { page: 1, per_page: 50, total_count: 1, total_pages: 1 },
        },
      },
    });
    wrapper = mountSection();
    await flushPromises();

    const table = wrapper.find('[data-testid="billing-stripe-orgs-table"]');
    expect(table.text()).toContain('cus_MIN');
    // No display_name/billing_email: the row falls back to the extid.
    expect(table.text()).toContain('og_minimal');
  });
});
