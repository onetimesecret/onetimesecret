// src/tests/apps/admin/AdminOrganizations.spec.ts

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

// Row click navigates to the detail page (the drawer + investigate/entitlement
// workflows moved to AdminOrganizationDetail — see AdminOrganizationDetail.spec).
const pushMock = vi.fn();
vi.mock('vue-router', () => ({ useRouter: () => ({ push: pushMock }) }));

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

// The JsonViewer's copy affordance touches navigator.clipboard; stub it (same
// shim the kit's JsonViewer.spec uses) so the investigate panel mounts cleanly.
vi.mock('@/shared/components/ui/CopyButton.vue', () => ({
  default: { name: 'CopyButton', template: '<button class="copy-button" />', props: ['text', 'tooltip', 'testid'] },
}));

// Render the headlessui dialogs synchronously in jsdom.
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

import AdminOrganizations from '@/apps/admin/views/AdminOrganizations.vue';
import { createTestI18n } from '@tests/setup';

const i18n = createTestI18n();

function orgRow(overrides: Record<string, unknown> = {}) {
  return {
    org_id: 'org1',
    extid: 'on_abc123',
    display_name: 'Acme',
    contact_email: 'owner@acme.test',
    owner_id: 'cust1',
    owner_email: 'ow***@a***.test',
    member_count: 3,
    domain_count: 1,
    is_default: false,
    created: 1700000000,
    updated: 1700003600,
    planid: 'identity_plus_v1',
    stripe_customer_id: 'cus_123',
    stripe_subscription_id: 'sub_123',
    subscription_status: 'active',
    subscription_period_end: '2026-01-01',
    billing_email: 'billing@acme.test',
    sync_status: 'potentially_stale',
    sync_status_reason: 'planid differs from Stripe',
    ...overrides,
  };
}

function orgsPayload(rows = [orgRow()]) {
  return {
    shrimp: '',
    record: {},
    details: {
      organizations: rows,
      pagination: { page: 1, per_page: 50, total_count: rows.length, total_pages: 1 },
      filters: { status: null, sync_status: null },
    },
  };
}

describe('AdminOrganizations (list + row navigation — ticket #32)', () => {
  let wrapper: VueWrapper;
  let pinia: ReturnType<typeof createPinia>;

  beforeEach(() => {
    pinia = createPinia();
    setActivePinia(pinia);
    vi.clearAllMocks();
  });
  afterEach(() => wrapper?.unmount());

  const mountView = () => mount(AdminOrganizations, { global: { plugins: [pinia, i18n] } });

  it('fetches the first page on mount and renders a row per organization', async () => {
    mockApi.get.mockResolvedValue({ data: orgsPayload() });
    wrapper = mountView();
    await flushPromises();

    expect(mockApi.get).toHaveBeenCalledWith('/api/colonel/organizations', {
      params: { page: 1, per_page: 50 },
    });
    const table = wrapper.find('[data-testid="organizations-table"]');
    expect(table.exists()).toBe(true);
    // The account email is obscured by default (RevealEmail).
    expect(table.text()).not.toContain('owner@acme.test');
    expect(table.text()).toContain('o•••@a•••.test');
  });

  it('renders the empty state when there are no organizations', async () => {
    mockApi.get.mockResolvedValue({ data: orgsPayload([]) });
    wrapper = mountView();
    await flushPromises();

    expect(wrapper.find('[data-testid="organizations-table-empty"]').exists()).toBe(true);
  });

  it('refetches with the sync-status filter when it changes', async () => {
    mockApi.get.mockResolvedValue({ data: orgsPayload() });
    wrapper = mountView();
    await flushPromises();

    const select = wrapper.find('#kit-filter-sync_status');
    await select.setValue('potentially_stale');
    await flushPromises();

    expect(mockApi.get).toHaveBeenLastCalledWith('/api/colonel/organizations', {
      params: { page: 1, per_page: 50, sync_status: 'potentially_stale' },
    });
  });

  it('navigates to the detail page on row click (drawer superseded by detail page)', async () => {
    mockApi.get.mockResolvedValue({ data: orgsPayload() });
    wrapper = mountView();
    await flushPromises();

    await wrapper.find('[data-testid="organizations-table"] tbody tr').trigger('click');

    // The in-view drawer is gone; the row routes to AdminOrganizationDetail by
    // the org's public id (extid), where investigate/entitlements/reconcile live.
    expect(pushMock).toHaveBeenCalledWith({
      name: 'AdminOrganizationDetail',
      params: { id: 'on_abc123' },
    });
    expect(wrapper.find('[data-testid="organizations-drawer"]').exists()).toBe(false);
  });

  it('shows the error banner + retry on a network failure', async () => {
    mockApi.get.mockRejectedValue(new Error('Network Error'));
    wrapper = mountView();
    await flushPromises();

    const banner = wrapper.find('[data-testid="organizations-error"]');
    expect(banner.exists()).toBe(true);

    mockApi.get.mockResolvedValueOnce({ data: orgsPayload() });
    await banner.find('button').trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-testid="organizations-error"]').exists()).toBe(false);
  });
});
