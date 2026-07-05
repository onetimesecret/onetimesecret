// src/tests/components/DomainHeader.spec.ts

import { mount, RouterLinkStub } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import DomainHeader from '@/apps/workspace/components/dashboard/DomainHeader.vue';
import type { CustomDomain } from '@/schemas/shapes/v3';
import { isApproximatedDomainValidation } from '@/utils/features';
import { ref } from 'vue';

// Control the install's domain validation strategy. Default to approximated so
// the status-badge assertions hold; the dedicated block flips it off.
vi.mock('@/utils/features', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/utils/features')>()),
  isApproximatedDomainValidation: vi.fn(() => true),
}));
const mockApprox = vi.mocked(isApproximatedDomainValidation);

// Use refs for reactive mocks that can change between tests
const mockStatusIcon = ref('check-circle');
const mockStatusColor = ref('text-emerald-600 dark:text-emerald-400');
const mockDisplayStatus = ref('Active');
const mockIsActive = ref(true);

vi.mock('@/shared/composables/useDomainStatus', () => ({
  useDomainStatus: vi.fn(() => ({
    statusIcon: mockStatusIcon,
    statusColor: mockStatusColor,
    displayStatus: mockDisplayStatus,
    isActive: mockIsActive,
  })),
}));

vi.mock('vue-i18n', () => ({
  useI18n: vi.fn(() => ({
    t: vi.fn((key: string) => {
      const translations: Record<string, string> = {
        'web.domains.open_domain_in_new_tab': 'Open domain in new tab',
        'web.domains.view_domain_verification_status': 'View domain verification status',
      };
      return translations[key] ?? key;
    }),
  })),
}));

describe('DomainHeader', () => {
  const createMockDomain = (overrides: Partial<CustomDomain> = {}): CustomDomain => ({
    extid: 'domain-123',
    custid: 'cust-456',
    display_domain: 'example.com',
    base_domain: 'example.com',
    subdomain: '',
    trd: '',
    tld: 'com',
    sld: 'example',
    is_apex: true,
    created: 1700000000,
    updated: 1700000000,
    vhost: {
      status: 'ACTIVE',
      last_monitored_unix: 123,
    },
    vhost_fetch_failed_at: null,
    ...overrides,
  });

  const defaultProps = {
    domain: null as CustomDomain | null,
    hasUnsavedChanges: false,
    orgid: 'org-123',
  };

  beforeEach(() => {
    // Reset mock values to defaults
    mockStatusIcon.value = 'check-circle';
    mockStatusColor.value = 'text-emerald-600 dark:text-emerald-400';
    mockDisplayStatus.value = 'Active';
    mockIsActive.value = true;
    // Default to approximated (status badge visible).
    mockApprox.mockReturnValue(true);
  });

  function mountComponent(props: Partial<typeof defaultProps> = {}) {
    return mount(DomainHeader, {
      props: { ...defaultProps, ...props },
      global: {
        stubs: {
          RouterLink: RouterLinkStub,
          OIcon: {
            template: '<span class="mock-icon" :class="$attrs.class" :data-name="name"></span>',
            props: ['collection', 'name'],
          },
        },
      },
    });
  }

  describe('loading state', () => {
    it('shows loading placeholder when domain is null', () => {
      const wrapper = mountComponent({ domain: null });
      expect(wrapper.find('.animate-pulse').exists()).toBe(true);
      expect(wrapper.find('h1').exists()).toBe(false);
    });

    it('shows domain content when domain is provided', () => {
      const domain = createMockDomain();
      const wrapper = mountComponent({ domain });
      expect(wrapper.find('.animate-pulse').exists()).toBe(false);
      expect(wrapper.find('h1').exists()).toBe(true);
    });
  });

  describe('domain display', () => {
    it('displays the domain name', () => {
      const domain = createMockDomain({ display_domain: 'test.example.com' });
      const wrapper = mountComponent({ domain });
      expect(wrapper.find('h1 span').text()).toBe('test.example.com');
    });

    it('displays status icon with name from composable', () => {
      mockStatusIcon.value = 'help-circle';
      const domain = createMockDomain();
      const wrapper = mountComponent({ domain });

      const statusIcon = wrapper.find('[data-name="help-circle"]');
      expect(statusIcon.exists()).toBe(true);
    });

    it('displays status text', () => {
      mockDisplayStatus.value = 'Unverified';
      const domain = createMockDomain();
      const wrapper = mountComponent({ domain });
      expect(wrapper.text()).toContain('Unverified');
    });
  });

  describe('external link', () => {
    it('constructs correct URL without externalPath', () => {
      const domain = createMockDomain({ display_domain: 'example.com' });
      const wrapper = mountComponent({ domain });
      const link = wrapper.find('a[target="_blank"]');
      expect(link.attributes('href')).toBe('https://example.com');
    });

    it('constructs correct URL with externalPath prop', () => {
      const domain = createMockDomain({ display_domain: 'example.com' });
      const wrapper = mountComponent({ domain, externalPath: '/incoming' } as any);
      const link = wrapper.find('a[target="_blank"]');
      expect(link.attributes('href')).toBe('https://example.com/incoming');
    });

    // The external link is ALWAYS visible since e42617e ([#3383] "always
    // show domain icon" — the showExternalLink computed and its v-show were
    // removed). These cases pin that contract across the two conditions
    // that previously hid it.

    it('keeps external link visible when hasUnsavedChanges is true', () => {
      const domain = createMockDomain();
      const wrapper = mountComponent({ domain, hasUnsavedChanges: true });
      const link = wrapper.find('a[target="_blank"]');
      expect(link.isVisible()).toBe(true);
    });

    it('shows external link when hasUnsavedChanges is false and domain is active', () => {
      const domain = createMockDomain();
      const wrapper = mountComponent({ domain, hasUnsavedChanges: false, externalPath: '/incoming' } as any);
      const link = wrapper.find('a[target="_blank"]');
      expect(link.isVisible()).toBe(true);
    });

    it('keeps external link visible when the domain is not active', () => {
      mockIsActive.value = false;
      mockDisplayStatus.value = 'Pending';
      mockStatusIcon.value = 'close-circle';
      const domain = createMockDomain();
      const wrapper = mountComponent({ domain, hasUnsavedChanges: false });
      const link = wrapper.find('a[target="_blank"]');
      expect(link.isVisible()).toBe(true);
    });
  });

  describe('verify route link', () => {
    it('links to correct verify route', () => {
      const domain = createMockDomain({ extid: 'domain-xyz' });
      const wrapper = mountComponent({ domain, orgid: 'org-abc' });
      const routerLink = wrapper.findComponent(RouterLinkStub);
      expect(routerLink.props('to')).toBe('/org/org-abc/domains/domain-xyz/verify');
    });
  });

  describe('validation strategy gating', () => {
    it('shows the status badge when validation strategy is approximated', () => {
      mockApprox.mockReturnValue(true);
      const domain = createMockDomain();
      const wrapper = mountComponent({ domain });

      // Badge renders its status icon and a RouterLink to the verify page.
      expect(wrapper.find('[data-name="check-circle"]').exists()).toBe(true);
      expect(wrapper.findComponent(RouterLinkStub).exists()).toBe(true);
    });

    it('hides the status badge when validation strategy is not approximated', () => {
      mockApprox.mockReturnValue(false);
      const domain = createMockDomain();
      const wrapper = mountComponent({ domain });

      // No status icon, no verify RouterLink — only the external-link anchor remains.
      expect(wrapper.find('[data-name="check-circle"]').exists()).toBe(false);
      expect(wrapper.findComponent(RouterLinkStub).exists()).toBe(false);
      // The domain name + external link are still rendered.
      expect(wrapper.find('h1').exists()).toBe(true);
      expect(wrapper.find('a[target="_blank"]').exists()).toBe(true);
    });
  });

  describe('statusColor integration', () => {
    // Note: These tests verify the composable integration works by checking
    // that useDomainStatus is called and its values are used in rendering.
    // The actual color classes are tested in useDomainStatus.spec.ts.

    it('uses statusColor from composable for icon styling', () => {
      mockStatusColor.value = 'text-emerald-600 dark:text-emerald-400';
      mockStatusIcon.value = 'check-circle';
      const domain = createMockDomain();
      const wrapper = mountComponent({ domain });

      // Verify the icon is rendered (composable integration works)
      const icon = wrapper.find('[data-name="check-circle"]');
      expect(icon.exists()).toBe(true);
    });

    it('uses different icon for stale status', () => {
      mockStatusIcon.value = 'help-circle';
      mockStatusColor.value = 'text-amber-500 dark:text-amber-400';
      const domain = createMockDomain();
      const wrapper = mountComponent({ domain });

      const icon = wrapper.find('[data-name="help-circle"]');
      expect(icon.exists()).toBe(true);
    });

    it('uses close-circle icon for error status', () => {
      mockStatusIcon.value = 'close-circle';
      mockStatusColor.value = 'text-rose-600 dark:text-rose-500';
      const domain = createMockDomain();
      const wrapper = mountComponent({ domain });

      const icon = wrapper.find('[data-name="close-circle"]');
      expect(icon.exists()).toBe(true);
    });
  });
});
