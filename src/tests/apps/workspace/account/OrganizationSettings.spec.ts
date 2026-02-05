// src/tests/apps/workspace/account/OrganizationSettings.spec.ts

import OrganizationSettings from '@/apps/workspace/account/settings/OrganizationSettings.vue';
import { createTestingPinia } from '@pinia/testing';
import { flushPromises, mount, VueWrapper } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { nextTick, ref } from 'vue';
import { createI18n } from 'vue-i18n';

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

// Mock services
vi.mock('@/services/billing.service', () => ({
  BillingService: {
    getOverview: vi.fn().mockResolvedValue({
      subscription: null,
      plan: null,
      usage: { teams: 0 },
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
  id: 'org_123',
  extid: 'on1abc123',
  display_name: 'Test Organization',
  description: 'A test organization',
  contact_email: 'billing@example.com',
  is_default: true,
  created: new Date('2024-01-01'),
  updated: new Date('2024-01-01'),
  entitlements: ['manage_members'],
  limits: { teams: 1 },
  planid: 'plan_starter', // Required for billing email field to be visible
};

const mockFetchOrganization = vi.fn();
const mockUpdateOrganization = vi.fn();
const mockFetchInvitations = vi.fn();

vi.mock('@/shared/stores/organizationStore', () => ({
  useOrganizationStore: () => ({
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
    },
  }),
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

// i18n setup
const i18n = createI18n({
  legacy: false,
  locale: 'en',
  messages: {
    en: {
      web: {
        organizations: {
          title: 'Organizations',
          not_found: 'Organization not found',
          load_error: 'Failed to load organization',
          update_success: 'Organization updated',
          update_error: 'Failed to update organization',
          billing_email_updated: 'Billing email updated successfully',
          billing_email_managed_on_billing:
            'Billing email can be changed on the Billing Overview page',
          general_settings: 'General Settings',
          display_name: 'Display Name',
          description: 'Description',
          contact_email: 'Billing Email',
          contact_email_help: 'This email will receive billing notifications',
          billing_coming_soon: 'Billing Coming Soon',
          billing_coming_soon_description: 'Billing features will be available soon',
          tabs: {
            general: 'Settings',
            members: 'Team',
            billing: 'Billing',
          },
          members: {
            member_singular: 'member',
            member_plural: 'members',
            no_members: 'No members yet',
            role_updated: 'Role updated',
            member_removed: 'Member removed',
          },
          invitations: {
            invite_member: 'Invite Member',
            upgrade_to_invite: 'Upgrade to invite members',
            upgrade_prompt: 'Upgrade your plan to invite team members',
            pending_invitations: 'Pending Invitations',
            invite_sent: 'Invitation sent',
            invite_error: 'Failed to send invitation',
            resend: 'Resend',
            revoke: 'Revoke',
            resend_success: 'Invitation resent',
            resend_error: 'Failed to resend invitation',
            revoke_success: 'Invitation revoked',
            revoke_error: 'Failed to revoke invitation',
            email_address: 'Email Address',
            email_placeholder: 'Enter email address',
            role: 'Role',
            roles: {
              member: 'Member',
              admin: 'Admin',
            },
            send_invite: 'Send Invite',
            status: {
              pending: 'Pending',
            },
          },
        },
        billing: {
          overview: {
            view_plans_action: 'View Plans',
            plan_features: 'Plan Features',
            upgrade_plan: 'Upgrade Plan',
            manage_billing: 'Manage Billing',
            view_invoices: 'View Invoices',
            no_entitlements: 'No entitlements',
          },
          subscription: {
            status: 'Subscription Status',
            catalog_name: 'Current Plan',
            team_usage: 'Team Usage',
            teams_used: '{used} of {limit} teams used',
          },
          plans: {
            free_plan: 'Free Plan',
          },
        },
        COMMON: {
          loading: 'Loading...',
          not_set: 'Not set',
          word_edit: 'Edit',
          word_save: 'Save',
          word_cancel: 'Cancel',
          save_changes: 'Save Changes',
          saving: 'Saving...',
          processing: 'Processing...',
        },
      },
    },
  },
});

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
    // Find the Settings tab button (located in the nav tabs area)
    const navTabs = w.find('nav[aria-label="Tabs"]');
    const tabs = navTabs.findAll('button');
    const settingsTab = tabs.find((tab) => tab.text() === 'Settings');
    if (!settingsTab) {
      throw new Error('Settings tab not found');
    }
    await settingsTab.trigger('click');
    await flushPromises();
    await nextTick();
  };

  /**
   * Helper to find the billing email section within the Settings tab
   */
  const findBillingEmailSection = (w: VueWrapper) => {
    // The billing email field has data-testid="org-billing-email-field"
    return w.find('[data-testid="org-billing-email-field"]');
  };

  /**
   * Helper to find the Edit link for billing email (navigates to billing overview)
   */
  const findEditLink = (w: VueWrapper) => {
    return w.find('[data-testid="org-billing-email-edit-link"]');
  };

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
        expect(section.text()).toContain('Billing Email');
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
        expect(editLink.text()).toBe('Edit');
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
        expect(section.text()).toContain('Not set');
      });

      it('shows "Not set" when contact_email is null', async () => {
        const orgWithNullEmail = { ...mockOrganization, contact_email: null };
        mockFetchOrganization.mockResolvedValue(orgWithNullEmail);

        wrapper = await mountComponent();
        await switchToSettingsTab(wrapper);

        const section = findBillingEmailSection(wrapper);
        expect(section.text()).toContain('Not set');
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
        expect(section.text()).toContain('Billing Overview');
      });
    });

    describe('Organization type visibility', () => {
      it('shows billing email field for default organization with paid plan', async () => {
        wrapper = await mountComponent();
        await switchToSettingsTab(wrapper);

        const section = findBillingEmailSection(wrapper);
        expect(section.exists()).toBe(true);
        expect(section.text()).toContain('Billing Email');
      });

      it('shows billing email field for non-default organization with paid plan', async () => {
        const nonDefaultOrg = { ...mockOrganization, is_default: false };
        mockFetchOrganization.mockResolvedValue(nonDefaultOrg);

        wrapper = await mountComponent();
        await switchToSettingsTab(wrapper);

        const section = findBillingEmailSection(wrapper);
        expect(section.exists()).toBe(true);
        expect(section.text()).toContain('Billing Email');
        expect(section.text()).toContain(nonDefaultOrg.contact_email);
      });
    });
  });
});
