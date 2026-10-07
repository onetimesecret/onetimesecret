// src/tests/apps/workspace/components/OrganizationContextBar.spec.ts

import { mount, VueWrapper, flushPromises } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createTestingPinia } from '@pinia/testing';
import { ref } from 'vue';
import OrganizationContextBar from '@/apps/workspace/components/navigation/OrganizationContextBar.vue';
import { useOrganizationStore } from '@/shared/stores/organizationStore';

// Mock child components
vi.mock('@/apps/workspace/components/navigation/DomainContextSwitcher.vue', () => ({
  default: {
    name: 'DomainContextSwitcher',
    template: '<div class="domain-switcher" :data-locked="locked">Domain Switcher</div>',
    props: ['locked'],
  },
}));

vi.mock('@/apps/workspace/components/navigation/OrganizationScopeSwitcher.vue', () => ({
  default: {
    name: 'OrganizationScopeSwitcher',
    template: '<div class="org-switcher" :data-locked="locked">Org Switcher</div>',
    props: ['locked'],
  },
}));

// Mock useScopeSwitcherVisibility composable
const mockShowOrgSwitcher = ref(true);
const mockLockOrgSwitcher = ref(false);
const mockShowDomainSwitcher = ref(true);
const mockLockDomainSwitcher = ref(false);
const mockIsSoloDefaultContext = ref(false);
const mockVisibility = ref<{ organization: string; domain: string }>({
  organization: 'show',
  domain: 'hide',
});

vi.mock('@/shared/composables/useScopeSwitcherVisibility', () => ({
  useScopeSwitcherVisibility: () => ({
    visibility: mockVisibility,
    showOrgSwitcher: mockShowOrgSwitcher,
    lockOrgSwitcher: mockLockOrgSwitcher,
    showDomainSwitcher: mockShowDomainSwitcher,
    lockDomainSwitcher: mockLockDomainSwitcher,
    isSoloDefaultContext: mockIsSoloDefaultContext,
  }),
}));

// Enable the org switcher feature flag so the static-org-name fallback path
// (gated on isOrganizationSwitcherEnabled) can be exercised.
vi.mock('@/utils/features', () => ({
  isOrganizationSwitcherEnabled: () => true,
}));

// Mock axios
vi.mock('axios', () => ({
  default: {
    isCancel: vi.fn().mockReturnValue(false),
  },
}));

describe('OrganizationContextBar', () => {
  let wrapper: VueWrapper;

  const mockOrganization = {
    objid: 'obj_123',
    extid: 'org_123',
    display_name: 'Test Organization',
    description: null,
    owner_id: 'cust_456',
    contact_email: null,
    is_default: false,
    planid: 'free',
    created: Date.now(),
    updated: Date.now(),
  };

  beforeEach(() => {
    vi.clearAllMocks();
    // Reset composable mocks to defaults
    mockShowOrgSwitcher.value = true;
    mockLockOrgSwitcher.value = false;
    mockShowDomainSwitcher.value = true;
    mockLockDomainSwitcher.value = false;
    mockIsSoloDefaultContext.value = false;
    mockVisibility.value = { organization: 'show', domain: 'hide' };
  });

  afterEach(() => {
    if (wrapper) {
      wrapper.unmount();
    }
  });

  // `currentOrganization: null` mounts with no current org; leaving the key out
  // defaults to mockOrganization. `isListFetched` maps onto `_listFetched`,
  // the state the getter of that name reads.
  const mountComponent = (storeState: Record<string, unknown> = {}) => {
    return mount(OrganizationContextBar, {
      global: {
        plugins: [
          createTestingPinia({
            createSpy: vi.fn,
            stubActions: false,
            initialState: {
              organization: {
                organizations: storeState.organizations ?? [mockOrganization],
                currentOrganization:
                  'currentOrganization' in storeState
                    ? storeState.currentOrganization
                    : mockOrganization,
                _listFetched: storeState.isListFetched ?? true,
              },
            },
          }),
        ],
        stubs: {
          RouterLink: {
            template: '<a :href="to"><slot /></a>',
            props: ['to'],
          },
        },
      },
    });
  };

  describe('Visibility Conditions', () => {
    it('renders when loaded, hasOrganizations, and domain switcher visible', async () => {
      mockShowDomainSwitcher.value = true;

      wrapper = mountComponent({
        organizations: [mockOrganization],
        isListFetched: true,
      });

      await flushPromises();

      const domainSwitcher = wrapper.find('.domain-switcher');
      expect(domainSwitcher.exists()).toBe(true);
    });

    it('does not render when hasOrganizations is false', async () => {
      wrapper = mountComponent({
        organizations: [],
        isListFetched: true,
      });

      await flushPromises();

      const domainSwitcher = wrapper.find('.domain-switcher');
      expect(domainSwitcher.exists()).toBe(false);
    });

    it('does not render when domain switcher is hidden', async () => {
      mockShowDomainSwitcher.value = false;

      wrapper = mountComponent({
        organizations: [mockOrganization],
        isListFetched: true,
      });

      await flushPromises();

      const domainSwitcher = wrapper.find('.domain-switcher');
      expect(domainSwitcher.exists()).toBe(false);
    });
  });

  describe('Locked State', () => {
    it('passes locked prop to domain switcher when lockDomainSwitcher is true', async () => {
      mockShowDomainSwitcher.value = true;
      mockLockDomainSwitcher.value = true;

      wrapper = mountComponent({
        organizations: [mockOrganization],
        isListFetched: true,
      });

      await flushPromises();

      const domainSwitcher = wrapper.find('.domain-switcher');
      expect(domainSwitcher.attributes('data-locked')).toBe('true');
    });
  });

  describe('Solo default org context', () => {
    it('hides the static org-name chip when isSoloDefaultContext is true', async () => {
      mockShowOrgSwitcher.value = false;
      mockShowDomainSwitcher.value = true;
      mockIsSoloDefaultContext.value = true;

      wrapper = mountComponent({
        organizations: [mockOrganization],
        currentOrganization: mockOrganization,
        isListFetched: true,
      });

      await flushPromises();

      expect(wrapper.find('[data-testid="org-context-static"]').exists()).toBe(false);
      // The domain switcher still shows for these users.
      expect(wrapper.find('.domain-switcher').exists()).toBe(true);
    });

    it('shows the static org-name chip when the switcher is hidden but context is not solo', async () => {
      mockShowOrgSwitcher.value = false;
      mockShowDomainSwitcher.value = true;
      mockIsSoloDefaultContext.value = false;

      wrapper = mountComponent({
        organizations: [mockOrganization],
        currentOrganization: mockOrganization,
        isListFetched: true,
      });

      await flushPromises();

      expect(wrapper.find('[data-testid="org-context-static"]').exists()).toBe(true);
    });
  });

  // The bootstrap payload normally seeds currentOrganization. When it named
  // none, the bar picks default-then-first once the list is in (#4565). This
  // is a tab-local fallback: it must not write the selection to the server.
  describe('Fallback when no organization is current', () => {
    const personal = {
      ...mockOrganization,
      objid: 'obj_default',
      extid: 'org_default',
      display_name: 'Personal',
      is_default: true,
    };
    const second = { ...mockOrganization, objid: 'obj_456', extid: 'org_456' };

    it('falls back to the default organization', async () => {
      wrapper = mountComponent({
        organizations: [mockOrganization, personal],
        currentOrganization: null,
      });
      await flushPromises();

      expect(useOrganizationStore().currentOrganization?.objid).toBe('obj_default');
    });

    it('falls back to the first organization when none is the default', async () => {
      wrapper = mountComponent({
        organizations: [mockOrganization, second],
        currentOrganization: null,
      });
      await flushPromises();

      expect(useOrganizationStore().currentOrganization?.objid).toBe('obj_123');
    });

    it('does not sync the fallback to the server', async () => {
      wrapper = mountComponent({
        organizations: [mockOrganization, personal],
        currentOrganization: null,
      });
      await flushPromises();

      const store = useOrganizationStore();
      expect(store.setCurrentOrganization).toHaveBeenCalledTimes(1);
      expect(store.selectOrganization).not.toHaveBeenCalled();
    });

    it('leaves an existing current organization alone', async () => {
      wrapper = mountComponent({
        organizations: [mockOrganization, personal],
        currentOrganization: mockOrganization,
      });
      await flushPromises();

      const store = useOrganizationStore();
      expect(store.currentOrganization?.objid).toBe('obj_123');
      expect(store.setCurrentOrganization).not.toHaveBeenCalled();
    });

    it('stays empty when the list is empty', async () => {
      wrapper = mountComponent({ organizations: [], currentOrganization: null });
      await flushPromises();

      const store = useOrganizationStore();
      expect(store.currentOrganization).toBeNull();
      expect(store.setCurrentOrganization).not.toHaveBeenCalled();
    });

    it('fetches the list first when it has not been fetched', async () => {
      wrapper = mountComponent({
        organizations: [],
        currentOrganization: null,
        isListFetched: false,
      });
      await flushPromises();

      // No api is provided here, so the real fetch rejects; the bar logs it
      // and carries on. What matters is that it asked.
      expect(useOrganizationStore().fetchOrganizations).toHaveBeenCalledTimes(1);
    });
  });

  describe('Multiple Organizations', () => {
    it('renders when user has multiple organizations', async () => {
      const multipleOrgs = [
        mockOrganization,
        { ...mockOrganization, extid: 'org_456', name: 'Second Org' },
      ];

      wrapper = mountComponent({
        organizations: multipleOrgs,
        currentOrganization: multipleOrgs[0],
        isListFetched: true,
      });

      await flushPromises();

      const domainSwitcher = wrapper.find('.domain-switcher');
      expect(domainSwitcher.exists()).toBe(true);
    });
  });
});
