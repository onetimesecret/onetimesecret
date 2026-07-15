// src/tests/apps/admin/AdminAuditLog.spec.ts

import { createPinia, setActivePinia } from 'pinia';
import { flushPromises, mount, VueWrapper } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const mockApi = {
  get: vi.fn(),
  post: vi.fn(),
  delete: vi.fn(),
};
vi.mock('@/shared/composables/useApi', () => ({ useApi: () => mockApi }));

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

import AdminAuditLog from '@/apps/admin/views/AdminAuditLog.vue';
import { createTestI18n } from '@tests/setup';

const i18n = createTestI18n();

const LIST_URL = '/api/colonel/audit';

function auditRow(overrides: Record<string, unknown> = {}) {
  return {
    id: 'evt_1',
    actor: 'ur_colonel1',
    verb: 'customer.set_role',
    target: 'ur_target1',
    result: 'success',
    detail: { from: 'customer', to: 'admin' },
    created: 1700000000,
    ...overrides,
  };
}

function auditPayload(rows = [auditRow()]) {
  return {
    shrimp: '',
    record: {},
    details: {
      events: rows,
      pagination: {
        page: 1,
        per_page: 50,
        total_count: rows.length,
        total_pages: 1,
        actor: null,
        verb: null,
      },
    },
  };
}

const mountView = (pinia: ReturnType<typeof createPinia>) =>
  mount(AdminAuditLog, { global: { plugins: [pinia, i18n] } });

const listGetCount = () => mockApi.get.mock.calls.filter((c) => c[0] === LIST_URL).length;

describe('AdminAuditLog (flight-recorder playback — observability lane)', () => {
  let wrapper: VueWrapper;
  let pinia: ReturnType<typeof createPinia>;

  beforeEach(() => {
    pinia = createPinia();
    setActivePinia(pinia);
    vi.clearAllMocks();
    vi.useFakeTimers();
  });
  afterEach(() => {
    vi.runOnlyPendingTimers();
    vi.useRealTimers();
    wrapper?.unmount();
  });

  it('fetches the first audit page on mount and renders a row per event', async () => {
    mockApi.get.mockResolvedValue({ data: auditPayload() });
    wrapper = mountView(pinia);
    await flushPromises();

    expect(mockApi.get).toHaveBeenCalledWith(LIST_URL, {
      params: { page: 1, per_page: 50 },
    });
    const table = wrapper.find('[data-testid="audit-table"]');
    expect(table.exists()).toBe(true);
    expect(table.text()).toContain('ur_colonel1');
    expect(table.text()).toContain('customer.set_role');
    expect(table.text()).toContain('ur_target1');
  });

  it('renders the timestamp as a formatted date and the detail as compact JSON', async () => {
    mockApi.get.mockResolvedValue({ data: auditPayload() });
    wrapper = mountView(pinia);
    await flushPromises();

    const table = wrapper.find('[data-testid="audit-table"]');
    // created: 1700000000 → Date via the Zod transform → mocked formatter.
    expect(table.text()).toContain('DT:2023-11-14T22:13:20.000Z');
    expect(table.text()).toContain('{"from":"customer","to":"admin"}');
  });

  it('renders a dash for events without detail', async () => {
    mockApi.get.mockResolvedValue({ data: auditPayload([auditRow({ detail: null })]) });
    wrapper = mountView(pinia);
    await flushPromises();

    expect(wrapper.find('[data-testid="audit-table"]').text()).toContain('—');
  });

  it('debounces the actor box into a single filtered fetch', async () => {
    mockApi.get.mockResolvedValue({ data: auditPayload() });
    wrapper = mountView(pinia);
    await flushPromises();
    const before = listGetCount();

    await wrapper.find('[data-testid="audit-filterbar"] input').setValue('ur_colonel1');
    // Debounced — no request yet.
    expect(listGetCount()).toBe(before);

    vi.advanceTimersByTime(300);
    await flushPromises();

    expect(listGetCount()).toBe(before + 1);
    expect(mockApi.get).toHaveBeenLastCalledWith(LIST_URL, {
      params: { page: 1, per_page: 50, actor: 'ur_colonel1' },
    });
  });

  it('sends the action category select as the verb filter immediately', async () => {
    mockApi.get.mockResolvedValue({ data: auditPayload() });
    wrapper = mountView(pinia);
    await flushPromises();

    await wrapper.find('#kit-filter-verb').setValue('customer');
    await flushPromises();

    expect(mockApi.get).toHaveBeenLastCalledWith(LIST_URL, {
      params: { page: 1, per_page: 50, verb: 'customer' },
    });
  });

  it('clear resets both filters and refetches unfiltered', async () => {
    mockApi.get.mockResolvedValue({ data: auditPayload() });
    wrapper = mountView(pinia);
    await flushPromises();

    await wrapper.find('#kit-filter-verb').setValue('customer');
    await flushPromises();

    await wrapper
      .find('[data-testid="audit-filterbar"]')
      .findAll('button')
      .at(-1)!
      .trigger('click');
    await flushPromises();

    expect(mockApi.get).toHaveBeenLastCalledWith(LIST_URL, {
      params: { page: 1, per_page: 50 },
    });
  });

  it('shows the error banner + retry on a network failure', async () => {
    mockApi.get.mockRejectedValue(new Error('Network Error'));
    wrapper = mountView(pinia);
    await flushPromises();

    const banner = wrapper.find('[data-testid="audit-error"]');
    expect(banner.exists()).toBe(true);

    mockApi.get.mockResolvedValueOnce({ data: auditPayload() });
    await banner.find('button').trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-testid="audit-error"]').exists()).toBe(false);
  });

  it('is read-only: renders no mutation affordances (no POST/DELETE ever fired)', async () => {
    mockApi.get.mockResolvedValue({ data: auditPayload() });
    wrapper = mountView(pinia);
    await flushPromises();

    expect(mockApi.post).not.toHaveBeenCalled();
    expect(mockApi.delete).not.toHaveBeenCalled();
  });
});
