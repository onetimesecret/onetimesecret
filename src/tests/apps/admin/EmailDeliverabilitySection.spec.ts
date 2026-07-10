// src/tests/apps/admin/EmailDeliverabilitySection.spec.ts

import { AxiosError } from 'axios';
import { createPinia, setActivePinia } from 'pinia';
import { flushPromises, mount, VueWrapper } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

/** Build a real AxiosError so the shared classifier extracts `data.error`. */
function axiosError(status: number, data: unknown, message = 'Request failed'): AxiosError {
  const err = new AxiosError(message);
  err.response = { status, data, statusText: '', headers: {}, config: {} as never };
  return err;
}

const mockApi = {
  get: vi.fn(),
  post: vi.fn(),
  delete: vi.fn(),
};
vi.mock('@/shared/composables/useApi', () => ({ useApi: () => mockApi }));

const showMock = vi.fn();
vi.mock('@/shared/stores/notificationsStore', () => ({
  useNotificationsStore: () => ({ show: showMock }),
}));

vi.mock('@/utils/format', () => ({
  formatDisplayDateTime: vi.fn(() => 'formatted-date'),
}));

vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="o-icon" :data-name="name" />',
    props: ['collection', 'name', 'class', 'size', 'aria-label'],
  },
}));

// Render the HeadlessUI dialog markup synchronously (mirrors AdminEmailTools.spec).
vi.mock('@headlessui/vue', () => ({
  Dialog: {
    name: 'Dialog',
    template: '<div role="dialog" @close="$emit(\'close\')"><slot /></div>',
    props: ['class'],
    emits: ['close'],
  },
  DialogPanel: {
    name: 'DialogPanel',
    template: '<div class="dialog-panel" :data-testid="$attrs[\'data-testid\']"><slot /></div>',
    props: ['class'],
  },
  DialogTitle: { name: 'DialogTitle', template: '<h3><slot /></h3>', props: ['as', 'class'] },
  TransitionRoot: {
    name: 'TransitionRoot',
    template: '<div v-if="show"><slot /></div>',
    props: ['as', 'show'],
  },
  TransitionChild: { name: 'TransitionChild', template: '<div><slot /></div>', props: ['as'] },
}));

import EmailDeliverabilitySection from '@/apps/admin/components/EmailDeliverabilitySection.vue';
import { createTestI18n } from '@tests/setup';

const i18n = createTestI18n();

const SUMMARY_URL = '/api/colonel/email/deliverability';
const SUPPRESSIONS_URL = '/api/colonel/email/deliverability/suppressions';
const EVENTS_URL = '/api/colonel/email/deliverability/events';
const LOOKUP_URL = '/api/colonel/email/deliverability/lookup';
const MESSAGES_URL = '/api/colonel/email/deliverability/messages';

function summaryPayload(counts = {}) {
  return {
    shrimp: '',
    record: {},
    details: {
      window_days: 7,
      counts: {
        suppressed_total: 3,
        recent_bounces: 2,
        recent_complaints: 1,
        sends_skipped: 5,
        ...counts,
      },
    },
  };
}

function suppressionsPayload(
  rows = [
    { address: 'bad@example.com', reason: 'bounce', source: 'ses', created: 1751900000 },
  ],
  pagination = {}
) {
  return {
    shrimp: '',
    record: {},
    details: {
      suppressions: rows,
      pagination: {
        page: 1,
        per_page: 25,
        total_count: rows.length,
        total_pages: 1,
        ...pagination,
      },
    },
  };
}

function eventsPayload(
  rows = [
    {
      id: 'ev1',
      address: 'bad@example.com',
      kind: 'bounce',
      reason: '550 user unknown',
      source: 'smtp-sync',
      created: 1751900000,
    },
  ]
) {
  return {
    shrimp: '',
    record: {},
    details: {
      events: rows,
      pagination: { page: 1, per_page: 20, total_count: rows.length, total_pages: 1 },
    },
  };
}

function removePayload(address = 'bad@example.com') {
  return {
    shrimp: '',
    record: { address, removed: true },
    details: { message: 'Suppression removed successfully' },
  };
}

/**
 * Recent-sends (item 9) payload. Defaults to the Lettermint live-OK shape;
 * pass overrides for the SES capability=false or the degraded (available=false)
 * shapes.
 */
function recentSendsPayload(
  overrides: Partial<{
    provider: string;
    capability: boolean;
    available: boolean;
    error: string | null;
    messages: unknown[];
  }> = {}
) {
  const messages = overrides.messages ?? [
    {
      id: 'msg_abc123',
      status: 'hard_bounced',
      subject: 'Your secret link',
      to: ['recipient@example.com'],
      from_email: 'noreply@onetimesecret.com',
      created_at: 1720000000,
    },
  ];
  return {
    shrimp: '',
    record: {},
    details: {
      provider: 'lettermint',
      capability: true,
      available: true,
      error: null,
      ...overrides,
      messages,
      pagination: { page: 1, per_page: 30, total_count: null, total_pages: null, cursor: null },
    },
  };
}

/** Recipient-lookup (item 10) payload; found in both local + provider by default. */
function recipientLookupPayload(
  overrides: Partial<{
    address: string;
    provider: string;
    capability: boolean;
    available: boolean;
    error: string | null;
    local: unknown;
    provider_result: unknown;
  }> = {}
) {
  return {
    shrimp: '',
    record: {},
    details: {
      address: 'user@example.com',
      provider: 'lettermint',
      capability: true,
      available: true,
      error: null,
      local: { suppressed: true, reason: 'bounce', source: 'ses', created: 1720000000 },
      provider_result: { suppressed: true, reason: 'BOUNCE', last_update_time: 1719990000 },
      ...overrides,
    },
  };
}

/** Happy-path GET router for the four mount fetches (+ submit-only lookup). */
function primeGets({
  summary = summaryPayload(),
  suppressions = suppressionsPayload(),
  events = eventsPayload(),
  messages = recentSendsPayload(),
  lookup = recipientLookupPayload(),
}: {
  summary?: unknown;
  suppressions?: unknown;
  events?: unknown;
  messages?: unknown;
  lookup?: unknown;
} = {}) {
  mockApi.get.mockImplementation((url: string) => {
    if (url === SUMMARY_URL) return Promise.resolve({ data: summary });
    if (url === SUPPRESSIONS_URL) return Promise.resolve({ data: suppressions });
    if (url === EVENTS_URL) return Promise.resolve({ data: events });
    if (url === MESSAGES_URL) return Promise.resolve({ data: messages });
    if (url === LOOKUP_URL) return Promise.resolve({ data: lookup });
    return Promise.reject(new Error(`unexpected GET ${url}`));
  });
}

const mountSection = (pinia: ReturnType<typeof createPinia>) =>
  mount(EmailDeliverabilitySection, { global: { plugins: [pinia, i18n] } });

describe('EmailDeliverabilitySection (email deliverability)', () => {
  let wrapper: VueWrapper;
  let pinia: ReturnType<typeof createPinia>;

  beforeEach(() => {
    pinia = createPinia();
    setActivePinia(pinia);
    vi.clearAllMocks();
  });
  afterEach(() => wrapper?.unmount());

  // ---- Mount fetches + tiles -------------------------------------------------

  it('fetches summary, suppressions, and events on mount', async () => {
    primeGets();
    wrapper = mountSection(pinia);
    await flushPromises();

    expect(mockApi.get).toHaveBeenCalledWith(SUMMARY_URL, undefined);
    expect(mockApi.get).toHaveBeenCalledWith(SUPPRESSIONS_URL, {
      params: { page: 1, per_page: 25 },
    });
    expect(mockApi.get).toHaveBeenCalledWith(EVENTS_URL, { params: { page: 1, per_page: 20 } });
    // Track B item-9 send log is fetched on mount too (cursor-paginated slice).
    expect(mockApi.get).toHaveBeenCalledWith(MESSAGES_URL, { params: { page: 1, per_page: 30 } });
  });

  it('renders the four summary tiles from the counts payload', async () => {
    primeGets();
    wrapper = mountSection(pinia);
    await flushPromises();

    expect(wrapper.find('[data-testid="deliverability-stat-suppressed"]').text()).toContain('3');
    expect(wrapper.find('[data-testid="deliverability-stat-bounces"]').text()).toContain('2');
    expect(wrapper.find('[data-testid="deliverability-stat-complaints"]').text()).toContain('1');
    expect(wrapper.find('[data-testid="deliverability-stat-skipped"]').text()).toContain('5');
  });

  it('surfaces a summary failure as an alert with retry (tiles degrade, section stays up)', async () => {
    primeGets();
    mockApi.get.mockImplementation((url: string) => {
      if (url === SUMMARY_URL) return Promise.reject(axiosError(500, { error: 'boom' }));
      if (url === SUPPRESSIONS_URL) return Promise.resolve({ data: suppressionsPayload([]) });
      if (url === EVENTS_URL) return Promise.resolve({ data: eventsPayload([]) });
      if (url === MESSAGES_URL) return Promise.resolve({ data: recentSendsPayload() });
      return Promise.reject(new Error(`unexpected GET ${url}`));
    });
    wrapper = mountSection(pinia);
    await flushPromises();

    expect(wrapper.find('[data-testid="deliverability-summary-error"]').exists()).toBe(true);
    // The suppression/events blocks still render (their fetches succeeded).
    expect(wrapper.find('[data-testid="deliverability-search-input"]').exists()).toBe(true);
  });

  // ---- Suppression list -------------------------------------------------------

  it('renders suppression rows with reason badge and a remove action', async () => {
    primeGets();
    wrapper = mountSection(pinia);
    await flushPromises();

    const table = wrapper.find('[data-testid="deliverability-suppressions-table"]');
    expect(table.exists()).toBe(true);
    expect(table.text()).toContain('bad@example.com');
    expect(table.text()).toContain('bounce');
    expect(
      wrapper.find('[data-testid="deliverability-remove-bad@example.com"]').exists()
    ).toBe(true);
  });

  it('shows the pipe-your-feedback empty states when nothing is recorded yet', async () => {
    primeGets({ suppressions: suppressionsPayload([]), events: eventsPayload([]) });
    wrapper = mountSection(pinia);
    await flushPromises();

    expect(wrapper.text()).toContain('web.admin.emailtools.deliverability.suppressions.empty');
    expect(wrapper.text()).toContain('web.admin.emailtools.deliverability.events.empty');
  });

  it('submits an exact-address lookup as a server-side search param', async () => {
    primeGets();
    wrapper = mountSection(pinia);
    await flushPromises();

    primeGets({ suppressions: suppressionsPayload([], { total_count: 0 }) });
    await wrapper
      .find('[data-testid="deliverability-search-input"]')
      .setValue('  Missing@Example.com ');
    await wrapper.find('[data-testid="deliverability-search-submit"]').trigger('submit');
    await flushPromises();

    expect(mockApi.get).toHaveBeenCalledWith(SUPPRESSIONS_URL, {
      params: { page: 1, per_page: 25, search: 'Missing@Example.com' },
    });
    // Search-specific empty state (distinct from the no-data-yet state).
    expect(wrapper.text()).toContain(
      'web.admin.emailtools.deliverability.suppressions.emptySearch'
    );
  });

  // ---- Guarded remove ---------------------------------------------------------

  it('gates removal behind a confirm dialog and DELETEs the encoded address', async () => {
    primeGets();
    wrapper = mountSection(pinia);
    await flushPromises();

    await wrapper.find('[data-testid="deliverability-remove-bad@example.com"]').trigger('click');
    await flushPromises();

    // One-click confirm (the unban idiom): no typed-token input.
    expect(wrapper.find('#admin-confirm-input').exists()).toBe(false);
    expect(mockApi.delete).not.toHaveBeenCalled();

    mockApi.delete.mockResolvedValueOnce({ data: removePayload() });
    await wrapper.find('[role="dialog"] form').trigger('submit');
    await flushPromises();

    expect(mockApi.delete).toHaveBeenCalledWith(
      `${SUPPRESSIONS_URL}/${encodeURIComponent('bad@example.com')}`
    );
    expect(showMock).toHaveBeenCalledWith(
      'web.admin.emailtools.deliverability.suppressions.remove.success',
      'success'
    );
    // The list and the summary tiles both refresh after a removal.
    // Mount issues four reads (summary, suppressions, events, messages); the
    // removal refetches suppressions + summary → six total.
    expect(mockApi.get).toHaveBeenCalledTimes(6);
  });

  it('keeps a failed removal in the dialog and does not notify', async () => {
    primeGets();
    wrapper = mountSection(pinia);
    await flushPromises();

    await wrapper.find('[data-testid="deliverability-remove-bad@example.com"]').trigger('click');
    mockApi.delete.mockRejectedValueOnce(axiosError(404, { error: 'Address is not suppressed' }));
    await wrapper.find('[role="dialog"] form').trigger('submit');
    await flushPromises();

    expect(wrapper.find('[role="dialog"]').text()).toContain('Address is not suppressed');
    expect(showMock).not.toHaveBeenCalled();
  });

  // ---- Events feed --------------------------------------------------------------

  it('renders the recent events feed with kind badge, source, and reason', async () => {
    primeGets();
    wrapper = mountSection(pinia);
    await flushPromises();

    const table = wrapper.find('[data-testid="deliverability-events-table"]');
    expect(table.exists()).toBe(true);
    expect(table.text()).toContain('bad@example.com');
    expect(table.text()).toContain('web.admin.emailtools.deliverability.events.kinds.bounce');
    expect(table.text()).toContain('smtp-sync');
    expect(table.text()).toContain('550 user unknown');
  });

  it('shows the events load error without taking down the section', async () => {
    mockApi.get.mockImplementation((url: string) => {
      if (url === SUMMARY_URL) return Promise.resolve({ data: summaryPayload() });
      if (url === SUPPRESSIONS_URL) return Promise.resolve({ data: suppressionsPayload() });
      if (url === EVENTS_URL) return Promise.reject(axiosError(500, { error: 'boom' }));
      if (url === MESSAGES_URL) return Promise.resolve({ data: recentSendsPayload() });
      return Promise.reject(new Error(`unexpected GET ${url}`));
    });
    wrapper = mountSection(pinia);
    await flushPromises();

    expect(wrapper.find('[data-testid="deliverability-events-error"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="deliverability-suppressions-table"]').exists()).toBe(true);
  });

  // ---- Recipient lookup (item 10 — local + live provider) --------------------

  it('looks up an address and shows local + provider results side by side', async () => {
    primeGets();
    wrapper = mountSection(pinia);
    await flushPromises();

    await wrapper.find('[data-testid="deliverability-lookup-input"]').setValue('user@example.com');
    await wrapper.find('[data-testid="deliverability-lookup-submit"]').trigger('submit');
    await flushPromises();

    expect(mockApi.get).toHaveBeenCalledWith(LOOKUP_URL, {
      params: { address: 'user@example.com' },
    });
    const result = wrapper.find('[data-testid="deliverability-lookup-result"]');
    expect(result.exists()).toBe(true);
    expect(wrapper.find('[data-testid="deliverability-lookup-local-status"]').text()).toContain(
      'web.admin.emailtools.deliverability.lookup.suppressed'
    );
    expect(wrapper.find('[data-testid="deliverability-lookup-provider-result"]').exists()).toBe(
      true
    );
  });

  it('renders the provider-unavailable note on a lookup provider failure (local still shown)', async () => {
    primeGets({
      lookup: recipientLookupPayload({
        provider: 'ses',
        available: false,
        error: 'SES get_suppressed_destination failed',
        provider_result: null,
      }),
    });
    wrapper = mountSection(pinia);
    await flushPromises();

    await wrapper.find('[data-testid="deliverability-lookup-input"]').setValue('user@example.com');
    await wrapper.find('[data-testid="deliverability-lookup-submit"]').trigger('submit');
    await flushPromises();

    // The provider column shows the failure; the local column is still present.
    expect(wrapper.find('[data-testid="deliverability-lookup-provider-error"]').text()).toContain(
      'SES get_suppressed_destination failed'
    );
    expect(wrapper.find('[data-testid="deliverability-lookup-local-status"]').exists()).toBe(true);
  });

  // ---- Recent sends feed (item 9 — provider's OWN message API) ---------------

  it('renders the recent sends table with a status badge and recipient', async () => {
    primeGets();
    wrapper = mountSection(pinia);
    await flushPromises();

    const table = wrapper.find('[data-testid="deliverability-messages-table"]');
    expect(table.exists()).toBe(true);
    expect(table.text()).toContain('Your secret link');
    expect(table.text()).toContain('recipient@example.com');
    expect(table.text()).toContain('web.admin.emailtools.deliverability.messages.status.hard_bounced');
  });

  it('shows the not-supported empty-state when the transport has no send log (capability=false)', async () => {
    primeGets({
      messages: recentSendsPayload({
        provider: 'ses',
        capability: false,
        available: false,
        messages: [],
      }),
    });
    wrapper = mountSection(pinia);
    await flushPromises();

    expect(wrapper.find('[data-testid="deliverability-messages-unsupported"]').exists()).toBe(true);
    // No table is rendered when the capability is structurally absent.
    expect(wrapper.find('[data-testid="deliverability-messages-table"]').exists()).toBe(false);
  });

  it('shows the send-log error alert on a provider failure without taking down the section', async () => {
    mockApi.get.mockImplementation((url: string) => {
      if (url === SUMMARY_URL) return Promise.resolve({ data: summaryPayload() });
      if (url === SUPPRESSIONS_URL) return Promise.resolve({ data: suppressionsPayload() });
      if (url === EVENTS_URL) return Promise.resolve({ data: eventsPayload() });
      if (url === MESSAGES_URL) return Promise.reject(axiosError(500, { error: 'boom' }));
      return Promise.reject(new Error(`unexpected GET ${url}`));
    });
    wrapper = mountSection(pinia);
    await flushPromises();

    expect(wrapper.find('[data-testid="deliverability-messages-error"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="deliverability-suppressions-table"]').exists()).toBe(true);
  });
});
