// src/tests/apps/admin/AdminDomains.spec.ts

import { createPinia, setActivePinia } from 'pinia';
import { flushPromises, mount, VueWrapper } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

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

// Render the confirm dialog synchronously in jsdom (same shim the kit test uses).
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

function domainsPayload(row: Record<string, unknown> = {}) {
  return {
    shrimp: '',
    record: {},
    details: {
      domains: [domainRow(row)],
      pagination: { page: 1, per_page: 50, total_count: 1, total_pages: 1 },
    },
  };
}

function verifyAck(current_state = 'verified') {
  return {
    shrimp: '',
    record: {
      domain_id: 'cd1',
      extid: 'cd_abc123',
      display_domain: 'secrets.example.com',
      verification_state: current_state,
      verified: current_state === 'verified',
      resolving: current_state === 'verified' || current_state === 'resolving',
      ready: current_state === 'verified',
      updated: 1700009999,
    },
    details: {
      previous_state: 'pending',
      current_state,
      changed: true,
      dns_validated: current_state === 'verified',
      ssl_ready: current_state === 'verified',
      is_resolving: current_state !== 'pending',
      error: null,
      message: 'Domain verification completed',
    },
  };
}

describe('AdminDomains (card grid + verify — ticket #31)', () => {
  let wrapper: VueWrapper;
  let pinia: ReturnType<typeof createPinia>;

  beforeEach(() => {
    pinia = createPinia();
    setActivePinia(pinia);
    vi.clearAllMocks();
  });
  afterEach(() => wrapper?.unmount());

  const mountView = () => mount(AdminDomains, { global: { plugins: [pinia, i18n] } });

  it('fetches the first page on mount and renders a card per domain', async () => {
    mockApi.get.mockResolvedValue({ data: domainsPayload() });
    wrapper = mountView();
    await flushPromises();

    expect(mockApi.get).toHaveBeenCalledWith('/api/colonel/domains', {
      params: { page: 1, per_page: 50 },
    });
    const grid = wrapper.find('[data-testid="domains-grid"]');
    expect(grid.exists()).toBe(true);
    expect(grid.text()).toContain('secrets.example.com');
    expect(wrapper.find('[data-testid="domain-card-cd_abc123"]').exists()).toBe(true);
  });

  it('renders the empty state when there are no domains', async () => {
    mockApi.get.mockResolvedValue({
      data: { shrimp: '', record: {}, details: { domains: [], pagination: { page: 1, per_page: 50, total_count: 0, total_pages: 0 } } },
    });
    wrapper = mountView();
    await flushPromises();

    expect(wrapper.find('[data-testid="domains-empty"]').exists()).toBe(true);
  });

  it('verifies a domain: POSTs the verify endpoint, notifies the honest state, and refetches', async () => {
    mockApi.get.mockResolvedValue({ data: domainsPayload() });
    mockApi.post.mockResolvedValue({ data: verifyAck('verified') });
    wrapper = mountView();
    await flushPromises();
    expect(mockApi.get).toHaveBeenCalledTimes(1);

    // Open the confirm dialog for this domain.
    await wrapper.find('[data-testid="domain-verify-cd_abc123"]').trigger('click');
    await flushPromises();

    // One-click confirm (no typed token) — submit is enabled immediately.
    const submit = wrapper.find('[data-testid="admin-confirm-submit"]');
    expect(submit.exists()).toBe(true);
    await submit.trigger('submit');
    await flushPromises();

    expect(mockApi.post).toHaveBeenCalledWith('/api/colonel/domains/cd_abc123/verify');
    // Honest outcome surfaced as a success notification for a verified result.
    expect(showMock).toHaveBeenCalledTimes(1);
    expect(showMock.mock.calls[0][1]).toBe('success');
    // Re-fetches the current page so the badge reflects persisted state.
    expect(mockApi.get).toHaveBeenCalledTimes(2);
  });

  it('surfaces a non-verified outcome honestly (info notification, not faked success)', async () => {
    mockApi.get.mockResolvedValue({ data: domainsPayload() });
    mockApi.post.mockResolvedValue({ data: verifyAck('pending') });
    wrapper = mountView();
    await flushPromises();

    await wrapper.find('[data-testid="domain-verify-cd_abc123"]').trigger('click');
    await flushPromises();
    await wrapper.find('[data-testid="admin-confirm-submit"]').trigger('submit');
    await flushPromises();

    expect(showMock).toHaveBeenCalledTimes(1);
    expect(showMock.mock.calls[0][1]).toBe('info');
  });

  it('shows the error banner + retry on a network failure', async () => {
    mockApi.get.mockRejectedValue(new Error('Network Error'));
    wrapper = mountView();
    await flushPromises();

    const banner = wrapper.find('[data-testid="domains-error"]');
    expect(banner.exists()).toBe(true);

    mockApi.get.mockResolvedValueOnce({ data: domainsPayload() });
    await banner.find('button').trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-testid="domains-error"]').exists()).toBe(false);
  });
});

// ---- Attach-domain-to-organization flow ------------------------------------

function orgRow(overrides: Record<string, unknown> = {}) {
  return {
    org_id: 'org1',
    extid: 'org_acme',
    display_name: 'Acme',
    contact_email: 'a@acme.com',
    owner_id: 'cust1',
    owner_email: 'a@acme.com',
    member_count: 1,
    domain_count: 1,
    is_default: false,
    created: 1700000000,
    updated: 1700000000,
    planid: null,
    stripe_customer_id: null,
    stripe_subscription_id: null,
    subscription_status: null,
    subscription_period_end: null,
    billing_email: null,
    sync_status: 'synced',
    sync_status_reason: null,
    ...overrides,
  };
}

function orgsSearchPayload() {
  return {
    shrimp: '',
    record: {},
    details: {
      organizations: [orgRow()],
      pagination: { page: 1, per_page: 25, total_count: 1, total_pages: 1 },
      filters: { status: null, sync_status: null },
    },
  };
}

function orgDetailPayload(domains: Array<Record<string, unknown>> = []) {
  return {
    shrimp: '',
    record: {
      org_id: 'org1',
      extid: 'org_acme',
      display_name: 'Acme',
      description: null,
      is_default: false,
      archived: false,
      archived_at: null,
      archived_comment: null,
      contact_email: 'a@acme.com',
      owner_id: 'cust1',
      owner_email: 'a@acme.com',
      billing_email: null,
      member_count: 1,
      domain_count: domains.length,
      created: 1700000000,
      updated: 1700000000,
      planid: null,
      stripe_customer_id: null,
      stripe_subscription_id: null,
      subscription_status: null,
      subscription_period_end: null,
      billing_email_present: false,
      sync_status: 'synced',
      sync_status_reason: null,
    },
    details: {
      entitlements: {
        plan: [],
        grants: [],
        revokes: [],
        materialized: [],
        expected: [],
        materialized_flag: false,
        materialized_at: null,
        plan_stale: null,
        drift: { extra: [], missing: [], in_sync: true },
      },
      members: [],
      domains,
    },
  };
}

function rosterDomain(overrides: Record<string, unknown> = {}) {
  return {
    extid: 'cd_exist',
    domain_id: 'cde',
    display_domain: 'secrets.acme.com',
    base_domain: 'acme.com',
    status: null,
    verified: true,
    resolving: true,
    verification_state: 'verified',
    ready: true,
    created: 1700000000,
    ...overrides,
  };
}

/** `{ record, details: { cluster } }` for create + per-domain detail. */
function domainDetailPayload(extid = 'cd_new') {
  return {
    shrimp: '',
    record: {
      domain_id: 'cd9',
      extid,
      display_domain: 'links.acme.com',
      base_domain: 'acme.com',
      trd: 'links',
      is_apex: false,
      txt_validation_host: '_ots.links',
      txt_validation_value: 'ots=abc123',
      verification_state: 'pending',
      verified: false,
      resolving: false,
      ready: false,
      created: 1700000000,
      updated: 1700000000,
    },
    details: { cluster: { proxy_ip: '203.0.113.5', proxy_host: 'proxy.ots.example' } },
  };
}

/**
 * The selected org's live domain roster. Reset per test; a create appends to it
 * so a post-create org-detail refetch returns the new domain (as the backend
 * does), which is what reveals its DNS records in the panel.
 */
let liveRoster: Array<Record<string, unknown>> = [];

/** Route GET by URL across list / org-search / org-detail / domain-detail. */
function routeGet(url: string) {
  if (url === '/api/colonel/domains') return { data: domainsPayload() };
  if (url.startsWith('/api/colonel/domains/')) return { data: domainDetailPayload() };
  if (url === '/api/colonel/organizations') return { data: orgsSearchPayload() };
  if (url.startsWith('/api/colonel/organizations/')) {
    return { data: orgDetailPayload(liveRoster) };
  }
  return { data: { shrimp: '', record: {}, details: {} } };
}

describe('AdminDomains — attach domain to organization', () => {
  let wrapper: VueWrapper;
  let pinia: ReturnType<typeof createPinia>;

  beforeEach(() => {
    pinia = createPinia();
    setActivePinia(pinia);
    vi.clearAllMocks();
    liveRoster = [rosterDomain()];
    mockApi.get.mockImplementation((url: string) => Promise.resolve(routeGet(url)));
  });
  afterEach(() => wrapper?.unmount());

  const mountView = () => mount(AdminDomains, { global: { plugins: [pinia, i18n] } });

  async function openPickerAndSelect(w: VueWrapper) {
    await w.find('[data-testid="attach-domain-cta"]').trigger('click');
    await flushPromises();
    // Bypass the search debounce by submitting the picker form directly.
    const input = w.find('[data-testid="org-search-input"]');
    await input.setValue('acme');
    await w.find('[data-testid="org-search-input"]').element
      .closest('form')!
      .dispatchEvent(new Event('submit'));
    await flushPromises();
    await w.find('[data-testid="org-select-org_acme"]').trigger('click');
    await flushPromises();
  }

  it('CTA → search → select pins the org record panel and loads its domain roster', async () => {
    wrapper = mountView();
    await flushPromises();

    await openPickerAndSelect(wrapper);

    // The picker searched with the term as a query param.
    expect(mockApi.get).toHaveBeenCalledWith('/api/colonel/organizations', {
      params: { page: 1, per_page: 25, search: 'acme' },
    });
    // The chosen org is pinned into the working-record panel.
    const panel = wrapper.find('[data-testid="selected-org-panel"]');
    expect(panel.exists()).toBe(true);
    expect(panel.text()).toContain('org_acme');
    // Its existing domains loaded via the org-detail endpoint.
    expect(mockApi.get).toHaveBeenCalledWith('/api/colonel/organizations/org_acme');
    expect(wrapper.find('[data-testid="panel-domain-cd_exist"]').exists()).toBe(true);
  });

  it('clearing the panel unpins the organization', async () => {
    wrapper = mountView();
    await flushPromises();
    await openPickerAndSelect(wrapper);

    await wrapper.find('[data-testid="record-panel-clear"]').trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-testid="selected-org-panel"]').exists()).toBe(false);
  });

  it('add domain: POSTs create for the org, notifies, and reveals the DNS records', async () => {
    // Creating appends the new domain to the org's roster, mirroring the backend
    // so the post-create org-detail refetch returns it.
    mockApi.post.mockImplementation((url: string) => {
      if (url === '/api/colonel/domains') {
        liveRoster.push(
          rosterDomain({
            extid: 'cd_new',
            domain_id: 'cd9',
            display_domain: 'links.acme.com',
            verified: false,
            resolving: false,
            verification_state: 'pending',
            ready: false,
          })
        );
        return Promise.resolve({ data: domainDetailPayload('cd_new') });
      }
      return Promise.resolve({ data: verifyAck('verified') });
    });
    wrapper = mountView();
    await flushPromises();
    await openPickerAndSelect(wrapper);

    // Open the add-domain modal from the panel.
    await wrapper.find('[data-testid="panel-add-domain"]').trigger('click');
    await flushPromises();

    await wrapper.find('[data-testid="add-domain-input"]').setValue('links.acme.com');
    await wrapper.find('[data-testid="add-domain-submit"]').trigger('click');
    await flushPromises();

    // Create is POSTed for the selected org by its extid.
    expect(mockApi.post).toHaveBeenCalledWith('/api/colonel/domains', {
      org_id: 'org_acme',
      domain: 'links.acme.com',
    });
    // Success notification surfaced.
    expect(showMock).toHaveBeenCalled();
    expect(showMock.mock.calls.at(-1)?.[1]).toBe('success');
    // The new domain's DNS detail is fetched and rendered.
    expect(mockApi.get).toHaveBeenCalledWith('/api/colonel/domains/cd_new');
    expect(wrapper.find('[data-testid="dns-details"]').exists()).toBe(true);
  });

  it('re-verifies a panel domain against the colonel verify endpoint', async () => {
    mockApi.post.mockResolvedValue({ data: verifyAck('verified') });
    wrapper = mountView();
    await flushPromises();
    await openPickerAndSelect(wrapper);

    await wrapper.find('[data-testid="panel-domain-verify-cd_exist"]').trigger('click');
    await flushPromises();

    expect(mockApi.post).toHaveBeenCalledWith('/api/colonel/domains/cd_exist/verify');
    expect(showMock).toHaveBeenCalled();
  });
});
