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

// Mock useScopeSwitcherVisibility composable
const mockShowDomainSwitcher = ref(true);
const mockLockDomainSwitcher = ref(false);

vi.mock('@/shared/composables/useScopeSwitcherVisibility', () => ({
  useScopeSwitcherVisibility: () => ({
    showDomainSwitcher: mockShowDomainSwitcher,
    lockDomainSwitcher: mockLockDomainSwitcher,
  }),
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
    extid: 'org_123',
    name: 'Test Organization',
    created: Date.now(),
    objid: 'obj_123',
  };

  beforeEach(() => {
    vi.clearAllMocks();
    // Reset composable mocks to defaults
    mockShowDomainSwitcher.value = true;
    mockLockDomainSwitcher.value = false;
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
