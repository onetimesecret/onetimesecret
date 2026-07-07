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

function investigatePayload() {
  return {
    shrimp: '',
    record: {
      org_id: 'org1',
      extid: 'on_abc123',
      investigated_at: '2026-07-06 12:00:00 UTC',
      local: {
        planid: 'free_v1',
        stripe_customer_id: 'cus_123',
        stripe_subscription_id: 'sub_123',
        subscription_status: 'active',
        subscription_period_end: null,
      },
      stripe: {
        available: true,
        reason: null,
        subscription: {
          id: 'sub_123',
          status: 'active',
          current_period_end: 1735689600,
          price_id: 'price_1',
          price_nickname: null,
          product_id: 'prod_1',
          product_name: 'Identity Plus',
          subscription_metadata_plan_id: null,
          price_metadata_plan_id: 'identity_plus_v1',
          resolved_plan_id: 'identity_plus_v1',
        },
      },
      comparison: {
        match: false,
        verdict: 'mismatch_detected',
        details: 'planid differs',
        issues: [{ field: 'planid', local: 'free_v1', stripe: 'identity_plus_v1', severity: 'high' }],
      },
    },
  };
}

function grantAck() {
  return {
    shrimp: '',
    record: {
      org_id: 'org1',
      extid: 'on_abc123',
      entitlement: 'custom_domains',
      action: 'granted',
      effective_entitlements: ['create_secrets', 'custom_domains'],
      grants: ['custom_domains'],
      revokes: [],
    },
  };
}

describe('AdminOrganizations (list + investigate + entitlements — ticket #32)', () => {
  let wrapper: VueWrapper;
  let pinia: ReturnType<typeof createPinia>;

  beforeEach(() => {
    pinia = createPinia();
    setActivePinia(pinia);
    vi.clearAllMocks();
  });
  afterEach(() => wrapper?.unmount());

  const mountView = () => mount(AdminOrganizations, { global: { plugins: [pinia, i18n] } });
  const dialogInput = (w: VueWrapper) => w.find('#admin-confirm-input');
  const dialogSubmit = (w: VueWrapper) => w.find('[data-testid="admin-confirm-submit"]');

  it('fetches the first page on mount and renders a row per organization', async () => {
    mockApi.get.mockResolvedValue({ data: orgsPayload() });
    wrapper = mountView();
    await flushPromises();

    expect(mockApi.get).toHaveBeenCalledWith('/api/colonel/organizations', {
      params: { page: 1, per_page: 50 },
    });
    const table = wrapper.find('[data-testid="organizations-table"]');
    expect(table.exists()).toBe(true);
    expect(table.text()).toContain('owner@acme.test');
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

  it('opens the detail drawer on row click and investigates on demand', async () => {
    mockApi.get.mockResolvedValue({ data: orgsPayload() });
    mockApi.post.mockResolvedValue({ data: investigatePayload() });
    wrapper = mountView();
    await flushPromises();

    await wrapper.find('[data-testid="organizations-table"] tbody tr').trigger('click');
    await flushPromises();

    const drawer = wrapper.find('[data-testid="organizations-drawer"]');
    expect(drawer.exists()).toBe(true);
    expect(drawer.text()).toContain('on_abc123');

    await wrapper.find('[data-testid="org-investigate-button"]').trigger('click');
    await flushPromises();

    expect(mockApi.post).toHaveBeenCalledWith('/api/colonel/organizations/on_abc123/investigate');
    const result = wrapper.find('[data-testid="org-investigate-result"]');
    expect(result.exists()).toBe(true);
    // #2349 parity: the mismatch verdict + issue field surface in the read-out.
    expect(wrapper.find('[data-testid="org-investigate-verdict"]').exists()).toBe(true);
    expect(result.text()).toContain('planid');
  });

  it('grants an entitlement through a typed-confirmation dialog and shows the new override state', async () => {
    mockApi.get.mockResolvedValue({ data: orgsPayload() });
    mockApi.post.mockResolvedValue({ data: grantAck() });
    wrapper = mountView();
    await flushPromises();

    await wrapper.find('[data-testid="organizations-table"] tbody tr').trigger('click');
    await flushPromises();

    // Enter an entitlement and request a grant.
    await wrapper.find('[data-testid="org-entitlement-input"]').setValue('custom_domains');
    await wrapper.find('[data-testid="org-entitlement-grant"]').trigger('click');
    await flushPromises();

    // Typed-confirmation gate: confirm stays disabled until the org's public id
    // is retyped exactly.
    expect(dialogSubmit(wrapper).attributes('disabled')).toBeDefined();
    await dialogInput(wrapper).setValue('on_abc123');
    expect(dialogSubmit(wrapper).attributes('disabled')).toBeUndefined();

    await dialogSubmit(wrapper).trigger('submit');
    await flushPromises();

    expect(mockApi.post).toHaveBeenCalledWith(
      '/api/colonel/organizations/on_abc123/entitlements/grant',
      { entitlement: 'custom_domains' }
    );
    expect(showMock).toHaveBeenCalledTimes(1);
    expect(showMock.mock.calls[0][1]).toBe('success');
    // The recomputed override state renders after the mutation.
    const state = wrapper.find('[data-testid="org-override-state"]');
    expect(state.exists()).toBe(true);
    expect(state.text()).toContain('custom_domains');
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
