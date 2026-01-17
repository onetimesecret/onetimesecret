// src/tests/apps/workspace/account/OrganizationSettings.spec.ts

import { mount, VueWrapper, flushPromises } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createI18n } from 'vue-i18n';
import { createTestingPinia } from '@pinia/testing';
import OrganizationSettings from '@/apps/workspace/account/settings/OrganizationSettings.vue';
import { nextTick, ref } from 'vue';

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
  created_at: new Date('2024-01-01'),
  updated_at: new Date('2024-01-01'),
  entitlements: ['manage_members'],
  limits: { teams: 1 },
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
          general_settings: 'General Settings',
          display_name: 'Display Name',
          description: 'Description',
          contact_email: 'Billing Email',
          contact_email_help: 'This email will receive billing notifications',
          billing_managed_by_default: 'Billing is managed by the default organization',
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
  template: '<a class="router-link"><slot /></a>',
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
    // The billing email section is within the general tab section
    const sections = w.findAll('section');
    const generalSection = sections.find((s) =>
      s.text().includes('General Settings')
    );
    return generalSection;
  };

  /**
   * Helper to find the Edit button for billing email
   */
  const findEditButton = (w: VueWrapper) => {
    const section = findBillingEmailSection(w);
    if (!section) return null;
    // Find the button with text "Edit" that's styled with brand color
    const buttons = section.findAll('button');
    return buttons.find((b) => b.text() === 'Edit');
  };

  /**
   * Helper to enter billing email edit mode
   */
  const enterEditMode = async (w: VueWrapper) => {
    const editButton = findEditButton(w);
    if (!editButton) {
      throw new Error('Edit button not found');
    }
    await editButton.trigger('click');
    await nextTick();
  };

  /**
   * Helper to find Save/Cancel buttons in edit mode
   */
  const findEditModeButtons = (w: VueWrapper) => {
    const section = findBillingEmailSection(w);
    if (!section) return { saveButton: null, cancelButton: null };
    const buttons = section.findAll('button[type="button"]');
    const saveButton = buttons.find((b) => b.text() === 'Save' || b.find('[data-icon-name="arrow-path"]').exists());
    const cancelButton = buttons.find((b) => b.text() === 'Cancel');
    return { saveButton, cancelButton };
  };

  describe('Billing Email Edit Flow', () => {
    describe('Display Mode', () => {
      it('shows current billing email as text', async () => {
        wrapper = await mountComponent();
        await switchToSettingsTab(wrapper);

        const section = findBillingEmailSection(wrapper);
        expect(section).toBeTruthy();
        expect(section!.text()).toContain('billing@example.com');
      });

      it('shows Edit link next to email', async () => {
        wrapper = await mountComponent();
        await switchToSettingsTab(wrapper);

        const editButton = findEditButton(wrapper);
        expect(editButton).toBeTruthy();
        expect(editButton!.text()).toBe('Edit');
      });

      it('shows "Not set" when contact_email is empty', async () => {
        const orgWithoutEmail = { ...mockOrganization, contact_email: '' };
        mockFetchOrganization.mockResolvedValue(orgWithoutEmail);

        wrapper = await mountComponent();
        await switchToSettingsTab(wrapper);

        const section = findBillingEmailSection(wrapper);
        expect(section!.text()).toContain('Not set');
      });

      it('shows "Not set" when contact_email is null', async () => {
        const orgWithNullEmail = { ...mockOrganization, contact_email: null };
        mockFetchOrganization.mockResolvedValue(orgWithNullEmail);

        wrapper = await mountComponent();
        await switchToSettingsTab(wrapper);

        const section = findBillingEmailSection(wrapper);
        expect(section!.text()).toContain('Not set');
      });
    });

    describe('Edit Mode', () => {
      it('clicking Edit shows input field', async () => {
        wrapper = await mountComponent();
        await switchToSettingsTab(wrapper);

        // Verify edit mode is not active
        expect(wrapper.find('#billing-email').exists()).toBe(false);

        // Click edit button
        await enterEditMode(wrapper);

        // Input should now be visible
        const input = wrapper.find('#billing-email');
        expect(input.exists()).toBe(true);
      });

      it('input is pre-populated with current email', async () => {
        wrapper = await mountComponent();
        await switchToSettingsTab(wrapper);
        await enterEditMode(wrapper);

        const input = wrapper.find('#billing-email');
        expect((input.element as HTMLInputElement).value).toBe('billing@example.com');
      });

      it('shows Save and Cancel buttons', async () => {
        wrapper = await mountComponent();
        await switchToSettingsTab(wrapper);
        await enterEditMode(wrapper);

        const { saveButton, cancelButton } = findEditModeButtons(wrapper);

        expect(saveButton).toBeTruthy();
        expect(cancelButton).toBeTruthy();
      });
    });

    describe('Save Behavior', () => {
      it('calls updateOrganization with billing_email', async () => {
        const updatedOrg = { ...mockOrganization, contact_email: 'new-billing@example.com' };
        mockUpdateOrganization.mockResolvedValue(updatedOrg);

        wrapper = await mountComponent();
        await switchToSettingsTab(wrapper);
        await enterEditMode(wrapper);

        // Update input value
        const input = wrapper.find('#billing-email');
        await input.setValue('new-billing@example.com');

        // Click save
        const { saveButton } = findEditModeButtons(wrapper);
        await saveButton?.trigger('click');
        await flushPromises();

        expect(mockUpdateOrganization).toHaveBeenCalledWith('on1abc123', {
          billing_email: 'new-billing@example.com',
        });
      });

      it('exits edit mode on success', async () => {
        const updatedOrg = { ...mockOrganization, contact_email: 'new-billing@example.com' };
        mockUpdateOrganization.mockResolvedValue(updatedOrg);

        wrapper = await mountComponent();
        await switchToSettingsTab(wrapper);
        await enterEditMode(wrapper);

        // Update and save
        const input = wrapper.find('#billing-email');
        await input.setValue('new-billing@example.com');

        const { saveButton } = findEditModeButtons(wrapper);
        await saveButton?.trigger('click');
        await flushPromises();

        // Should exit edit mode - input should no longer exist
        expect(wrapper.find('#billing-email').exists()).toBe(false);
      });

      it('shows success message on save', async () => {
        const updatedOrg = { ...mockOrganization, contact_email: 'new-billing@example.com' };
        mockUpdateOrganization.mockResolvedValue(updatedOrg);

        wrapper = await mountComponent();
        await switchToSettingsTab(wrapper);
        await enterEditMode(wrapper);

        // Update and save
        const input = wrapper.find('#billing-email');
        await input.setValue('new-billing@example.com');

        const { saveButton } = findEditModeButtons(wrapper);
        await saveButton?.trigger('click');
        await flushPromises();

        // Check for success alert
        const section = findBillingEmailSection(wrapper);
        expect(section!.text()).toContain('Billing email updated successfully');
      });

      it('does not call API if email unchanged', async () => {
        wrapper = await mountComponent();
        await switchToSettingsTab(wrapper);
        await enterEditMode(wrapper);

        // Click save without changing value
        const { saveButton } = findEditModeButtons(wrapper);
        await saveButton?.trigger('click');
        await flushPromises();

        // Should NOT call updateOrganization
        expect(mockUpdateOrganization).not.toHaveBeenCalled();
      });

      it('shows error message on save failure', async () => {
        mockUpdateOrganization.mockRejectedValue(new Error('Update failed'));

        wrapper = await mountComponent();
        await switchToSettingsTab(wrapper);
        await enterEditMode(wrapper);

        // Update and save
        const input = wrapper.find('#billing-email');
        await input.setValue('new-billing@example.com');

        const { saveButton } = findEditModeButtons(wrapper);
        await saveButton?.trigger('click');
        await flushPromises();

        // Check for error alert
        const section = findBillingEmailSection(wrapper);
        expect(section!.text()).toContain('Update failed');
      });
    });

    describe('Cancel Behavior', () => {
      it('reverts input to original value', async () => {
        wrapper = await mountComponent();
        await switchToSettingsTab(wrapper);
        await enterEditMode(wrapper);

        // Change input value
        const input = wrapper.find('#billing-email');
        await input.setValue('changed@example.com');
        expect((input.element as HTMLInputElement).value).toBe('changed@example.com');

        // Click cancel
        const { cancelButton } = findEditModeButtons(wrapper);
        await cancelButton?.trigger('click');
        await nextTick();

        // Re-enter edit mode to check value was reverted
        await enterEditMode(wrapper);

        const input2 = wrapper.find('#billing-email');
        expect((input2.element as HTMLInputElement).value).toBe('billing@example.com');
      });

      it('exits edit mode', async () => {
        wrapper = await mountComponent();
        await switchToSettingsTab(wrapper);
        await enterEditMode(wrapper);

        expect(wrapper.find('#billing-email').exists()).toBe(true);

        // Click cancel
        const { cancelButton } = findEditModeButtons(wrapper);
        await cancelButton?.trigger('click');
        await nextTick();

        // Input should no longer exist
        expect(wrapper.find('#billing-email').exists()).toBe(false);
      });
    });

    describe('Keyboard Shortcuts', () => {
      it('Enter key triggers save', async () => {
        const updatedOrg = { ...mockOrganization, contact_email: 'enter-test@example.com' };
        mockUpdateOrganization.mockResolvedValue(updatedOrg);

        wrapper = await mountComponent();
        await switchToSettingsTab(wrapper);
        await enterEditMode(wrapper);

        // Update input and press Enter
        const input = wrapper.find('#billing-email');
        await input.setValue('enter-test@example.com');
        await input.trigger('keyup.enter');
        await flushPromises();

        expect(mockUpdateOrganization).toHaveBeenCalledWith('on1abc123', {
          billing_email: 'enter-test@example.com',
        });
      });

      it('Escape key triggers cancel', async () => {
        wrapper = await mountComponent();
        await switchToSettingsTab(wrapper);
        await enterEditMode(wrapper);

        expect(wrapper.find('#billing-email').exists()).toBe(true);

        // Change value and press Escape
        const input = wrapper.find('#billing-email');
        await input.setValue('should-be-reverted@example.com');
        await input.trigger('keyup.escape');
        await nextTick();

        // Should exit edit mode
        expect(wrapper.find('#billing-email').exists()).toBe(false);
        // updateOrganization should NOT be called
        expect(mockUpdateOrganization).not.toHaveBeenCalled();
      });
    });

    describe('Loading State', () => {
      it('shows spinner during save', async () => {
        // Create a pending promise to hold the save in progress
        let resolveUpdate: (value: unknown) => void;
        const pendingPromise = new Promise((resolve) => {
          resolveUpdate = resolve;
        });
        mockUpdateOrganization.mockReturnValue(pendingPromise);

        wrapper = await mountComponent();
        await switchToSettingsTab(wrapper);
        await enterEditMode(wrapper);

        // Update input and start save
        const input = wrapper.find('#billing-email');
        await input.setValue('new@example.com');

        const { saveButton } = findEditModeButtons(wrapper);
        saveButton?.trigger('click');

        await nextTick();

        // Check for spinner icon (arrow-path with animate-spin)
        const spinner = wrapper.find('[data-icon-name="arrow-path"]');
        expect(spinner.exists()).toBe(true);

        // Resolve the promise
        resolveUpdate!(mockOrganization);
        await flushPromises();
      });

      it('disables buttons during save', async () => {
        let resolveUpdate: (value: unknown) => void;
        const pendingPromise = new Promise((resolve) => {
          resolveUpdate = resolve;
        });
        mockUpdateOrganization.mockReturnValue(pendingPromise);

        wrapper = await mountComponent();
        await switchToSettingsTab(wrapper);
        await enterEditMode(wrapper);

        // Update input and start save
        const input = wrapper.find('#billing-email');
        await input.setValue('new@example.com');

        const { saveButton } = findEditModeButtons(wrapper);
        saveButton?.trigger('click');

        await nextTick();

        // Find buttons in edit mode and check disabled state
        const section = findBillingEmailSection(wrapper);
        const editModeButtons = section!.findAll('button[type="button"]');
        const saveBtnInProgress = editModeButtons.find(
          (b) => b.find('[data-icon-name="arrow-path"]').exists() || b.attributes('disabled') !== undefined
        );
        const cancelBtn = editModeButtons.find((b) => b.text() === 'Cancel');

        // Save and Cancel should be disabled
        expect(saveBtnInProgress?.attributes('disabled')).toBeDefined();
        expect(cancelBtn?.attributes('disabled')).toBeDefined();

        // Resolve the promise
        resolveUpdate!(mockOrganization);
        await flushPromises();
      });
    });

    describe('Billing Email Visibility', () => {
      it('only shows billing email field for default organization', async () => {
        wrapper = await mountComponent();
        await switchToSettingsTab(wrapper);

        // Should show billing email label
        const section = findBillingEmailSection(wrapper);
        expect(section!.text()).toContain('Billing Email');
      });

      it('shows info notice for non-default organization', async () => {
        const nonDefaultOrg = { ...mockOrganization, is_default: false };
        mockFetchOrganization.mockResolvedValue(nonDefaultOrg);

        wrapper = await mountComponent();
        await switchToSettingsTab(wrapper);

        // Should show the info notice instead of billing email field
        const section = findBillingEmailSection(wrapper);
        expect(section!.text()).toContain('Billing is managed by the default organization');
      });
    });
  });
});
