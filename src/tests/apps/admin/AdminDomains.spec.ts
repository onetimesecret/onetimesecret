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
