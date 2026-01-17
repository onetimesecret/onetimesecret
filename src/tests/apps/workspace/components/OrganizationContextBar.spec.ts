// src/tests/apps/workspace/components/OrganizationContextBar.spec.ts

import { mount, VueWrapper, flushPromises } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createTestingPinia } from '@pinia/testing';
import { ref } from 'vue';
import OrganizationContextBar from '@/apps/workspace/components/navigation/OrganizationContextBar.vue';

// Mock child components
vi.mock('@/shared/components/navigation/DomainScopeSwitcher.vue', () => ({
  default: {
    name: 'DomainScopeSwitcher',
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

vi.mock('@/shared/composables/useScopeSwitcherVisibility', () => ({
  useScopeSwitcherVisibility: () => ({
    showOrgSwitcher: mockShowOrgSwitcher,
    lockOrgSwitcher: mockLockOrgSwitcher,
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
    mockShowOrgSwitcher.value = true;
    mockLockOrgSwitcher.value = false;
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
    it('renders when loaded, hasOrganizations, and at least one switcher visible', async () => {
      mockShowOrgSwitcher.value = true;
      mockShowDomainSwitcher.value = false;

      wrapper = mountComponent({
        organizations: [mockOrganization],
        isListFetched: true,
      });

      await flushPromises();

      const orgSwitcher = wrapper.find('.org-switcher');
      expect(orgSwitcher.exists()).toBe(true);
    });

    it('does not render when hasOrganizations is false', async () => {
      wrapper = mountComponent({
        organizations: [],
        isListFetched: true,
      });

      await flushPromises();

      const orgSwitcher = wrapper.find('.org-switcher');
      const domainSwitcher = wrapper.find('.domain-switcher');
      expect(orgSwitcher.exists()).toBe(false);
      expect(domainSwitcher.exists()).toBe(false);
    });

    it('does not render when both switchers are hidden', async () => {
      mockShowOrgSwitcher.value = false;
      mockShowDomainSwitcher.value = false;

      wrapper = mountComponent({
        organizations: [mockOrganization],
        isListFetched: true,
      });

      await flushPromises();

      const orgSwitcher = wrapper.find('.org-switcher');
      const domainSwitcher = wrapper.find('.domain-switcher');
      expect(orgSwitcher.exists()).toBe(false);
      expect(domainSwitcher.exists()).toBe(false);
    });

    it('renders only org switcher when domain switcher is hidden', async () => {
      mockShowOrgSwitcher.value = true;
      mockShowDomainSwitcher.value = false;

      wrapper = mountComponent({
        organizations: [mockOrganization],
        isListFetched: true,
      });

      await flushPromises();

      const orgSwitcher = wrapper.find('.org-switcher');
      const domainSwitcher = wrapper.find('.domain-switcher');
      expect(orgSwitcher.exists()).toBe(true);
      expect(domainSwitcher.exists()).toBe(false);
    });

    it('renders only domain switcher when org switcher is hidden', async () => {
      mockShowOrgSwitcher.value = false;
      mockShowDomainSwitcher.value = true;

      wrapper = mountComponent({
        organizations: [mockOrganization],
        isListFetched: true,
      });

      await flushPromises();

      const orgSwitcher = wrapper.find('.org-switcher');
      const domainSwitcher = wrapper.find('.domain-switcher');
      expect(orgSwitcher.exists()).toBe(false);
      expect(domainSwitcher.exists()).toBe(true);
    });
  });

  describe('Separator Logic', () => {
    it('shows separator when both switchers are visible', async () => {
      mockShowOrgSwitcher.value = true;
      mockShowDomainSwitcher.value = true;

      wrapper = mountComponent({
        organizations: [mockOrganization],
        isListFetched: true,
      });

      await flushPromises();

      const separator = wrapper.find('span[aria-hidden="true"]');
      expect(separator.exists()).toBe(true);
      expect(separator.text()).toBe('|');
    });

    it('hides separator when only org switcher is visible', async () => {
      mockShowOrgSwitcher.value = true;
      mockShowDomainSwitcher.value = false;

      wrapper = mountComponent({
        organizations: [mockOrganization],
        isListFetched: true,
      });

      await flushPromises();

      const separator = wrapper.find('span[aria-hidden="true"]');
      expect(separator.exists()).toBe(false);
    });

    it('hides separator when only domain switcher is visible', async () => {
      mockShowOrgSwitcher.value = false;
      mockShowDomainSwitcher.value = true;

      wrapper = mountComponent({
        organizations: [mockOrganization],
        isListFetched: true,
      });

      await flushPromises();

      const separator = wrapper.find('span[aria-hidden="true"]');
      expect(separator.exists()).toBe(false);
    });
  });

  describe('Locked State', () => {
    it('passes locked prop to org switcher when lockOrgSwitcher is true', async () => {
      mockShowOrgSwitcher.value = true;
      mockLockOrgSwitcher.value = true;
      mockShowDomainSwitcher.value = false;

      wrapper = mountComponent({
        organizations: [mockOrganization],
        isListFetched: true,
      });

      await flushPromises();

      const orgSwitcher = wrapper.find('.org-switcher');
      expect(orgSwitcher.attributes('data-locked')).toBe('true');
    });

    it('passes locked prop to domain switcher when lockDomainSwitcher is true', async () => {
      mockShowOrgSwitcher.value = false;
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

      const orgSwitcher = wrapper.find('.org-switcher');
      expect(orgSwitcher.exists()).toBe(true);
    });
  });

  describe('Accessibility', () => {
    it('separator has aria-hidden="true"', async () => {
      mockShowOrgSwitcher.value = true;
      mockShowDomainSwitcher.value = true;

      wrapper = mountComponent({
        organizations: [mockOrganization],
        isListFetched: true,
      });

      await flushPromises();

      const separator = wrapper.find('span[aria-hidden="true"]');
      expect(separator.exists()).toBe(true);
    });
  });
});
