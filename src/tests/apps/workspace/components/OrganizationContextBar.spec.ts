// src/tests/apps/workspace/components/OrganizationContextBar.spec.ts

import { mount, VueWrapper, flushPromises } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createTestingPinia } from '@pinia/testing';
import { ref } from 'vue';
import OrganizationContextBar from '@/apps/workspace/components/navigation/OrganizationContextBar.vue';

// Mock child components
vi.mock('@/shared/components/navigation/DomainContextSwitcher.vue', () => ({
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
                currentOrganization: storeState.currentOrganization ?? mockOrganization,
                isListFetched: storeState.isListFetched ?? true,
              },
            },
          }),
        ],
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
