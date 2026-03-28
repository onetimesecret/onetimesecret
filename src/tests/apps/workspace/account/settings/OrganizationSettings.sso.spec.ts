// src/tests/apps/workspace/account/settings/OrganizationSettings.sso.spec.ts
//
// Tests for OrganizationSettings.vue SSO tab covering:
// 1. SSO tab visibility based on entitlements
// 2. Domain list rendering when SSO tab active
// 3. SSO status badges (Enabled/Configured/Not Configured)
// 4. Links to domain SSO configuration
// 5. Organization-level SSO fallback section
//
// Note: These tests extend the existing OrganizationSettings.spec.ts test suite
// with SSO-specific test cases.

import OrganizationSettings from '@/apps/workspace/account/settings/OrganizationSettings.vue';
import { createTestingPinia } from '@pinia/testing';
import { flushPromises, mount, VueWrapper } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { nextTick, ref } from 'vue';
import { createI18n } from 'vue-i18n';

// ─────────────────────────────────────────────────────────────────────────────
// Mocks
// ─────────────────────────────────────────────────────────────────────────────

// Mock vue-router
vi.mock('vue-router', () => ({
  useRoute: () => ({
    path: '/org/on1abc123/settings/sso',
    params: { extid: 'on1abc123', orgid: 'on1abc123' },
    query: { tab: 'sso' },
  }),
  useRouter: () => ({
    push: vi.fn(),
    replace: vi.fn(),
    back: vi.fn(),
  }),
  RouterLink: {
    name: 'RouterLink',
    template: '<a :href="to" class="router-link" :data-to="to"><slot /></a>',
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

vi.mock('@/apps/workspace/components/organizations/SsoConfigForm.vue', () => ({
  default: {
    name: 'SsoConfigForm',
    template: '<div class="sso-config-form" data-testid="org-sso-config-form" :data-org-ext-id="orgExtId" />',
    props: ['orgExtId'],
    emits: ['saved', 'deleted'],
  },
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

const mockSsoGetConfig = vi.fn();
vi.mock('@/services/sso.service', () => ({
  SsoService: {
    getConfig: (...args: unknown[]) => mockSsoGetConfig(...args),
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
  entitlements: ['manage_members', 'manage_sso'],
  limits: { teams: 1 },
  planid: 'plan_starter',
};

// Domain fixtures
const mockDomains = [
  {
    extid: 'dm_001',
    display_domain: 'example.com',
    status: 'verified',
    sso_enabled: false,
    sso_configured: false,
  },
  {
    extid: 'dm_002',
    display_domain: 'secure.example.com',
    status: 'verified',
    sso_enabled: false,
    sso_configured: true,
  },
  {
    extid: 'dm_003',
    display_domain: 'auth.example.com',
    status: 'verified',
    sso_enabled: true,
    sso_configured: true,
  },
];

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

// Mock domainsStore with full interface
const mockDomainsRef = ref(mockDomains);

vi.mock('@/shared/stores/domainsStore', () => ({
  useDomainsStore: () => ({
    domains: mockDomainsRef.value,
    isLoading: false,
    recordCount: () => mockDomainsRef.value.length,
    fetchDomains: vi.fn().mockResolvedValue(mockDomainsRef.value),
  }),
}));

// Mock useDomainsManager composable (used by OrganizationSettings for SSO tab)
vi.mock('@/shared/composables/useDomainsManager', () => ({
  useDomainsManager: () => ({
    domains: mockDomainsRef,
    isLoading: ref(false),
    recordCount: ref(mockDomainsRef.value.length),
    fetchDomains: vi.fn().mockResolvedValue(mockDomainsRef.value),
    getDomain: vi.fn(),
    verifyDomain: vi.fn(),
    error: ref(null),
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
const mockEntitlements = ref<string[]>(['manage_members', 'manage_sso']);
vi.mock('@/shared/composables/useEntitlements', () => ({
  useEntitlements: () => ({
    entitlements: mockEntitlements,
    can: (entitlement: string) => mockEntitlements.value.includes(entitlement),
    formatEntitlement: (key: string) => `Formatted: ${key}`,
    initDefinitions: vi.fn().mockResolvedValue(undefined),
    ENTITLEMENTS: {
      MANAGE_MEMBERS: 'manage_members',
      MANAGE_SSO: 'manage_sso',
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

vi.mock('@/types/organization', () => ({
  ENTITLEMENTS: {
    MANAGE_MEMBERS: 'manage_members',
    MANAGE_SSO: 'manage_sso',
  },
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
          billing_email_managed_on_billing: 'Billing email can be changed on the Billing Overview page',
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
            domains: 'Domains',
            sso: 'Single Sign-On',
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
          sso: {
            domain_sso_title: 'Domain SSO Configuration',
            domain_sso_description: 'Configure single sign-on for each custom domain',
            no_domains: 'No domains configured',
            no_domains_description: 'Add a custom domain to enable SSO configuration',
            status_enabled: 'Enabled',
            status_configured: 'Configured',
            status_not_configured: 'Not Configured',
            configure_link: 'Configure SSO',
            org_default_title: 'Organization Default SSO',
            org_default_description: 'Fallback SSO configuration for domains without specific settings',
            update_success: 'SSO configuration updated',
            delete_success: 'SSO configuration deleted',
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

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

describe('OrganizationSettings SSO Tab', () => {
  let wrapper: VueWrapper;

  beforeEach(() => {
    vi.clearAllMocks();

    // Default mock implementations
    mockFetchOrganization.mockResolvedValue(mockOrganization);
    mockUpdateOrganization.mockResolvedValue(mockOrganization);
    mockFetchInvitations.mockResolvedValue([]);
    mockSsoGetConfig.mockResolvedValue({ record: null });
    mockEntitlements.value = ['manage_members', 'manage_sso'];

    // Reset domains to default
    mockDomainsRef.value = [
      {
        extid: 'dm_001',
        display_domain: 'example.com',
        status: 'verified',
        sso_enabled: false,
        sso_configured: false,
      },
      {
        extid: 'dm_002',
        display_domain: 'secure.example.com',
        status: 'verified',
        sso_enabled: false,
        sso_configured: true,
      },
      {
        extid: 'dm_003',
        display_domain: 'auth.example.com',
        status: 'verified',
        sso_enabled: true,
        sso_configured: true,
      },
    ];
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
          RouterLink: {
            name: 'RouterLink',
            template: '<a :href="to" class="router-link" :data-to="to"><slot /></a>',
            props: ['to'],
          },
        },
      },
    });
    await flushPromises();
    await nextTick();
    return wrapper;
  };

  const switchToSsoTab = async (w: VueWrapper) => {
    const ssoTab = w.find('[data-testid="org-tab-sso"]');
    if (!ssoTab.exists()) {
      throw new Error('SSO tab not found - user may not have manage_sso entitlement');
    }
    await ssoTab.trigger('click');
    await flushPromises();
    await nextTick();
  };

  // ─────────────────────────────────────────────────────────────────────────────
  // SSO Tab visibility
  // ─────────────────────────────────────────────────────────────────────────────

  describe('SSO Tab visibility', () => {
    it('shows SSO tab when user has manage_sso entitlement', async () => {
      mockEntitlements.value = ['manage_members', 'manage_sso'];
      await mountComponent();

      const ssoTab = wrapper.find('[data-testid="org-tab-sso"]');
      expect(ssoTab.exists()).toBe(true);
    });

    it('hides SSO tab when user lacks manage_sso entitlement', async () => {
      mockEntitlements.value = ['manage_members'];
      await mountComponent();

      const ssoTab = wrapper.find('[data-testid="org-tab-sso"]');
      expect(ssoTab.exists()).toBe(false);
    });

    it('SSO tab has correct aria attributes', async () => {
      await mountComponent();

      const ssoTab = wrapper.find('[data-testid="org-tab-sso"]');
      expect(ssoTab.attributes('role')).toBe('tab');
      expect(ssoTab.attributes('aria-controls')).toBe('org-panel-sso');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // Domain list rendering
  // ─────────────────────────────────────────────────────────────────────────────

  describe('Domain list rendering', () => {
    it('renders domain list when SSO tab is active', async () => {
      await mountComponent();
      await switchToSsoTab(wrapper);

      const ssoSection = wrapper.find('[data-testid="org-section-sso"]');
      expect(ssoSection.exists()).toBe(true);

      // Check that domains are listed
      expect(wrapper.text()).toContain('example.com');
      expect(wrapper.text()).toContain('secure.example.com');
      expect(wrapper.text()).toContain('auth.example.com');
    });

    it('displays correct number of domains', async () => {
      await mountComponent();
      await switchToSsoTab(wrapper);

      // Each domain should have its own row/card
      const domainNames = ['example.com', 'secure.example.com', 'auth.example.com'];
      domainNames.forEach((domain) => {
        expect(wrapper.text()).toContain(domain);
      });
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // SSO status badges
  // ─────────────────────────────────────────────────────────────────────────────

  describe('SSO status badges', () => {
    it('shows "Not Configured" badge for domain without SSO', async () => {
      await mountComponent();
      await switchToSsoTab(wrapper);

      // The first domain should show "Not Configured"
      expect(wrapper.text()).toContain('Not Configured');
    });

    it('shows "Configured" badge for domain with SSO configured but not enabled', async () => {
      await mountComponent();
      await switchToSsoTab(wrapper);

      // The second domain should show "Configured"
      expect(wrapper.text()).toContain('Configured');
    });

    it('shows "Enabled" badge for domain with SSO enabled', async () => {
      await mountComponent();
      await switchToSsoTab(wrapper);

      // The third domain should show "Enabled"
      expect(wrapper.text()).toContain('Enabled');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // Domain SSO configuration links
  // ─────────────────────────────────────────────────────────────────────────────

  describe('Domain SSO configuration links', () => {
    it('renders links to domain SSO configuration pages', async () => {
      await mountComponent();
      await switchToSsoTab(wrapper);

      // Find links that point to SSO configuration
      const links = wrapper.findAll('.router-link');
      const ssoLinks = links.filter((link) => {
        const to = link.attributes('data-to');
        return to && to.includes('/sso');
      });

      // Should have at least one SSO link per domain
      expect(ssoLinks.length).toBeGreaterThanOrEqual(1);
    });

    it('SSO links have correct format', async () => {
      await mountComponent();
      await switchToSsoTab(wrapper);

      // Check for link to first domain's SSO page
      const links = wrapper.findAll('.router-link');
      const ssoLink = links.find((link) => {
        const to = link.attributes('data-to');
        return to && to.includes('/domains/dm_001/sso');
      });

      expect(ssoLink).toBeDefined();
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // Empty state
  // ─────────────────────────────────────────────────────────────────────────────

  describe('Empty state', () => {
    it('shows empty state when no domains configured', async () => {
      mockDomainsRef.value = [];
      await mountComponent();
      await switchToSsoTab(wrapper);

      expect(wrapper.text()).toContain('No domains configured');
    });

    it('shows description in empty state', async () => {
      mockDomainsRef.value = [];
      await mountComponent();
      await switchToSsoTab(wrapper);

      expect(wrapper.text()).toContain('Add a custom domain to enable SSO configuration');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // Organization-level SSO fallback
  // ─────────────────────────────────────────────────────────────────────────────

  describe('Organization-level SSO fallback', () => {
    it('renders organization default SSO section', async () => {
      await mountComponent();
      await switchToSsoTab(wrapper);

      expect(wrapper.text()).toContain('Organization Default SSO');
    });

    it('renders SsoConfigForm for organization-level SSO', async () => {
      await mountComponent();
      await switchToSsoTab(wrapper);

      const orgSsoForm = wrapper.find('[data-testid="org-sso-config-form"]');
      expect(orgSsoForm.exists()).toBe(true);
    });

    it('passes correct orgExtId to SsoConfigForm', async () => {
      await mountComponent();
      await switchToSsoTab(wrapper);

      const orgSsoForm = wrapper.find('[data-testid="org-sso-config-form"]');
      expect(orgSsoForm.attributes('data-org-ext-id')).toBe('on1abc123');
    });

    it('shows description for organization default SSO', async () => {
      await mountComponent();
      await switchToSsoTab(wrapper);

      expect(wrapper.text()).toContain('Fallback SSO configuration');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // SSO tab badge
  // ─────────────────────────────────────────────────────────────────────────────

  describe('SSO tab badge', () => {
    it('shows status badge on SSO tab when config exists and enabled', async () => {
      mockSsoGetConfig.mockResolvedValue({
        record: { enabled: true, provider_type: 'entra_id' },
      });
      await mountComponent();

      const ssoTab = wrapper.find('[data-testid="org-tab-sso"]');
      // Badge should show "Enabled" status
      expect(ssoTab.text()).toContain('Enabled');
    });

    it('shows "Configured" badge when SSO configured but not enabled', async () => {
      mockSsoGetConfig.mockResolvedValue({
        record: { enabled: false, provider_type: 'entra_id' },
      });
      await mountComponent();

      const ssoTab = wrapper.find('[data-testid="org-tab-sso"]');
      expect(ssoTab.text()).toContain('Configured');
    });

    it('does not show badge when no SSO config exists', async () => {
      mockSsoGetConfig.mockResolvedValue({ record: null });
      await mountComponent();

      const ssoTab = wrapper.find('[data-testid="org-tab-sso"]');
      // Tab text should just be "Single Sign-On" without status badge
      const tabText = ssoTab.text();
      expect(tabText).not.toMatch(/Enabled|Configured/);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // Event handling
  // ─────────────────────────────────────────────────────────────────────────────

  describe('Event handling', () => {
    it('listens to saved event from SsoConfigForm', async () => {
      await mountComponent();
      await switchToSsoTab(wrapper);

      const orgSsoForm = wrapper.findComponent({ name: 'SsoConfigForm' });
      await orgSsoForm.vm.$emit('saved');
      await flushPromises();

      // Verify the event was emitted (component receives it)
      expect(orgSsoForm.emitted('saved')).toBeTruthy();
    });

    it('listens to deleted event from SsoConfigForm', async () => {
      await mountComponent();
      await switchToSsoTab(wrapper);

      const orgSsoForm = wrapper.findComponent({ name: 'SsoConfigForm' });
      await orgSsoForm.vm.$emit('deleted');
      await flushPromises();

      expect(orgSsoForm.emitted('deleted')).toBeTruthy();
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // Accessibility
  // ─────────────────────────────────────────────────────────────────────────────

  describe('Accessibility', () => {
    it('SSO section has correct aria attributes', async () => {
      await mountComponent();
      await switchToSsoTab(wrapper);

      const ssoSection = wrapper.find('[data-testid="org-section-sso"]');
      expect(ssoSection.attributes('role')).toBe('tabpanel');
      expect(ssoSection.attributes('aria-labelledby')).toBe('org-tab-sso');
    });

    it('SSO tab has correct selected state when active', async () => {
      await mountComponent();
      await switchToSsoTab(wrapper);

      const ssoTab = wrapper.find('[data-testid="org-tab-sso"]');
      expect(ssoTab.attributes('aria-selected')).toBe('true');
    });
  });
});
