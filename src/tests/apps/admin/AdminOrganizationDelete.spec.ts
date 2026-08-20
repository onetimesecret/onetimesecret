// src/tests/apps/admin/AdminOrganizationDelete.spec.ts

/**
 * The colonel console's org DELETE flow (#4204) — the console peer of
 * `bin/ots org delete`, over the shared Onetime::Operations::Org::Delete op.
 *
 * Split out of AdminOrganizationDetail.spec.ts because this is a destructive
 * gate with its own two-request shape, the same way the customer purge gate
 * lives in AdminCustomerDetailPurge.spec.ts.
 *
 * What is pinned here:
 *   - The button PREVIEWS (dry_run=true) and never deletes on its own.
 *   - The dialog is built from the SERVER's plan, so an operator confirms
 *     against the real member/invitation/domain counts.
 *   - A guardrail blocks the apply client-side too, and toggling the one
 *     override that clears it re-plans.
 *   - Only `record.deleted` + `details.dry_run === false` are treated as proof
 *     of a deletion.
 */

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
// `isNavigationFailure` is reached by the shared error classifier on every
// failed mutation, so the mock must carry it or a blocked delete blows up in
// the composable instead of surfacing its reason.
vi.mock('vue-router', () => ({
  useRouter: () => ({ push: pushMock }),
  isNavigationFailure: () => false,
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

/** The delete plan / receipt the endpoint answers with. */
function deleteAck(
  overrides: {
    status?: string;
    deleted?: boolean;
    dry_run?: boolean;
    is_default?: boolean;
    active_subscription?: boolean;
    domains?: string[];
    drifted_domains?: string[];
    owner_org_count?: number;
  } = {}
) {
  const {
    status = 'planned',
    deleted = false,
    dry_run = true,
    is_default = false,
    active_subscription = false,
    domains = [],
    // Domains that still reference the org through `CustomDomain.owners` but
    // have fallen out of its collection: in NEITHER `domains` NOR
    // `domain_count`, so the plan is the operator's only sight of them.
    drifted_domains = [],
    owner_org_count = 2,
  } = overrides;
  return {
    shrimp: '',
    record: { deleted, org_id: PUBLIC_ID, display_name: 'Acme', status },
    details: {
      dry_run,
      planid: 'identity_plus_v1',
      members: [{ extid: 'mem_1', email: 'alice@example.com' }],
      members_notified: 1,
      pending_invitations: 2,
      domain_count: domains.length,
      domains,
      drifted_domains,
      is_default,
      active_subscription,
      owner_id: 'cust1',
      owner_org_count,
      default_org_cleared: ['mem_1'],
    },
  };
}

describe('AdminOrganizationDetail — permanent delete', () => {
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
      global: { plugins: [pinia, i18n], stubs: { RouterLink: RouterLinkStub } },
    });
  const dialogInput = (w: VueWrapper) => w.find('#admin-confirm-input');
  const dialogSubmit = (w: VueWrapper) => w.find('[data-testid="admin-confirm-submit"]');

  async function openPlan(ack = deleteAck()) {
    mockApi.get.mockResolvedValue({ data: detailPayload() });
    mockApi.delete.mockResolvedValue({ data: ack });
    wrapper = mountView();
    await flushPromises();

    await wrapper.find('[data-testid="org-delete-button"]').trigger('click');
    await flushPromises();
    return wrapper;
  }

  it('previews first — the button never deletes on its own', async () => {
    await openPlan();

    expect(mockApi.delete).toHaveBeenCalledTimes(1);
    const [url] = mockApi.delete.mock.calls[0];
    expect(url).toContain(`/api/colonel/organizations/${PUBLIC_ID}?`);
    expect(url).toContain('dry_run=true');
    expect(url).toContain('force_default=false');
    expect(url).toContain('force_subscription=false');
    expect(pushMock).not.toHaveBeenCalled();
  });

  it("builds the confirmation from the server's plan", async () => {
    await openPlan();

    const plan = wrapper.find('[data-testid="org-delete-plan"]');
    expect(plan.exists()).toBe(true);
    expect(wrapper.find('[data-testid="org-delete-member-count"]').text()).toBe('1');
    expect(plan.text()).toContain('alice@example.com');
    expect(plan.text()).toContain('identity_plus_v1');
    expect(wrapper.find('[data-testid="org-delete-blocked"]').exists()).toBe(false);
  });

  it('applies only after the extid is retyped, then navigates away', async () => {
    await openPlan();

    mockApi.delete.mockResolvedValue({
      data: deleteAck({ status: 'success', deleted: true, dry_run: false }),
    });
    await dialogInput(wrapper).setValue(PUBLIC_ID);
    await dialogSubmit(wrapper).trigger('submit');
    await flushPromises();

    expect(mockApi.delete).toHaveBeenCalledTimes(2);
    expect(mockApi.delete.mock.calls[1][0]).toContain('dry_run=false');
    expect(showMock).toHaveBeenCalledWith(expect.any(String), 'success');
    expect(pushMock).toHaveBeenCalledWith({ name: 'AdminOrganizations' });
  });

  it('refuses to report a deletion when the ack still echoes a dry run', async () => {
    await openPlan();

    mockApi.delete.mockResolvedValue({
      data: deleteAck({ status: 'planned', deleted: false, dry_run: true }),
    });
    await dialogInput(wrapper).setValue(PUBLIC_ID);
    await dialogSubmit(wrapper).trigger('submit');
    await flushPromises();

    expect(showMock).not.toHaveBeenCalled();
    expect(pushMock).not.toHaveBeenCalled();
  });

  it('surfaces a blocked guardrail and offers only the override that clears it', async () => {
    await openPlan(deleteAck({ status: 'is_default', is_default: true }));

    expect(wrapper.find('[data-testid="org-delete-blocked"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="org-delete-force-default"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="org-delete-force-subscription"]').exists()).toBe(false);
  });

  it('does not send an apply while a guardrail still blocks it', async () => {
    await openPlan(deleteAck({ status: 'last_org', owner_org_count: 1 }));

    await dialogInput(wrapper).setValue(PUBLIC_ID);
    await dialogSubmit(wrapper).trigger('submit');
    await flushPromises();

    // Preview only: the blocked apply never reached the network.
    expect(mockApi.delete).toHaveBeenCalledTimes(1);
    expect(pushMock).not.toHaveBeenCalled();
  });

  it('re-plans when an override is toggled — clearing one guard can reveal the next', async () => {
    await openPlan(deleteAck({ status: 'is_default', is_default: true }));

    mockApi.delete.mockResolvedValue({
      data: deleteAck({
        status: 'active_subscription',
        is_default: true,
        active_subscription: true,
      }),
    });
    await wrapper.find('[data-testid="org-delete-force-default"] input').setValue(true);
    await flushPromises();

    expect(mockApi.delete).toHaveBeenCalledTimes(2);
    expect(mockApi.delete.mock.calls[1][0]).toContain('force_default=true');
    expect(mockApi.delete.mock.calls[1][0]).toContain('dry_run=true');
    // The next guard is now the visible one, with its own override.
    expect(wrapper.find('[data-testid="org-delete-force-subscription"]').exists()).toBe(true);
  });

  // Previews are unversioned requests; toggling an override re-plans while the
  // previous preview can still be in flight. The dangerous ordering is a STALE
  // response with a clear verdict landing after a fresh blocked one — the
  // operator would confirm against override state that is no longer selected.
  it('discards an out-of-order preview — a stale response never clears a live guard', async () => {
    await openPlan(deleteAck({ status: 'is_default', is_default: true }));

    // The next two previews go out back-to-back; the FIRST resolves LAST.
    const resolvers: Array<(value: { data: unknown }) => void> = [];
    mockApi.delete.mockImplementation(
      () =>
        new Promise((resolve) => {
          resolvers.push(resolve);
        })
    );

    const toggle = wrapper.find('[data-testid="org-delete-force-default"] input');
    await toggle.setValue(true); // preview A: force_default=true → would come back clear
    await toggle.setValue(false); // preview B: force_default=false → still blocked
    await flushPromises();
    expect(resolvers).toHaveLength(2);

    // B (the newest, matching the current overrides) answers first: blocked.
    resolvers[1]({ data: deleteAck({ status: 'is_default', is_default: true }) });
    await flushPromises();
    expect(wrapper.find('[data-testid="org-delete-blocked"]').exists()).toBe(true);

    // A limps in late with a CLEAR verdict for overrides nobody has selected
    // any more. It must be discarded, not confirmed against.
    resolvers[0]({ data: deleteAck({ status: 'planned' }) });
    await flushPromises();
    expect(wrapper.find('[data-testid="org-delete-blocked"]').exists()).toBe(true);
  });

  // Domain drift (#4211 follow-up): CustomDomain records still name this org
  // but have fallen out of its collection, so they are in NEITHER `domains`
  // NOR `domain_count`. The server refuses the apply with no override; the
  // dialog's only job is to name them and the repair.
  describe('drifted domains', () => {
    it('blocks the delete and names the drifted domains', async () => {
      await openPlan(
        deleteAck({
          status: 'drifted_domains',
          drifted_domains: ['ghost.example.com', 'stale.example.com'],
        })
      );

      const blocked = wrapper.find('[data-testid="org-delete-blocked"]');
      expect(blocked.exists()).toBe(true);
      // i18n is pass-through in specs (ADR-014): assert the KEY, and read the
      // names off the plan row that renders them verbatim.
      expect(blocked.text()).toContain(
        'web.admin.organizations.detail.delete.blocked.driftedDomains'
      );

      const drifted = wrapper.find('[data-testid="org-delete-drifted-domains"]');
      expect(drifted.exists()).toBe(true);
      expect(drifted.text()).toContain('ghost.example.com');
      expect(drifted.text()).toContain('stale.example.com');
      // The remediation is operator-side, so the command has to be on screen.
      expect(drifted.text()).toContain(
        'web.admin.organizations.detail.delete.driftedDomainsRepair'
      );
    });

    it('offers no override — there is none, and the apply never leaves the client', async () => {
      await openPlan(
        deleteAck({ status: 'drifted_domains', drifted_domains: ['ghost.example.com'] })
      );

      expect(wrapper.find('[data-testid="org-delete-force-default"]').exists()).toBe(false);
      expect(wrapper.find('[data-testid="org-delete-force-subscription"]').exists()).toBe(false);

      await dialogInput(wrapper).setValue(PUBLIC_ID);
      await dialogSubmit(wrapper).trigger('submit');
      await flushPromises();

      expect(mockApi.delete).toHaveBeenCalledTimes(1); // the preview only
      expect(pushMock).not.toHaveBeenCalled();
    });

    it('shows the drift even when another guard is the named verdict', async () => {
      // `has_domains` trips first server-side, but an org can carry both — and
      // removing the visible domains would then leave a delete still refused
      // for reasons nothing on the screen explains.
      await openPlan(
        deleteAck({
          status: 'has_domains',
          domains: ['secrets.acme.test'],
          drifted_domains: ['ghost.example.com'],
        })
      );

      expect(wrapper.find('[data-testid="org-delete-drifted-domains"]').text()).toContain(
        'ghost.example.com'
      );
    });

    it('still opens the dialog when the ack omits the key entirely', async () => {
      // A backend predating the field: `.default([])` keeps the plan readable
      // instead of bricking the confirmation with "plan unreadable".
      const ack = deleteAck();
      delete (ack.details as Record<string, unknown>).drifted_domains;
      await openPlan(ack);

      expect(wrapper.find('[data-testid="org-delete-plan"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="org-delete-drifted-domains"]').exists()).toBe(false);
    });
  });

  it('never opens the dialog on a plan it cannot read', async () => {
    mockApi.get.mockResolvedValue({ data: detailPayload() });
    mockApi.delete.mockResolvedValue({ data: { shrimp: '', record: { nope: true } } });
    wrapper = mountView();
    await flushPromises();

    await wrapper.find('[data-testid="org-delete-button"]').trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-testid="org-delete-plan"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="org-delete-preview-error"]').exists()).toBe(true);
  });
});
