// src/tests/apps/workspace/account/OrganizationSettings.spec.ts

import OrganizationSettings from '@/apps/workspace/account/settings/OrganizationSettings.vue';
import { createTestingPinia } from '@pinia/testing';
import { flushPromises, mount, VueWrapper } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { nextTick, ref } from 'vue';
import { createTestI18n } from '@tests/setup';

// Mock vue-router
vi.mock('vue-router', () => ({
  useRoute: () => ({
    path: '/org/on1abc123',
    params: { extid: 'on1abc123', orgid: 'on1abc123' },
    query: {},
  }),
  useRouter: () => ({
    push: vi.fn(),
    replace: vi.fn(),
    back: vi.fn(),
  }),
  RouterLink: {
    name: 'RouterLink',
    template: '<a :href="to"><slot /></a>',
    props: ['to'],
  },
}));

// Mock child components
vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="o-icon" :data-icon-name="name" />',
    props: ['collection', 'name', 'class'],
  },
}));
vi.mock('@/shared/components/forms/BasicFormAlerts.vue', () => ({
  default: {
    name: 'BasicFormAlerts',
    template: '<div class="form-alerts" data-testid="form-alerts">{{ error }}{{ success }}</div>',
    props: ['error', 'success'],
  },
}));
vi.mock('@/apps/workspace/components/members/MembersTable.vue', () => ({
  default: {
    name: 'MembersTable',
    template: '<div class="members-table" />',
    props: ['members', 'orgExtid', 'isLoading', 'compact'],
  },
}));
vi.mock('@/apps/workspace/components/billing/EntitlementUpgradePrompt.vue', () => ({
  default: {
    name: 'EntitlementUpgradePrompt',
    template: '<div class="entitlement-upgrade-prompt" />',
    props: ['error', 'resourceType'],
  },
}));
vi.mock('@/apps/workspace/components/domains/DomainsTable.vue', () => ({
  default: {
    name: 'DomainsTable',
    template: '<div class="domains-table" />',
  },
}));
// SecretActivityTable owns its own fetching (mounting IS activation), so it
// must be mocked here — otherwise switching to the Activity tab fires a real
// useApi fetch this suite doesn't stub.
vi.mock('@/apps/workspace/components/organizations/SecretActivityTable.vue', () => ({
  default: {
    name: 'SecretActivityTable',
    template:
      '<div class="secret-activity-table" data-testid="secret-activity-table" :data-org-extid="orgExtid" />',
    props: ['orgExtid'],
  },
}));
vi.mock('@/shared/components/closet/ListSkeleton.vue', () => ({
  default: {
    name: 'ListSkeleton',
    template: '<div class="list-skeleton" data-testid="list-skeleton" />',
    props: ['icon', 'iconSize'],
  },
}));
vi.mock('@/shared/components/ui/EmptyState.vue', () => ({
  default: {
    name: 'EmptyState',
    template: `<div class="empty-state" data-testid="empty-state">
      <slot name="title" />
      <slot name="description" />
      <a v-if="showAction !== false" :href="actionRoute" data-testid="empty-state-action">{{ actionText }}</a>
    </div>`,
    props: ['actionRoute', 'actionText', 'showAction', 'testid'],
  },
}));

// Domains + permissions composables.
// The Domains-tab "Add Domain" CTA is gated on `canCreateDomain && domainCount > 0`.
// We vary `mockDomainCount` to exercise the domainCount portion (the change on
// this branch). `canCreateDomain` is held via its own ref so we test the
// component's gate, not the permission logic itself — that lives in
// useOrgPermissions, which is being reworked in feature/3326-permissions-api.
const mockDomainCount = ref(0);
const mockCanCreateDomain = ref(true);
vi.mock('@/shared/composables/useDomainsManager', () => ({
  useDomainsManager: () => ({
    isLoading: ref(false),
    records: ref([]),
    recordCount: mockDomainCount,
    error: ref(null),
    refreshRecords: vi.fn().mockResolvedValue(undefined),
  }),
}));
vi.mock('@/shared/composables/useOrgPermissions', () => ({
  useOrgPermissions: () => ({
    canCreateDomain: mockCanCreateDomain,
  }),
}));

// Mock services
vi.mock('@/services/billing.service', () => ({
  BillingService: {
    getOverview: vi.fn().mockResolvedValue({
      subscription: null,
      plan: null,
      usage: { members: 0, domains: 0 },
    }),
  },
}));

// Mock error classification
vi.mock('@/schemas/errors', () => ({
  classifyError: (err: unknown) => ({
    message: err instanceof Error ? err.message : 'Unknown error',
  }),
}));

// Store mocks
const mockOrganization = {
  objid: 'org_123',
  extid: 'on1abc123',
  owner_id: 'cust_456',
  display_name: 'Test Organization',
  description: 'A test organization',
  contact_email: 'billing@example.com',
  is_default: true,
  created: new Date('2024-01-01'),
  updated: new Date('2024-01-01'),
  entitlements: ['manage_members'],
  limits: { teams: 1 },
  planid: 'plan_starter', // Required for billing email field to be visible
  // Audit-trail role gate (#3637): admin/owner required. 'admin' keeps
  // isOwner false so owner-only sections stay unaffected.
  current_user_role: 'admin',
};

const mockFetchOrganization = vi.fn();
const mockUpdateOrganization = vi.fn();
const mockFetchInvitations = vi.fn();

vi.mock('@/shared/stores/organizationStore', () => ({
  useOrganizationStore: () => ({
    organizations: [],
    setCurrentOrganization: vi.fn(),
    fetchOrganization: mockFetchOrganization,
    updateOrganization: mockUpdateOrganization,
    fetchInvitations: mockFetchInvitations,
    createInvitation: vi.fn(),
    resendInvitation: vi.fn(),
    revokeInvitation: vi.fn(),
  }),
}));

vi.mock('@/shared/stores/membersStore', () => ({
  useMembersStore: () => ({
    members: [],
    memberCount: 0,
    loading: false,
    isInitialized: false,
    currentOrgExtid: null,
    fetchMembers: vi.fn().mockResolvedValue([]),
  }),
}));

// Mock entitlements composable
const mockEntitlements = ref<string[]>(['manage_members']);
vi.mock('@/shared/composables/useEntitlements', () => ({
  useEntitlements: () => ({
    entitlements: mockEntitlements,
    can: (entitlement: string) => mockEntitlements.value.includes(entitlement),
    formatEntitlement: (key: string) => `Formatted: ${key}`,
    initDefinitions: vi.fn().mockResolvedValue(undefined),
    ENTITLEMENTS: {
      MANAGE_MEMBERS: 'manage_members',
      MANAGE_SSO: 'manage_sso',
      AUDIT_LOGS: 'audit_logs',
    },
  }),
}));

// Mock features (SSO feature flag)
const mockOrgsSsoEnabled = ref(false);
vi.mock('@/utils/features', () => ({
  isOrgsSsoEnabled: () => mockOrgsSsoEnabled.value,
}));

vi.mock('@/shared/composables/useAsyncHandler', () => ({
  useAsyncHandler: () => ({
    wrap: vi.fn((fn) => fn()),
  }),
}));

vi.mock('@/shared/composables/useEntitlementError', () => ({
  useEntitlementError: () => ({
    isUpgradeRequired: ref(false),
  }),
}));

// i18n setup (pass-through: keys render as-is, see ADR-014)
const i18n = createTestI18n();

// Router stubs
const routerLinkStub = {
  template: '<a class="router-link" :href="to"><slot /></a>',
  props: ['to'],
};

describe('OrganizationSettings', () => {
  let wrapper: VueWrapper;

  beforeEach(() => {
    vi.clearAllMocks();

    // Default mock implementations
    mockFetchOrganization.mockResolvedValue(mockOrganization);
    mockUpdateOrganization.mockResolvedValue(mockOrganization);
    mockFetchInvitations.mockResolvedValue([]);
    mockEntitlements.value = ['manage_members'];
    mockDomainCount.value = 0;
    mockCanCreateDomain.value = true;
    mockOrgsSsoEnabled.value = false;
  });

  afterEach(() => {
    wrapper?.unmount();
  });

  const mountComponent = async () => {
    const pinia = createTestingPinia({
      createSpy: vi.fn,
      initialState: {
        bootstrap: {
          billing_enabled: true,
        },
      },
    });

    wrapper = mount(OrganizationSettings, {
      global: {
        plugins: [i18n, pinia],
        stubs: {
          RouterLink: routerLinkStub,
        },
      },
    });
    await flushPromises();
    await nextTick();
    return wrapper;
  };

  const switchToSettingsTab = async (w: VueWrapper) => {
    // Find the Settings (general) tab button (located in the nav tabs area).
    // Match by stable id, not rendered text: under pass-through i18n the tab
    // label renders the raw key 'web.organizations.tabs.general', not 'Settings'.
    const navTabs = w.find('nav[aria-label="Organization settings tabs"]');
    const tabs = navTabs.findAll('button');
    const settingsTab = tabs.find((tab) => tab.attributes('id') === 'org-tab-general');
    if (!settingsTab) {
      throw new Error('Settings tab not found');
    }
    await settingsTab.trigger('click');
    await flushPromises();
    await nextTick();
  };

  /**
   * Helper to find the billing email section within the Settings tab.
   * The billing email field has data-testid="org-billing-email-field".
   */
  const findBillingEmailSection = (w: VueWrapper) =>
    w.find('[data-testid="org-billing-email-field"]');

  /**
   * Helper to find the Edit link for billing email (navigates to billing overview)
   */
  const findEditLink = (w: VueWrapper) => w.find('[data-testid="org-billing-email-edit-link"]');

  /**
   * Billing Email Display Tests
   *
   * The billing email field is now read-only on the Settings tab.
   * Editing is done via the Billing Overview page (linked via Edit link).
   * The field is only visible for organizations with a paid plan (planid set).
   */
  describe('Billing Email Display', () => {
    describe('Visibility', () => {
      it('shows billing email field for organizations with a paid plan', async () => {
        wrapper = await mountComponent();
        await switchToSettingsTab(wrapper);

        const section = findBillingEmailSection(wrapper);
        expect(section.exists()).toBe(true);
        expect(section.text()).toContain('web.organizations.contact_email');
      });

      it('hides billing email field for organizations without a paid plan', async () => {
        const orgWithoutPlan = { ...mockOrganization, planid: undefined };
        mockFetchOrganization.mockResolvedValue(orgWithoutPlan);

        wrapper = await mountComponent();
        await switchToSettingsTab(wrapper);

        const section = findBillingEmailSection(wrapper);
        expect(section.exists()).toBe(false);
      });

      it('shows current billing email as text', async () => {
        wrapper = await mountComponent();
        await switchToSettingsTab(wrapper);

        const section = findBillingEmailSection(wrapper);
        expect(section.exists()).toBe(true);
        expect(section.text()).toContain('billing@example.com');
      });

      it('shows Edit link next to email', async () => {
        wrapper = await mountComponent();
        await switchToSettingsTab(wrapper);

        const editLink = findEditLink(wrapper);
        expect(editLink.exists()).toBe(true);
        expect(editLink.text()).toBe('web.COMMON.word_edit');
      });

      it('Edit link points to billing overview page', async () => {
        wrapper = await mountComponent();
        await switchToSettingsTab(wrapper);

        const editLink = findEditLink(wrapper);
        expect(editLink.attributes('href')).toBe('/billing/on1abc123/overview');
      });

      it('shows "Not set" when contact_email is empty', async () => {
        const orgWithoutEmail = { ...mockOrganization, contact_email: '' };
        mockFetchOrganization.mockResolvedValue(orgWithoutEmail);

        wrapper = await mountComponent();
        await switchToSettingsTab(wrapper);

        const section = findBillingEmailSection(wrapper);
        expect(section.text()).toContain('web.COMMON.not_set');
      });

      it('shows "Not set" when contact_email is null', async () => {
        const orgWithNullEmail = { ...mockOrganization, contact_email: null };
        mockFetchOrganization.mockResolvedValue(orgWithNullEmail);

        wrapper = await mountComponent();
        await switchToSettingsTab(wrapper);

        const section = findBillingEmailSection(wrapper);
        expect(section.text()).toContain('web.COMMON.not_set');
      });
    });

    describe('Read-only behavior', () => {
      it('does not have an input field for billing email', async () => {
        wrapper = await mountComponent();
        await switchToSettingsTab(wrapper);

        // Billing email is read-only - no input field should exist
        expect(wrapper.find('#billing-email').exists()).toBe(false);
      });

      it('shows helper text explaining where to edit billing email', async () => {
        wrapper = await mountComponent();
        await switchToSettingsTab(wrapper);

        const section = findBillingEmailSection(wrapper);
        // The helper text explains billing email is managed on the billing page
        expect(section.text()).toContain('web.organizations.billing_email_managed_on_billing');
      });
    });

    describe('Organization type visibility', () => {
      it('shows billing email field for default organization with paid plan', async () => {
        wrapper = await mountComponent();
        await switchToSettingsTab(wrapper);

        const section = findBillingEmailSection(wrapper);
        expect(section.exists()).toBe(true);
        expect(section.text()).toContain('web.organizations.contact_email');
      });

      it('shows billing email field for non-default organization with paid plan', async () => {
        const nonDefaultOrg = { ...mockOrganization, is_default: false };
        mockFetchOrganization.mockResolvedValue(nonDefaultOrg);

        wrapper = await mountComponent();
        await switchToSettingsTab(wrapper);

        const section = findBillingEmailSection(wrapper);
        expect(section.exists()).toBe(true);
        expect(section.text()).toContain('web.organizations.contact_email');
        expect(section.text()).toContain(nonDefaultOrg.contact_email);
      });
    });
  });

  /**
   * Organization ID Display
   *
   * The Settings tab shows the organization extid (on… prefix) as a copyable
   * read-only identifier for support/API-scoping reference. It is explicitly
   * NOT the HTTP Basic auth username — that is the customer extid (ur…) or
   * account email, surfaced on the account API settings page.
   */
  describe('Organization ID Display', () => {
    const findExtidField = (w: VueWrapper) => w.find('[data-testid="org-extid-field"]');

    it('shows the organization extid on the Settings tab', async () => {
      wrapper = await mountComponent();
      await switchToSettingsTab(wrapper);

      const field = findExtidField(wrapper);
      expect(field.exists()).toBe(true);
      expect(field.text()).toContain('web.organizations.organization_id');
      expect(field.find('[data-testid="org-extid-value"]').text()).toBe('on1abc123');
    });

    it('renders it read-only with a copy button carrying the extid', async () => {
      wrapper = await mountComponent();
      await switchToSettingsTab(wrapper);

      const field = findExtidField(wrapper);
      // No input — this is a reference identifier, not editable form data
      expect(field.find('input').exists()).toBe(false);

      const copyButton = field.find('button[data-testid="org-extid-copy"]');
      expect(copyButton.exists()).toBe(true);

      const copyComponent = wrapper.findComponent({ name: 'CopyButton' });
      expect(copyComponent.exists()).toBe(true);
      expect(copyComponent.props('text')).toBe('on1abc123');
    });

    it('shows the support/API-scoping hint', async () => {
      wrapper = await mountComponent();
      await switchToSettingsTab(wrapper);

      const field = findExtidField(wrapper);
      expect(field.text()).toContain('web.organizations.organization_id_hint');
    });

    it('omits the field when the organization has no extid', async () => {
      const orgWithoutExtid = { ...mockOrganization, extid: undefined };
      mockFetchOrganization.mockResolvedValue(orgWithoutExtid);

      wrapper = await mountComponent();
      await switchToSettingsTab(wrapper);

      expect(findExtidField(wrapper).exists()).toBe(false);
    });
  });

  /**
   * Domains tab — "Add Domain" CTA visibility (fix/sso-ui).
   *
   * The header CTA is gated on `canCreateDomain && domainCount > 0` so it does
   * not duplicate the add button in the empty state. Domains is the default
   * tab, so no tab switch is needed.
   */
  describe('Domains Tab — Add Domain CTA', () => {
    // Header CTA only; the empty-state has its own add link, which is the
    // duplication this gate (domainCount > 0) exists to avoid.
    const addLink = '[data-testid="org-domains-add-cta"]';

    it('hides the Add Domain CTA when there are no domains', async () => {
      mockCanCreateDomain.value = true;
      mockDomainCount.value = 0;
      wrapper = await mountComponent();

      expect(wrapper.find(addLink).exists()).toBe(false);
    });

    it('shows the Add Domain CTA when domains exist', async () => {
      mockCanCreateDomain.value = true;
      mockDomainCount.value = 2;
      wrapper = await mountComponent();

      expect(wrapper.find(addLink).exists()).toBe(true);
    });

    it('hides the Add Domain CTA when the user cannot create domains', async () => {
      mockCanCreateDomain.value = false;
      mockDomainCount.value = 2;
      wrapper = await mountComponent();

      expect(wrapper.find(addLink).exists()).toBe(false);
    });
  });

  /**
   * SSO tab — EmptyState CTA visibility (fix/sso-ui).
   *
   * The SSO tab EmptyState shows an "Add Domain" action only when
   * `canCreateDomain === true`. This prevents non-admins from seeing a CTA
   * they cannot act on.
   */
  describe('SSO Tab — EmptyState CTA', () => {
    // Helper to switch to SSO tab
    const switchToSsoTab = async (w: VueWrapper) => {
      const navTabs = w.find('nav[aria-label="Organization settings tabs"]');
      const tabs = navTabs.findAll('button');
      const ssoTab = tabs.find((tab) => tab.attributes('id') === 'org-tab-sso');
      if (!ssoTab) {
        throw new Error('SSO tab not found');
      }
      await ssoTab.trigger('click');
      await flushPromises();
      await nextTick();
    };

    // Enable SSO feature and entitlement for all tests in this block
    const enableSso = () => {
      mockOrgsSsoEnabled.value = true;
      mockEntitlements.value = ['manage_members', 'manage_sso'];
    };

    it('shows EmptyState CTA when user can create domains', async () => {
      enableSso();
      mockCanCreateDomain.value = true;
      mockDomainCount.value = 0;
      wrapper = await mountComponent();
      await switchToSsoTab(wrapper);

      const emptyState = wrapper.find('[data-testid="empty-state"]');
      expect(emptyState.exists()).toBe(true);
      expect(emptyState.find('[data-testid="empty-state-action"]').exists()).toBe(true);
    });

    it('hides EmptyState CTA when user cannot create domains', async () => {
      enableSso();
      mockCanCreateDomain.value = false;
      mockDomainCount.value = 0;
      wrapper = await mountComponent();
      await switchToSsoTab(wrapper);

      const emptyState = wrapper.find('[data-testid="empty-state"]');
      expect(emptyState.exists()).toBe(true);
      expect(emptyState.find('[data-testid="empty-state-action"]').exists()).toBe(false);
    });

    it('does not show EmptyState when domains exist', async () => {
      enableSso();
      mockCanCreateDomain.value = true;
      mockDomainCount.value = 2;
      wrapper = await mountComponent();
      await switchToSsoTab(wrapper);

      // When domains exist, the domain list is shown instead of EmptyState
      const emptyState = wrapper.find('[data-testid="org-section-sso"] [data-testid="empty-state"]');
      expect(emptyState.exists()).toBe(false);
    });
  });

  /**
   * Activity tab — Secret Activity audit trail (#3637).
   *
   * The audit_logs entitlement gates the panel CONTENT only, never the tab:
   * the tab is always rendered (and keyboard-reachable), and an unentitled
   * user who opens it lands on an inline upgrade notice — no redirect, no
   * hidden tab. SecretActivityTable owns its fetching, so when unentitled the
   * content div (and therefore the fetch) never mounts.
   */
  describe('Activity Tab — Secret Activity', () => {
    const switchToActivityTab = async (w: VueWrapper) => {
      const navTabs = w.find('nav[aria-label="Organization settings tabs"]');
      const tabs = navTabs.findAll('button');
      const activityTab = tabs.find((tab) => tab.attributes('id') === 'org-tab-activity');
      if (!activityTab) {
        throw new Error('Activity tab not found');
      }
      await activityTab.trigger('click');
      await flushPromises();
      await nextTick();
      return activityTab;
    };

    const findPanel = (w: VueWrapper) => w.find('[data-testid="org-section-activity"]');
    const findActivityTable = (w: VueWrapper) => w.find('[data-testid="secret-activity-table"]');

    describe('entitled organization', () => {
      beforeEach(() => {
        mockEntitlements.value = ['manage_members', 'audit_logs'];
      });

      it('shows the activity panel with the SecretActivityTable', async () => {
        wrapper = await mountComponent();
        await switchToActivityTab(wrapper);

        const panel = findPanel(wrapper);
        expect(panel.exists()).toBe(true);
        expect(panel.text()).toContain('web.organizations.audit.title');
        expect(panel.text()).toContain('web.organizations.audit.description');

        const table = findActivityTable(wrapper);
        expect(table.exists()).toBe(true);
        // The table fetches for the org in the route.
        expect(table.attributes('data-org-extid')).toBe('on1abc123');
      });

      it('does not show the upgrade notice', async () => {
        wrapper = await mountComponent();
        await switchToActivityTab(wrapper);

        expect(findPanel(wrapper).text()).not.toContain(
          'web.organizations.audit.upgrade_prompt'
        );
      });
    });

    describe('unentitled organization', () => {
      // beforeEach default: mockEntitlements = ['manage_members'] (no audit_logs)

      it('still renders the Activity tab in the tab bar', async () => {
        wrapper = await mountComponent();

        const navTabs = wrapper.find('nav[aria-label="Organization settings tabs"]');
        const activityTab = navTabs
          .findAll('button')
          .find((tab) => tab.attributes('id') === 'org-tab-activity');
        expect(activityTab).toBeDefined();
        expect(activityTab!.text()).toContain('web.organizations.tabs.activity');
      });

      it('opens the panel with the upgrade notice instead of redirecting', async () => {
        wrapper = await mountComponent();
        const activityTab = await switchToActivityTab(wrapper);

        // No redirect: the tab stays selected and its panel renders.
        expect(activityTab.attributes('aria-selected')).toBe('true');
        const panel = findPanel(wrapper);
        expect(panel.exists()).toBe(true);
        expect(panel.text()).toContain('web.organizations.audit.upgrade_prompt');

        // The upgrade CTA links to the plans page.
        const plansLink = panel
          .findAll('a')
          .find((a) => a.attributes('href') === '/billing/on1abc123/plans');
        expect(plansLink).toBeDefined();
        expect(plansLink!.text()).toContain('web.billing.overview.view_plans_action');
      });

      it('never mounts SecretActivityTable (so its fetch cannot fire)', async () => {
        wrapper = await mountComponent();
        await switchToActivityTab(wrapper);

        expect(findActivityTable(wrapper).exists()).toBe(false);
      });
    });

    describe('member role (entitled plan)', () => {
      // Backend materializes membership entitlements as plan ∩ role and
      // audit_logs is admin-tier, so a plain member is 403'd server-side even
      // on an entitled plan. The UI must show the role notice — not the
      // upgrade prompt, and never mount the table (whose fetch would 403).
      beforeEach(() => {
        mockEntitlements.value = ['manage_members', 'audit_logs'];
        mockFetchOrganization.mockResolvedValue({
          ...mockOrganization,
          current_user_role: 'member',
        });
      });

      it('shows the role notice instead of the table or upgrade prompt', async () => {
        wrapper = await mountComponent();
        await switchToActivityTab(wrapper);

        const panel = findPanel(wrapper);
        expect(panel.find('[data-testid="org-audit-role-notice"]').exists()).toBe(true);
        expect(panel.text()).toContain('web.organizations.audit.role_required');
        expect(panel.text()).not.toContain('web.organizations.audit.upgrade_prompt');
        expect(findActivityTable(wrapper).exists()).toBe(false);
      });
    });
  });
});
