// src/tests/apps/admin/AdminOrganizationDetail.spec.ts

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

// CopyButton (used by RevealEmail + JsonViewer) touches navigator.clipboard; stub.
vi.mock('@/shared/components/ui/CopyButton.vue', () => ({
  default: {
    name: 'CopyButton',
    template: '<button class="copy-button" />',
    props: ['text', 'tooltip', 'testid'],
  },
}));

// Render the headlessui confirm dialog synchronously in jsdom.
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

import AdminOrganizationDetail from '@/apps/admin/views/AdminOrganizationDetail.vue';
import { createTestI18n } from '@tests/setup';

const i18n = createTestI18n();
const PUBLIC_ID = 'on_abc123';

function detailPayload(overrides: Record<string, unknown> = {}) {
  return {
    shrimp: '',
    record: {
      org_id: 'org1',
      extid: PUBLIC_ID,
      display_name: 'Acme',
      description: 'Acme workspace',
      is_default: false,
      archived: false,
      archived_at: null,
      archived_comment: null,
      contact_email: 'owner@acme.test',
      owner_id: 'cust1',
      owner_email: 'ow***@a***.test',
      billing_email: 'billing@acme.test',
      member_count: 1,
      domain_count: 1,
      created: 1700000000,
      updated: 1700003600,
      planid: 'identity_plus_v1',
      stripe_customer_id: 'cus_123',
      stripe_subscription_id: 'sub_123',
      subscription_status: 'active',
      subscription_period_end: '2026-01-01',
      billing_email_present: true,
      sync_status: 'potentially_stale',
      sync_status_reason: 'planid differs from Stripe',
    },
    details: {
      entitlements: {
        plan: ['create_secrets'],
        grants: ['custom_domains'],
        revokes: [],
        materialized: ['create_secrets', 'custom_domains'],
        expected: ['create_secrets', 'custom_domains'],
        materialized_flag: true,
        materialized_at: 1700000000,
        plan_stale: false,
        drift: { extra: [], missing: [], in_sync: true },
      },
      members: [
        {
          extid: 'mem_1',
          email: 'alice@example.com',
          role: 'owner',
          status: 'active',
          is_owner: true,
          joined_at: 1700000000,
          created: 1700000000,
        },
      ],
      domains: [
        {
          extid: 'dom_1',
          domain_id: 'd1',
          display_domain: 'secrets.acme.test',
          base_domain: 'acme.test',
          status: 'active',
          verified: true,
          resolving: true,
          verification_state: 'verified',
          ready: true,
          created: 1700000000,
        },
      ],
    },
    ...overrides,
  };
}

function grantAck() {
  return {
    shrimp: '',
    record: {
      org_id: 'org1',
      extid: PUBLIC_ID,
      entitlement: 'analytics',
      action: 'granted',
      effective_entitlements: ['create_secrets', 'custom_domains', 'analytics'],
      grants: ['custom_domains', 'analytics'],
      revokes: [],
    },
  };
}

function reconcileAck() {
  return {
    shrimp: '',
    record: {
      org_id: 'org1',
      extid: PUBLIC_ID,
      mode: 'stripe_sync',
      status: 'reconciled',
      reason: null,
      before: {
        planid: 'free_v1',
        subscription_status: 'active',
        subscription_period_end: null,
        materialized_count: 1,
      },
      after: {
        planid: 'identity_plus_v1',
        subscription_status: 'active',
        subscription_period_end: '2026-01-01',
        materialized_count: 2,
      },
    },
  };
}

function investigateAck() {
  return {
    shrimp: '',
    record: {
      org_id: 'org1',
      extid: PUBLIC_ID,
      investigated_at: '2026-07-06 12:00:00 UTC',
      local: {
        planid: 'free_v1',
        stripe_customer_id: 'cus_123',
        stripe_subscription_id: 'sub_123',
        subscription_status: 'active',
        subscription_period_end: null,
      },
      stripe: { available: true, reason: null, subscription: null },
      comparison: {
        match: false,
        verdict: 'mismatch_detected',
        details: 'planid differs',
        issues: [{ field: 'planid', local: 'free_v1', stripe: 'identity_plus_v1', severity: 'high' }],
      },
    },
  };
}

describe('AdminOrganizationDetail (org detail + entitlements + reconcile)', () => {
  let wrapper: VueWrapper;
  let pinia: ReturnType<typeof createPinia>;

  beforeEach(() => {
    pinia = createPinia();
    setActivePinia(pinia);
    vi.clearAllMocks();
  });
  afterEach(() => wrapper?.unmount());

  const mountView = () =>
    mount(AdminOrganizationDetail, {
      props: { id: PUBLIC_ID },
      global: { plugins: [pinia, i18n] },
    });
  const dialogInput = (w: VueWrapper) => w.find('#admin-confirm-input');
  const dialogSubmit = (w: VueWrapper) => w.find('[data-testid="admin-confirm-submit"]');

  it('fetches the org by public id on mount and renders the read-out with obscured emails', async () => {
    mockApi.get.mockResolvedValue({ data: detailPayload() });
    wrapper = mountView();
    await flushPromises();

    expect(mockApi.get).toHaveBeenCalledWith(`/api/colonel/organizations/${PUBLIC_ID}`, undefined);
    expect(wrapper.find('[data-testid="detail-content"]').exists()).toBe(true);

    // Emails obscured by default (RevealEmail).
    const billing = wrapper.find('[data-testid="billing-contactEmail"]');
    expect(billing.text()).not.toContain('owner@acme.test');
    expect(billing.text()).toContain('o•••@a•••.test');

    // Entitlement breakdown is shown on load (plan / grants / materialized).
    expect(wrapper.find('[data-testid="entitlements-plan"]').text()).toContain('create_secrets');
    expect(wrapper.find('[data-testid="entitlements-grants"]').text()).toContain('custom_domains');
    expect(wrapper.find('[data-testid="entitlements-materialized"]').text()).toContain('custom_domains');
    expect(wrapper.find('[data-testid="entitlements-insync"]').exists()).toBe(true);

    // Members + domains tables render.
    expect(wrapper.find('[data-testid="members-table"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="domains-table"]').text()).toContain('secrets.acme.test');
  });

  it('surfaces the drift + stale warnings when the entitlements are out of sync', async () => {
    mockApi.get.mockResolvedValue({
      data: detailPayload({
        details: {
          ...detailPayload().details,
          entitlements: {
            ...detailPayload().details.entitlements,
            plan_stale: true,
            drift: { extra: ['legacy_flag'], missing: ['custom_domains'], in_sync: false },
          },
        },
      }),
    });
    wrapper = mountView();
    await flushPromises();

    expect(wrapper.find('[data-testid="entitlements-drift-badge"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="entitlements-stale-badge"]').exists()).toBe(true);
    const drift = wrapper.find('[data-testid="entitlements-drift"]');
    expect(drift.text()).toContain('legacy_flag');
    expect(drift.text()).toContain('custom_domains');
  });

  it('grants an entitlement through a typed-confirmation dialog and refreshes the detail', async () => {
    mockApi.get.mockResolvedValue({ data: detailPayload() });
    mockApi.post.mockResolvedValue({ data: grantAck() });
    wrapper = mountView();
    await flushPromises();

    await wrapper.find('[data-testid="org-entitlement-input"]').setValue('analytics');
    await wrapper.find('[data-testid="org-entitlement-grant"]').trigger('click');
    await flushPromises();

    // Typed-confirmation gate: confirm disabled until the extid is retyped.
    expect(dialogSubmit(wrapper).attributes('disabled')).toBeDefined();
    await dialogInput(wrapper).setValue(PUBLIC_ID);
    expect(dialogSubmit(wrapper).attributes('disabled')).toBeUndefined();

    await dialogSubmit(wrapper).trigger('submit');
    await flushPromises();

    expect(mockApi.post).toHaveBeenCalledWith(
      `/api/colonel/organizations/${PUBLIC_ID}/entitlements/grant`,
      { entitlement: 'analytics' }
    );
    expect(showMock).toHaveBeenCalledTimes(1);
    expect(showMock.mock.calls[0][1]).toBe('success');
    // The panel is driven by a refreshed GET, not the ack: two GETs total.
    expect(mockApi.get).toHaveBeenCalledTimes(2);
  });

  it('reconciles through a typed-confirmation dialog and shows the before/after diff', async () => {
    mockApi.get.mockResolvedValue({ data: detailPayload() });
    mockApi.post.mockResolvedValue({ data: reconcileAck() });
    wrapper = mountView();
    await flushPromises();

    await wrapper.find('[data-testid="org-reconcile-button"]').trigger('click');
    await flushPromises();

    expect(dialogSubmit(wrapper).attributes('disabled')).toBeDefined();
    await dialogInput(wrapper).setValue(PUBLIC_ID);
    await dialogSubmit(wrapper).trigger('submit');
    await flushPromises();

    expect(mockApi.post).toHaveBeenCalledWith(`/api/colonel/organizations/${PUBLIC_ID}/reconcile`);
    const result = wrapper.find('[data-testid="org-reconcile-result"]');
    expect(result.exists()).toBe(true);
    // Diff renders both sides (plan free_v1 → identity_plus_v1).
    const planDiff = wrapper.find('[data-testid="reconcile-diff-planid"]');
    expect(planDiff.text()).toContain('free_v1');
    expect(planDiff.text()).toContain('identity_plus_v1');
    expect(showMock.mock.calls[0][1]).toBe('success');
    // Refreshed after the mutation.
    expect(mockApi.get).toHaveBeenCalledTimes(2);
  });

  it('investigates on demand and renders the verdict', async () => {
    mockApi.get.mockResolvedValue({ data: detailPayload() });
    mockApi.post.mockResolvedValue({ data: investigateAck() });
    wrapper = mountView();
    await flushPromises();

    await wrapper.find('[data-testid="org-investigate-button"]').trigger('click');
    await flushPromises();

    expect(mockApi.post).toHaveBeenCalledWith(
      `/api/colonel/organizations/${PUBLIC_ID}/investigate`
    );
    expect(wrapper.find('[data-testid="org-investigate-verdict"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="org-investigate-result"]').text()).toContain('planid');
  });

  it('renders the not-found state on a 404', async () => {
    mockApi.get.mockRejectedValue({ response: { status: 404 } });
    wrapper = mountView();
    await flushPromises();

    expect(wrapper.find('[data-testid="detail-not-found"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="detail-content"]').exists()).toBe(false);
  });
});
