// src/tests/apps/admin/AdminOrganizationDetail.spec.ts

import { flushPromises, mount, RouterLinkStub, VueWrapper } from '@vue/test-utils';
import { createPinia, setActivePinia } from 'pinia';
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

import AdminCheckoutLinkModal from '@/apps/admin/components/AdminCheckoutLinkModal.vue';
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
      // The billing catalog the override picker offers (same source as the
      // server's known_entitlement? predicate).
      available_entitlements: [
        {
          name: 'api_access',
          description: 'Can use REST API endpoints',
          category: 'infrastructure',
        },
        { name: 'create_secrets', description: 'Can create basic secrets', category: 'core' },
        {
          name: 'custom_domains',
          description: 'Can configure custom domains',
          category: 'infrastructure',
        },
      ],
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

function clearAck() {
  return {
    shrimp: '',
    record: {
      org_id: 'org1',
      extid: PUBLIC_ID,
      entitlement: null,
      action: 'cleared',
      effective_entitlements: ['create_secrets'],
      grants: [],
      revokes: [],
    },
  };
}

function reconcileAck(
  memberships: {
    success: number;
    failed: number;
    total: number;
    failed_ids: string[];
  } | null = null
) {
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
      // #3907 item 3: cascade counts ride on the record; the null default
      // exercises the "did not cascade / cascade raised" shape the schema
      // must accept.
      memberships,
    },
  };
}

function plansPayload() {
  return {
    plans: [
      { planid: 'identity_plus_v1', name: 'Identity Plus', display_order: 1 },
      { planid: 'team_plus_v1', name: 'Team Plus', display_order: 2 },
    ],
    source: 'stripe',
  };
}

function planChangeAck(warning: string | null = null, details: Record<string, unknown> = {}) {
  return {
    shrimp: '',
    record: {
      org_id: 'org1',
      extid: PUBLIC_ID,
      display_name: 'Acme',
      old_planid: 'identity_plus_v1',
      new_planid: 'team_plus_v1',
      updated: 1700007200,
    },
    details: {
      changed: true,
      materialization: 'materialized',
      message: 'Organization plan updated successfully',
      warning,
      ...details,
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
        issues: [
          { field: 'planid', local: 'free_v1', stripe: 'identity_plus_v1', severity: 'high' },
        ],
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
      // vue-router is mocked wholesale above, so RouterLink has no real
      // implementation to resolve — stub it the way AdminCustomers.spec does so
      // the member links still render and carry their `to` target.
      global: { plugins: [pinia, i18n], stubs: { RouterLink: RouterLinkStub } },
    });
  const dialogInput = (w: VueWrapper) => w.find('#admin-confirm-input');
  const dialogSubmit = (w: VueWrapper) => w.find('[data-testid="admin-confirm-submit"]');

  it('fetches the org by public id on mount and renders the read-out with obscured emails', async () => {
    mockApi.get.mockResolvedValue({ data: detailPayload() });
    wrapper = mountView();
    await flushPromises();

    expect(mockApi.get).toHaveBeenCalledWith(`/api/colonel/organizations/${PUBLIC_ID}`, undefined);
    expect(wrapper.find('[data-testid="detail-content"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="checkout-link-button"]').exists()).toBe(true);
    expect(wrapper.findComponent(AdminCheckoutLinkModal).props('endpoint')).toBe(
      `/api/colonel/organizations/${PUBLIC_ID}/checkout-link`
    );

    // Emails obscured by default (RevealEmail).
    const billing = wrapper.find('[data-testid="billing-contactEmail"]');
    expect(billing.text()).not.toContain('owner@acme.test');
    expect(billing.text()).toContain('o•••@a•••.test');

    // Entitlement resolution matrix is shown on load: one row per entitlement,
    // each carrying WHY it resolves the way it does.
    expect(wrapper.find('[data-testid="entitlements-matrix"]').exists()).toBe(true);
    expect(
      wrapper.find('[data-testid="entitlement-row-create_secrets"]').attributes('data-state')
    ).toBe('plan');
    expect(
      wrapper.find('[data-testid="entitlement-row-custom_domains"]').attributes('data-state')
    ).toBe('granted');
    expect(wrapper.find('[data-testid="entitlements-insync"]').exists()).toBe(true);
    // Summary signals stay visible above the matrix.
    expect(wrapper.find('[data-testid="entitlements-summary-materialized"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="entitlements-summary-plan-stale"]').exists()).toBe(true);

    // Members + domains tables render.
    expect(wrapper.find('[data-testid="members-table"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="domains-table"]').text()).toContain('secrets.acme.test');

    // Each member shows their public id and links through to the customer
    // record. A real router-link (middle-click / new-tab must work), and the
    // extid IS the route param — GetUserDetails resolves by extid first.
    const memberLink = wrapper
      .findAllComponents(RouterLinkStub)
      .find((link) => link.attributes('data-testid') === 'member-detail-mem_1');
    expect(memberLink).toBeDefined();
    expect(memberLink!.text()).toContain('mem_1');
    expect(memberLink!.props('to')).toEqual({
      name: 'AdminCustomerDetail',
      params: { id: 'mem_1' },
    });
  });

  it('surfaces the drift + stale warnings when the entitlements are out of sync', async () => {
    mockApi.get.mockResolvedValue({
      data: detailPayload({
        details: {
          ...detailPayload().details,
          entitlements: {
            ...detailPayload().details.entitlements,
            // Realistic drift: extra ⊆ materialized, missing ⊆ expected.
            materialized: ['create_secrets', 'legacy_flag'],
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
    // And the matrix names the two failure modes per row.
    expect(
      wrapper.find('[data-testid="entitlement-row-legacy_flag"]').attributes('data-state')
    ).toBe('orphaned');
    expect(
      wrapper.find('[data-testid="entitlement-row-custom_domains"]').attributes('data-state')
    ).toBe('missing');
  });

  it('grants an entitlement chosen from the catalog dropdown and refreshes the detail', async () => {
    mockApi.get.mockResolvedValue({ data: detailPayload() });
    mockApi.post.mockResolvedValue({ data: grantAck() });
    wrapper = mountView();
    await flushPromises();

    // The dropdown is the primary affordance; free text is not shown yet.
    expect(wrapper.find('[data-testid="org-entitlement-select"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="org-entitlement-input"]').exists()).toBe(false);

    await wrapper.find('[data-testid="org-entitlement-select"]').setValue('api_access');
    // A catalog pick is never flagged as a typo.
    expect(wrapper.find('[data-testid="org-entitlement-catalog-warning"]').exists()).toBe(false);
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
      { entitlement: 'api_access' }
    );
    expect(showMock).toHaveBeenCalledTimes(1);
    expect(showMock.mock.calls[0][1]).toBe('success');
    // The panel is driven by a refreshed GET, not the ack: three GETs total
    // (mount-time detail + available-plans catalog, then the refresh).
    expect(mockApi.get).toHaveBeenCalledTimes(3);
  });

  it('changes the plan through the billing-section selector and confirm dialog', async () => {
    mockApi.get.mockImplementation((url: string) => {
      if (url === '/api/colonel/available-plans') {
        return Promise.resolve({ data: plansPayload() });
      }
      return Promise.resolve({ data: detailPayload() });
    });
    mockApi.post.mockResolvedValue({ data: planChangeAck() });
    wrapper = mountView();
    await flushPromises();

    // The selector renders the catalog and tracks the record's current plan.
    const select = wrapper.find('[data-testid="plan-select"]');
    expect(select.exists()).toBe(true);
    expect((select.element as HTMLSelectElement).value).toBe('identity_plus_v1');
    // Apply is a no-op while the selection matches the record.
    expect(wrapper.find('[data-testid="plan-apply"]').attributes('disabled')).toBeDefined();
    // The catalog also feeds the checkout modal (previously mounted with []).
    expect(wrapper.findComponent(AdminCheckoutLinkModal).props('plans')).toHaveLength(2);

    await select.setValue('team_plus_v1');
    await wrapper.find('[data-testid="plan-apply"]').trigger('click');
    await flushPromises();

    // Reversible change: plain confirm, no typed-confirmation token.
    expect(dialogSubmit(wrapper).attributes('disabled')).toBeUndefined();
    await dialogSubmit(wrapper).trigger('submit');
    await flushPromises();

    expect(mockApi.post).toHaveBeenCalledWith(`/api/colonel/organizations/${PUBLIC_ID}/plan`, {
      planid: 'team_plus_v1',
    });
    expect(showMock.mock.calls[0][1]).toBe('success');
    // Refreshed after the mutation: detail + plans on mount, then the refresh.
    expect(mockApi.get).toHaveBeenCalledTimes(3);
  });

  it('surfaces the server Stripe-overwrite warning after a plan change', async () => {
    mockApi.get.mockImplementation((url: string) => {
      if (url === '/api/colonel/available-plans') {
        return Promise.resolve({ data: plansPayload() });
      }
      return Promise.resolve({ data: detailPayload() });
    });
    mockApi.post.mockResolvedValue({
      data: planChangeAck('Live Stripe subscription may overwrite this change.'),
    });
    wrapper = mountView();
    await flushPromises();

    await wrapper.find('[data-testid="plan-select"]').setValue('team_plus_v1');
    await wrapper.find('[data-testid="plan-apply"]').trigger('click');
    await flushPromises();
    await dialogSubmit(wrapper).trigger('submit');
    await flushPromises();

    // Success toast first, then the server's own warning text as info.
    expect(showMock).toHaveBeenCalledTimes(2);
    expect(showMock.mock.calls[1][0]).toContain('Stripe');
    expect(showMock.mock.calls[1][1]).toBe('info');
  });

  it('surfaces a failed entitlement re-materialization as an error, not success', async () => {
    mockApi.get.mockImplementation((url: string) => {
      if (url === '/api/colonel/available-plans') {
        return Promise.resolve({ data: plansPayload() });
      }
      return Promise.resolve({ data: detailPayload() });
    });
    // Planid wrote, but the entitlement engine did not run: the org keeps the
    // OLD plan's entitlements. The server's qualified message must render as
    // an error toast — never the unqualified success toast.
    mockApi.post.mockResolvedValue({
      data: planChangeAck(null, {
        materialization: 'materialization_failed',
        message:
          'Organization plan was saved, but entitlement re-materialization failed — ' +
          'run reconcile on this organization.',
      }),
    });
    wrapper = mountView();
    await flushPromises();

    await wrapper.find('[data-testid="plan-select"]').setValue('team_plus_v1');
    await wrapper.find('[data-testid="plan-apply"]').trigger('click');
    await flushPromises();
    await dialogSubmit(wrapper).trigger('submit');
    await flushPromises();

    expect(showMock).toHaveBeenCalledTimes(1);
    expect(showMock.mock.calls[0][0]).toContain('re-materialization failed');
    expect(showMock.mock.calls[0][1]).toBe('error');
  });

  it('keeps the out-of-catalog path (CLI parity): warns, then still grants', async () => {
    mockApi.get.mockResolvedValue({ data: detailPayload() });
    mockApi.post.mockResolvedValue({ data: grantAck() });
    wrapper = mountView();
    await flushPromises();

    // Opt into free text, then type a name the catalog does not carry.
    await wrapper.find('[data-testid="org-entitlement-select"]').setValue('__other__');
    await wrapper.find('[data-testid="org-entitlement-input"]').setValue('ships_next_release');
    expect(wrapper.find('[data-testid="org-entitlement-catalog-warning"]').exists()).toBe(true);

    // Warned, not blocked — the grant button stays live.
    await wrapper.find('[data-testid="org-entitlement-grant"]').trigger('click');
    await flushPromises();
    // The confirm dialog repeats the warning before the write.
    expect(wrapper.find('[data-testid="admin-confirm-dialog"]').text()).toContain(
      'entitlements.catalogWarning'
    );

    await dialogInput(wrapper).setValue(PUBLIC_ID);
    await dialogSubmit(wrapper).trigger('submit');
    await flushPromises();

    expect(mockApi.post).toHaveBeenCalledWith(
      `/api/colonel/organizations/${PUBLIC_ID}/entitlements/grant`,
      { entitlement: 'ships_next_release' }
    );
  });

  it('keeps clear-all behind the typed-confirmation gate and returns the picker to the catalog', async () => {
    mockApi.get.mockResolvedValue({ data: detailPayload() });
    mockApi.delete.mockResolvedValue({ data: clearAck() });
    wrapper = mountView();
    await flushPromises();

    // Land in free text first, so the reset is observable.
    await wrapper.find('[data-testid="org-entitlement-select"]').setValue('__other__');
    expect(wrapper.find('[data-testid="org-entitlement-input"]').exists()).toBe(true);

    await wrapper.find('[data-testid="org-entitlement-clear"]').trigger('click');
    await flushPromises();

    // Wipes EVERY override — the extid gate is unchanged.
    expect(dialogSubmit(wrapper).attributes('disabled')).toBeDefined();
    await dialogInput(wrapper).setValue(PUBLIC_ID);
    await dialogSubmit(wrapper).trigger('submit');
    await flushPromises();

    expect(mockApi.delete).toHaveBeenCalledWith(
      `/api/colonel/organizations/${PUBLIC_ID}/entitlements/overrides`
    );
    expect(wrapper.find('[data-testid="org-entitlement-select"]').exists()).toBe(true);
  });

  it('falls open to free text when the catalog is unavailable (no dropdown, no typo warning)', async () => {
    mockApi.get.mockResolvedValue({
      data: detailPayload({
        details: { ...detailPayload().details, available_entitlements: [] },
      }),
    });
    wrapper = mountView();
    await flushPromises();

    expect(wrapper.find('[data-testid="org-entitlement-select"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="org-entitlement-catalog-unavailable"]').exists()).toBe(true);

    await wrapper.find('[data-testid="org-entitlement-input"]').setValue('anything_at_all');
    // Fail OPEN, exactly like the server's known_entitlement? predicate.
    expect(wrapper.find('[data-testid="org-entitlement-catalog-warning"]').exists()).toBe(false);
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
    // memberships: null (did not cascade) renders no cascade line.
    expect(wrapper.find('[data-testid="reconcile-memberships"]').exists()).toBe(false);
    expect(showMock.mock.calls[0][1]).toBe('success');
    // Refreshed after the mutation (plus the mount-time available-plans GET).
    expect(mockApi.get).toHaveBeenCalledTimes(3);
  });

  // #3907 item 3: the applied statuses carry no reason string, so this line
  // is the only console-visible signal that a reconcile left memberships
  // with stale entitlements.
  it('surfaces a partial membership cascade with the failed ids', async () => {
    mockApi.get.mockResolvedValue({ data: detailPayload() });
    mockApi.post.mockResolvedValue({
      data: reconcileAck({ success: 1, failed: 2, total: 3, failed_ids: ['mem_p', 'mem_q'] }),
    });
    wrapper = mountView();
    await flushPromises();

    await wrapper.find('[data-testid="org-reconcile-button"]').trigger('click');
    await flushPromises();
    await dialogInput(wrapper).setValue(PUBLIC_ID);
    await dialogSubmit(wrapper).trigger('submit');
    await flushPromises();

    const cascade = wrapper.find('[data-testid="reconcile-memberships"]');
    expect(cascade.exists()).toBe(true);
    expect(cascade.text()).toContain('1/3');
    expect(cascade.text()).toContain('mem_p, mem_q');
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
