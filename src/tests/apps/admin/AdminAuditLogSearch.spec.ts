// src/tests/apps/admin/AdminAuditLogSearch.spec.ts

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

const actorInput = (w: VueWrapper) => w.find('[data-testid="audit-actor-input"]');
const actorForm = (w: VueWrapper) => w.find('[data-testid="audit-actor-form"]');
const searchButton = (w: VueWrapper) => w.find('[data-testid="audit-actor-search"]');

/**
 * The audit `actor` filter is MANUAL by operator request: the endpoint's
 * filtered path loads up to 10k events into Ruby per request, so the old
 * debounced as-you-type box turned every typing pause into a full-set scan.
 * These specs pin the "typing is inert, submitting searches" contract.
 */
describe('AdminAuditLog actor search (manual submit, no debounce)', () => {
  let wrapper: VueWrapper;
  let pinia: ReturnType<typeof createPinia>;

  beforeEach(() => {
    pinia = createPinia();
    setActivePinia(pinia);
    vi.clearAllMocks();
    vi.useFakeTimers();
    mockApi.get.mockResolvedValue({ data: auditPayload() });
  });
  afterEach(() => {
    vi.runOnlyPendingTimers();
    vi.useRealTimers();
    wrapper?.unmount();
  });

  it('does not fetch while the operator types — not even after any debounce window', async () => {
    wrapper = mountView(pinia);
    await flushPromises();
    const before = listGetCount();

    await actorInput(wrapper).setValue('ur_col');
    await actorInput(wrapper).setValue('ur_colonel1');
    expect(listGetCount()).toBe(before);

    // Nothing is scheduled: advancing well past the old 300ms debounce is inert.
    vi.advanceTimersByTime(5000);
    await flushPromises();
    expect(listGetCount()).toBe(before);
  });

  it('flags the typed-but-unsubmitted state so stale rows are not read as results', async () => {
    wrapper = mountView(pinia);
    await flushPromises();

    expect(wrapper.find('[data-testid="audit-search-pending"]').exists()).toBe(false);

    await actorInput(wrapper).setValue('ur_colonel1');
    expect(wrapper.find('[data-testid="audit-search-pending"]').exists()).toBe(true);

    await actorForm(wrapper).trigger('submit');
    await flushPromises();
    expect(wrapper.find('[data-testid="audit-search-pending"]').exists()).toBe(false);
  });

  it('runs the search on Enter in the actor box', async () => {
    wrapper = mountView(pinia);
    await flushPromises();
    const before = listGetCount();

    await actorInput(wrapper).setValue('ur_colonel1');
    await actorInput(wrapper).trigger('keydown.enter');
    await flushPromises();

    expect(listGetCount()).toBe(before + 1);
    expect(mockApi.get).toHaveBeenLastCalledWith(LIST_URL, {
      params: { page: 1, per_page: 50, actor: 'ur_colonel1' },
    });
  });

  it('runs the same search from the Search button (mouse/keyboard parity)', async () => {
    wrapper = mountView(pinia);
    await flushPromises();
    const before = listGetCount();

    await actorInput(wrapper).setValue('ur_colonel1');
    expect(searchButton(wrapper).exists()).toBe(true);
    await actorForm(wrapper).trigger('submit');
    await flushPromises();

    expect(listGetCount()).toBe(before + 1);
    expect(mockApi.get).toHaveBeenLastCalledWith(LIST_URL, {
      params: { page: 1, per_page: 50, actor: 'ur_colonel1' },
    });
  });

  it('submits exactly once per Enter press (no debounce echo behind it)', async () => {
    wrapper = mountView(pinia);
    await flushPromises();
    const before = listGetCount();

    await actorInput(wrapper).setValue('ur_colonel1');
    await actorInput(wrapper).trigger('keydown.enter');
    await flushPromises();
    vi.advanceTimersByTime(5000);
    await flushPromises();

    expect(listGetCount()).toBe(before + 1);
  });

  it('trims the submitted term and keeps the box in sync with what was applied', async () => {
    wrapper = mountView(pinia);
    await flushPromises();

    await actorInput(wrapper).setValue('  ur_colonel1  ');
    await actorForm(wrapper).trigger('submit');
    await flushPromises();

    expect(mockApi.get).toHaveBeenLastCalledWith(LIST_URL, {
      params: { page: 1, per_page: 50, actor: 'ur_colonel1' },
    });
    expect((actorInput(wrapper).element as HTMLInputElement).value).toBe('ur_colonel1');
    expect(wrapper.find('[data-testid="audit-search-pending"]').exists()).toBe(false);
  });

  it('submitting an emptied box returns to the unfiltered list', async () => {
    wrapper = mountView(pinia);
    await flushPromises();

    await actorInput(wrapper).setValue('ur_colonel1');
    await actorForm(wrapper).trigger('submit');
    await flushPromises();

    await actorInput(wrapper).setValue('');
    await actorForm(wrapper).trigger('submit');
    await flushPromises();

    expect(mockApi.get).toHaveBeenLastCalledWith(LIST_URL, {
      params: { page: 1, per_page: 50 },
    });
  });

  it('clear resets the applied actor search and refetches unfiltered', async () => {
    wrapper = mountView(pinia);
    await flushPromises();

    await actorInput(wrapper).setValue('ur_colonel1');
    await actorForm(wrapper).trigger('submit');
    await flushPromises();
    expect(mockApi.get).toHaveBeenLastCalledWith(LIST_URL, {
      params: { page: 1, per_page: 50, actor: 'ur_colonel1' },
    });

    const before = listGetCount();
    await wrapper
      .find('[data-testid="audit-filterbar"]')
      .findAll('button')
      .at(-1)!
      .trigger('click');
    await flushPromises();

    expect(listGetCount()).toBe(before + 1);
    expect(mockApi.get).toHaveBeenLastCalledWith(LIST_URL, {
      params: { page: 1, per_page: 50 },
    });
    expect((actorInput(wrapper).element as HTMLInputElement).value).toBe('');

    // And no deferred work fires behind the clear.
    vi.advanceTimersByTime(5000);
    await flushPromises();
    expect(listGetCount()).toBe(before + 1);
  });

  it('keeps the action category select immediate, and carries the applied actor with it', async () => {
    wrapper = mountView(pinia);
    await flushPromises();

    await wrapper.find('#kit-filter-verb').setValue('customer');
    await flushPromises();
    expect(mockApi.get).toHaveBeenLastCalledWith(LIST_URL, {
      params: { page: 1, per_page: 50, verb: 'customer' },
    });

    await actorInput(wrapper).setValue('ur_colonel1');
    await actorForm(wrapper).trigger('submit');
    await flushPromises();

    expect(mockApi.get).toHaveBeenLastCalledWith(LIST_URL, {
      params: { page: 1, per_page: 50, actor: 'ur_colonel1', verb: 'customer' },
    });
  });

  it('does not carry an unsubmitted actor term into a category change', async () => {
    wrapper = mountView(pinia);
    await flushPromises();

    await actorInput(wrapper).setValue('ur_colonel1');
    await wrapper.find('#kit-filter-verb').setValue('domain');
    await flushPromises();

    expect(mockApi.get).toHaveBeenLastCalledWith(LIST_URL, {
      params: { page: 1, per_page: 50, verb: 'domain' },
    });
  });

  it('leaves no pending timer behind on unmount', async () => {
    wrapper = mountView(pinia);
    await flushPromises();

    await actorInput(wrapper).setValue('ur_colonel1');
    wrapper.unmount();

    const after = listGetCount();
    vi.advanceTimersByTime(5000);
    await flushPromises();
    expect(listGetCount()).toBe(after);
  });
});
