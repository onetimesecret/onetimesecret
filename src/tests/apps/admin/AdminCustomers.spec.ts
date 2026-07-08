// src/tests/apps/admin/AdminCustomers.spec.ts

import { createPinia, setActivePinia } from 'pinia';
import { flushPromises, mount, VueWrapper } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const mockApi = {
  get: vi.fn(),
  post: vi.fn(),
  delete: vi.fn(),
};
vi.mock('@/shared/composables/useApi', () => ({ useApi: () => mockApi }));

const pushMock = vi.fn();
vi.mock('vue-router', () => ({
  useRouter: () => ({ push: pushMock }),
  useRoute: () => ({ params: {} }),
}));

// Deterministic, bootstrap-free date rendering.
vi.mock('@/utils/format', () => ({
  formatDisplayDateTime: (d: Date) => `DT:${d.toISOString()}`,
}));

vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="o-icon" :data-name="name" />',
    props: ['collection', 'name', 'class', 'size', 'aria-label'],
  },
}));

import AdminCustomers from '@/apps/admin/views/AdminCustomers.vue';
import { createTestI18n } from '@tests/setup';

const i18n = createTestI18n();

function usersPayload(
  overrides: {
    page?: number;
    per_page?: number;
    role?: string | null;
    suspended?: boolean;
  } = {}
) {
  return {
    shrimp: '',
    record: {},
    details: {
      users: [
        {
          user_id: 'ur_alice',
          extid: 'ur_alice',
          email: 'alice@example.com',
          role: 'customer',
          verified: true,
          suspended: overrides.suspended ?? false,
          created: 1700000000,
          last_login: 1700000100,
          planid: 'basic',
          secrets_count: 3,
          secrets_created: 5,
          secrets_shared: 2,
        },
      ],
      pagination: {
        page: overrides.page ?? 1,
        per_page: overrides.per_page ?? 50,
        total_count: 1,
        total_pages: 1,
        role_filter: overrides.role ?? null,
      },
    },
  };
}

describe('AdminCustomers (list view — ticket #22)', () => {
  let wrapper: VueWrapper;
  let pinia: ReturnType<typeof createPinia>;

  beforeEach(() => {
    pinia = createPinia();
    setActivePinia(pinia);
    vi.clearAllMocks();
  });
  afterEach(() => wrapper?.unmount());

  const mountView = () => mount(AdminCustomers, { global: { plugins: [pinia, i18n] } });

  it('fetches the first page on mount and renders a row per customer', async () => {
    mockApi.get.mockResolvedValue({ data: usersPayload() });
    wrapper = mountView();
    await flushPromises();

    expect(mockApi.get).toHaveBeenCalledWith('/api/colonel/users', {
      params: { page: 1, per_page: 50 },
    });
    const table = wrapper.find('[data-testid="customers-table"]');
    expect(table.exists()).toBe(true);
    expect(table.text()).toContain('alice@example.com');
    // Non-sortable columns: header buttons should NOT be rendered (fixed order).
    expect(table.findAll('thead th button')).toHaveLength(0);
  });

  it('forwards the role filter to the server on filter-change', async () => {
    mockApi.get.mockResolvedValue({ data: usersPayload() });
    wrapper = mountView();
    await flushPromises();

    await wrapper.find('#kit-filter-role').setValue('admin');
    await flushPromises();

    expect(mockApi.get).toHaveBeenLastCalledWith('/api/colonel/users', {
      params: { page: 1, per_page: 50, role: 'admin' },
    });
  });

  it('debounces the email search box into a single filtered fetch', async () => {
    vi.useFakeTimers();
    try {
      mockApi.get.mockResolvedValue({ data: usersPayload() });
      wrapper = mountView();
      await flushPromises();
      const before = mockApi.get.mock.calls.length;

      await wrapper
        .find('[data-testid="customers-filterbar"] input[type="search"]')
        .setValue('alice');
      // Debounced — no request yet.
      expect(mockApi.get.mock.calls.length).toBe(before);

      vi.advanceTimersByTime(300);
      await flushPromises();

      expect(mockApi.get.mock.calls.length).toBe(before + 1);
      expect(mockApi.get).toHaveBeenLastCalledWith('/api/colonel/users', {
        params: { page: 1, per_page: 50, search: 'alice' },
      });
    } finally {
      vi.runOnlyPendingTimers();
      vi.useRealTimers();
    }
  });

  it('shows a SUSPENDED badge on suspended rows only', async () => {
    mockApi.get.mockResolvedValue({ data: usersPayload({ suspended: true }) });
    wrapper = mountView();
    await flushPromises();
    expect(wrapper.find('[data-testid="suspended-badge"]').exists()).toBe(true);

    wrapper.unmount();
    setActivePinia((pinia = createPinia()));
    mockApi.get.mockResolvedValue({ data: usersPayload() });
    wrapper = mountView();
    await flushPromises();
    expect(wrapper.find('[data-testid="suspended-badge"]').exists()).toBe(false);
  });

  it('routes to the detail page (by public id) on row click', async () => {
    mockApi.get.mockResolvedValue({ data: usersPayload() });
    wrapper = mountView();
    await flushPromises();

    await wrapper.find('[data-testid="customers-table"] tbody tr').trigger('click');

    expect(pushMock).toHaveBeenCalledWith({
      name: 'AdminCustomerDetail',
      params: { id: 'ur_alice' },
    });
  });

  it('renders the pagination control when the server returns pagination', async () => {
    mockApi.get.mockResolvedValue({ data: usersPayload() });
    wrapper = mountView();
    await flushPromises();

    // KitPagination shows the range summary string.
    expect(wrapper.text()).toContain('web.colonel.pagination.showing');
  });

  it('shows the error banner + retry on a network failure', async () => {
    mockApi.get.mockRejectedValue(new Error('Network Error'));
    wrapper = mountView();
    await flushPromises();

    const banner = wrapper.find('[data-testid="customers-error"]');
    expect(banner.exists()).toBe(true);

    // Retry re-issues the request.
    mockApi.get.mockResolvedValueOnce({ data: usersPayload() });
    await banner.find('button').trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-testid="customers-error"]').exists()).toBe(false);
  });
});
