// src/tests/apps/admin/ColonelAuditLog.spec.ts

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

import ColonelAuditLog from '@/apps/admin/views/ColonelAuditLog.vue';
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
    // Stream discriminator (#4335): which of the model's three capped trails
    // this row came from. Required by colonelAuditEventSchema.
    trail: 'events',
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
  mount(ColonelAuditLog, { global: { plugins: [pinia, i18n] } });

const listGetCount = () => mockApi.get.mock.calls.filter((c) => c[0] === LIST_URL).length;

describe('ColonelAuditLog (flight-recorder playback — observability lane)', () => {
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

  // The actor box is MANUAL search (the debounce was removed deliberately):
  // typing issues nothing, submitting the form issues exactly one fetch.
  // Full coverage lives in ColonelAuditLogSearch.spec.ts.
  it('searches the actor box on submit, not while typing', async () => {
    mockApi.get.mockResolvedValue({ data: auditPayload() });
    wrapper = mountView(pinia);
    await flushPromises();
    const before = listGetCount();

    await wrapper.find('[data-testid="audit-actor-input"]').setValue('ur_colonel1');
    // Manual search — nothing fires on input, and no timer is pending either.
    expect(listGetCount()).toBe(before);
    vi.advanceTimersByTime(1000);
    await flushPromises();
    expect(listGetCount()).toBe(before);

    await wrapper.find('[data-testid="audit-actor-form"]').trigger('submit');
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

  /**
   * The category select is the ONLY discovery surface for a verb family: a
   * prefix that is missing here is unreachable from the UI even though the
   * server would happily filter on it. `membership` was absent while
   * membership.add / .remove / .set_role / .entitlement.<action> were live.
   */
  it('offers every live verb prefix as an action category', async () => {
    mockApi.get.mockResolvedValue({ data: auditPayload() });
    wrapper = mountView(pinia);
    await flushPromises();

    // The leading `value=""` option is FilterBar's "All actions"; drop it.
    const values = wrapper
      .find('#kit-filter-verb')
      .findAll('option')
      .map((o) => (o.element as HTMLOptionElement).value)
      .filter((v) => v !== '');

    expect(values).toEqual([
      'customer',
      'session',
      'secret',
      'domain',
      'organization',
      'membership',
      'entitlement_preview',
      'banner',
      'queue',
      'email',
      'ratelimit',
      'ip',
      'colonel',
    ]);
    expect(values).toHaveLength(13);
  });

  it('sends a category prefix verbatim so it prefix-matches the whole family', async () => {
    mockApi.get.mockResolvedValue({ data: auditPayload() });
    wrapper = mountView(pinia);
    await flushPromises();

    // `membership` must reach membership.entitlement.<action>, which is built
    // by interpolation server-side and is therefore not a literal verb.
    await wrapper.find('#kit-filter-verb').setValue('membership');
    await flushPromises();

    expect(mockApi.get).toHaveBeenLastCalledWith(LIST_URL, {
      params: { page: 1, per_page: 50, verb: 'membership' },
    });
  });

  /**
   * usePaginatedFetch keeps `validationError` separate from `error` precisely so
   * a view can tell "the response arrived but broke the contract" from "the
   * request threw". Before this, the audit screen read only `error`, so a Zod
   * mismatch degraded the store to `[]` and the operator saw "No audit events
   * recorded yet" — a broken read contract wearing the costume of a quiet log.
   *
   * Latent by design: the live payload parses green, so the branch is forced
   * with a well-formed HTTP 200 whose `events` is not an array.
   */
  describe('contract mismatch (payload arrived, failed Zod)', () => {
    const brokenPayload = {
      shrimp: '',
      record: {},
      details: {
        events: 'not-an-array',
        pagination: { page: 1, per_page: 50, total_count: 0, total_pages: 0 },
      },
    };

    it('renders the contract-mismatch state and NOT the empty state', async () => {
      mockApi.get.mockResolvedValue({ data: brokenPayload });
      wrapper = mountView(pinia);
      await flushPromises();

      const mismatch = wrapper.find('[data-testid="audit-contract-error"]');
      expect(mismatch.exists()).toBe(true);
      expect(mismatch.attributes('role')).toBe('alert');
      expect(mismatch.text()).toContain('web.admin.audit.list.contractError');

      // The lie this bug told: no empty state, and no "no events" copy anywhere.
      expect(wrapper.find('[data-testid="audit-table-empty"]').exists()).toBe(false);
      expect(wrapper.find('[data-testid="audit-table"]').exists()).toBe(false);
      expect(wrapper.text()).not.toContain('web.admin.audit.list.empty');
    });

    it('is distinct from the network-error banner', async () => {
      mockApi.get.mockResolvedValue({ data: brokenPayload });
      wrapper = mountView(pinia);
      await flushPromises();

      // A contract mismatch never throws, so the network banner must stay away.
      expect(wrapper.find('[data-testid="audit-error"]').exists()).toBe(false);

      wrapper.unmount();
      mockApi.get.mockRejectedValue(new Error('Network Error'));
      wrapper = mountView(createPinia());
      await flushPromises();

      expect(wrapper.find('[data-testid="audit-error"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="audit-contract-error"]').exists()).toBe(false);
    });

    it('an empty-but-valid page still shows the ordinary empty state', async () => {
      mockApi.get.mockResolvedValue({ data: auditPayload([]) });
      wrapper = mountView(pinia);
      await flushPromises();

      expect(wrapper.find('[data-testid="audit-contract-error"]').exists()).toBe(false);
      expect(wrapper.find('[data-testid="audit-table-empty"]').exists()).toBe(true);
    });

    it('retry clears the mismatch once the payload parses again', async () => {
      mockApi.get.mockResolvedValue({ data: brokenPayload });
      wrapper = mountView(pinia);
      await flushPromises();

      const mismatch = wrapper.find('[data-testid="audit-contract-error"]');
      expect(mismatch.exists()).toBe(true);

      mockApi.get.mockResolvedValue({ data: auditPayload() });
      await mismatch.find('button').trigger('click');
      await flushPromises();

      expect(wrapper.find('[data-testid="audit-contract-error"]').exists()).toBe(false);
      expect(wrapper.find('[data-testid="audit-table"]').text()).toContain('customer.set_role');
    });
  });

  it('is read-only: renders no mutation affordances (no POST/DELETE ever fired)', async () => {
    mockApi.get.mockResolvedValue({ data: auditPayload() });
    wrapper = mountView(pinia);
    await flushPromises();

    expect(mockApi.post).not.toHaveBeenCalled();
    expect(mockApi.delete).not.toHaveBeenCalled();
  });

  // The export is a download link, not a fetch: the server streams CSV/NDJSON
  // with a Content-Disposition header. What the screen owes the operator is a
  // link whose filters match the table they are reading.
  describe('export links', () => {
    it('links to the export endpoint in both serialisations', async () => {
      mockApi.get.mockResolvedValue({ data: auditPayload() });
      wrapper = mountView(pinia);
      await flushPromises();

      expect(wrapper.find('[data-testid="audit-export-csv"]').attributes('href')).toBe(
        '/api/colonel/audit/export?format=csv'
      );
      expect(wrapper.find('[data-testid="audit-export-ndjson"]').attributes('href')).toBe(
        '/api/colonel/audit/export?format=ndjson'
      );
    });

    it('carries the APPLIED filters, not the half-typed actor box', async () => {
      mockApi.get.mockResolvedValue({ data: auditPayload() });
      wrapper = mountView(pinia);
      await flushPromises();

      // Typed but not submitted: the table has not moved, so neither has the link.
      await wrapper.find('[data-testid="audit-actor-input"]').setValue('colonel@example.com');
      expect(wrapper.find('[data-testid="audit-export-csv"]').attributes('href')).toBe(
        '/api/colonel/audit/export?format=csv'
      );

      await wrapper.find('[data-testid="audit-actor-form"]').trigger('submit');
      await flushPromises();

      expect(wrapper.find('[data-testid="audit-export-csv"]').attributes('href')).toBe(
        '/api/colonel/audit/export?format=csv&actor=colonel%40example.com'
      );
    });

    it('does not fetch anything of its own', async () => {
      mockApi.get.mockResolvedValue({ data: auditPayload() });
      wrapper = mountView(pinia);
      await flushPromises();
      const callsAfterMount = mockApi.get.mock.calls.length;

      await wrapper.find('[data-testid="audit-export-csv"]').trigger('click');

      expect(mockApi.get.mock.calls.length).toBe(callsAfterMount);
    });
  });
});
