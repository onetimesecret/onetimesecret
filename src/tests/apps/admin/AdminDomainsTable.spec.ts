// src/tests/apps/admin/AdminDomainsTable.spec.ts
//
// Covers the DataTable rebuild of the domains list: the server-side search /
// status filters, the TLS/serving column, the row-click detail drawer and its
// escalation link. The verify flow and the attach-to-organization flow are
// covered by AdminDomains.spec.ts and are not repeated here.
//
// The filter assertions pin the REQUEST CONTRACT (`search` / `status` query
// params on GET /api/colonel/domains, applied server-side before pagination).

import { createPinia, setActivePinia } from 'pinia';
import { flushPromises, mount, RouterLinkStub, VueWrapper } from '@vue/test-utils';
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

const showMock = vi.fn();
vi.mock('@/shared/stores/notificationsStore', () => ({
  useNotificationsStore: () => ({ show: showMock }),
}));

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

// Render the drawer's HeadlessUI dialog synchronously and IN-PLACE (the real
// Dialog teleports its panel to <body>, escaping the mounted wrapper).
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

import AdminDomains from '@/apps/admin/views/AdminDomains.vue';
import { createTestI18n } from '@tests/setup';

const i18n = createTestI18n();

function domainRow(overrides: Record<string, unknown> = {}) {
  return {
    domain_id: 'cd1',
    extid: 'cd_abc123',
    display_domain: 'secrets.example.com',
    base_domain: 'example.com',
    subdomain: 'secrets',
    status: null,
    verified: false,
    resolving: false,
    verification_state: 'pending',
    ready: false,
    created: 1700000000,
    updated: 1700003600,
    org_id: 'org1',
    org_name: 'Acme',
    brand: { name: 'Acme', tagline: null, homepage_url: null },
    homepage_config: null,
    api_config: null,
    has_logo: false,
    has_icon: false,
    logo_url: null,
    icon_url: null,
    ...overrides,
  };
}

/** Two rows that differ in every filterable dimension. */
function twoRowPayload() {
  return {
    shrimp: '',
    record: {},
    details: {
      domains: [
        domainRow(),
        domainRow({
          domain_id: 'cd2',
          extid: 'cd_def456',
          display_domain: 'links.globex.com',
          base_domain: 'globex.com',
          subdomain: 'links',
          verified: true,
          resolving: true,
          verification_state: 'verified',
          ready: true,
          org_id: 'org2',
          org_name: 'Globex',
        }),
      ],
      pagination: { page: 1, per_page: 50, total_count: 2, total_pages: 1 },
    },
  };
}

const searchInput = (w: VueWrapper) => w.find('#kit-filter-search');
const stateSelect = (w: VueWrapper) => w.find('#kit-filter-state');
const rowCount = (w: VueWrapper) => w.findAll('tbody tr').length;

describe('AdminDomains — table, filters and drawer', () => {
  let wrapper: VueWrapper;
  let pinia: ReturnType<typeof createPinia>;

  const mountView = () =>
    mount(AdminDomains, {
      global: {
        plugins: [pinia, i18n],
        stubs: { RouterLink: RouterLinkStub },
      },
    });

  beforeEach(() => {
    pinia = createPinia();
    setActivePinia(pinia);
    vi.clearAllMocks();
    mockApi.get.mockResolvedValue({ data: twoRowPayload() });
  });
  afterEach(() => wrapper?.unmount());

  it('renders one table row per domain with the serving/TLS state', async () => {
    wrapper = mountView();
    await flushPromises();

    expect(rowCount(wrapper)).toBe(2);
    // `ready` is the server's own answer; we render it, never re-derive it.
    expect(wrapper.find('[data-testid="domain-tls-cd_def456"]').text()).toBe(
      'web.admin.domains.tls.serving'
    );
    expect(wrapper.find('[data-testid="domain-tls-cd_abc123"]').text()).toBe(
      'web.admin.domains.tls.none'
    );
  });

  it('debounces the search box into a single filtered request', async () => {
    vi.useFakeTimers();
    try {
      wrapper = mountView();
      await flushPromises();
      expect(mockApi.get).toHaveBeenCalledTimes(1);

      await searchInput(wrapper).setValue('glo');
      await searchInput(wrapper).setValue('globex');
      vi.advanceTimersByTime(300);
      await flushPromises();

      // One request for the pause, not one per keystroke, and page 1.
      expect(mockApi.get).toHaveBeenCalledTimes(2);
      expect(mockApi.get).toHaveBeenLastCalledWith('/api/colonel/domains', {
        params: { page: 1, per_page: 50, search: 'globex' },
      });
    } finally {
      vi.useRealTimers();
    }
  });

  it('sends the state filter as the server `status` param', async () => {
    wrapper = mountView();
    await flushPromises();

    await stateSelect(wrapper).setValue('verified');
    await flushPromises();

    expect(mockApi.get).toHaveBeenLastCalledWith('/api/colonel/domains', {
      params: { page: 1, per_page: 50, status: 'verified' },
    });
  });

  it('clearing drops every filter param in one request', async () => {
    wrapper = mountView();
    await flushPromises();

    await stateSelect(wrapper).setValue('verified');
    await flushPromises();

    await wrapper.find('[data-testid="domains-filterbar"] button').trigger('click');
    await flushPromises();

    expect(mockApi.get).toHaveBeenLastCalledWith('/api/colonel/domains', {
      params: { page: 1, per_page: 50 },
    });
  });

  it('shows the filtered-empty message when the filtered page comes back empty', async () => {
    wrapper = mountView();
    await flushPromises();

    mockApi.get.mockResolvedValue({
      data: {
        shrimp: '',
        record: {},
        details: {
          domains: [],
          pagination: { page: 1, per_page: 50, total_count: 0, total_pages: 0 },
        },
      },
    });
    await stateSelect(wrapper).setValue('verified');
    await flushPromises();

    const empty = wrapper.find('[data-testid="domains-empty"]');
    expect(empty.exists()).toBe(true);
    expect(empty.text()).toContain('web.admin.domains.list.emptyFilter');
  });

  it('opens the read-only drawer on row click and escalates to the detail page', async () => {
    wrapper = mountView();
    await flushPromises();

    await wrapper.find('[data-testid="domain-row-cd_abc123"]').trigger('click');
    await flushPromises();

    const drawer = wrapper.find('[data-testid="domains-drawer"]');
    expect(drawer.exists()).toBe(true);
    expect(drawer.text()).toContain('Acme');
    expect(wrapper.find('[data-testid="domain-field-publicId"]').text()).toContain('cd_abc123');

    // The drawer renders from the row already in hand — no second fetch.
    expect(mockApi.get).toHaveBeenCalledTimes(1);

    const fullPage = wrapper.findComponent('[data-testid="domain-open-full-page"]');
    expect(fullPage.exists()).toBe(true);
    expect(fullPage.props('to')).toEqual({
      name: 'AdminDomainDetail',
      params: { id: 'cd_abc123' },
    });
  });

  it('does not open the drawer when a row action is clicked', async () => {
    wrapper = mountView();
    await flushPromises();

    await wrapper.find('[data-testid="domain-verify-cd_abc123"]').trigger('click');
    await flushPromises();

    // The verify confirm dialog opened; the drawer stayed closed.
    expect(wrapper.find('[data-testid="admin-confirm-dialog"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="domains-drawer"]').exists()).toBe(false);
  });
});
