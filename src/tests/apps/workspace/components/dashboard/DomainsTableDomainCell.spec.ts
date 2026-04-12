// src/tests/apps/workspace/components/dashboard/DomainsTableDomainCell.spec.ts

import { mount } from '@vue/test-utils';
import { describe, it, expect, vi, afterEach, beforeEach } from 'vitest';
import DomainsTableDomainCell from '@/apps/workspace/components/dashboard/DomainsTableDomainCell.vue';

// Mock vue-i18n
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key: string) => key,
  }),
}));

// Mock date-fns to avoid locale issues in tests
vi.mock('date-fns', () => ({
  formatDistanceToNow: () => '3 days ago',
}));

// Mock DomainVerificationInfo child component
vi.mock('@/apps/workspace/components/domains/DomainVerificationInfo.vue', () => ({
  default: {
    name: 'DomainVerificationInfo',
    template: '<div class="domain-verification-info" data-testid="verification-info" />',
    props: ['mode', 'domain', 'orgid'],
  },
}));

// Mock OIcon component
vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="o-icon" :data-icon-name="name" :data-collection="collection" />',
    props: ['collection', 'name', 'class'],
  },
}));

// Mock useDomainStatus composable
const mockUseDomainStatus = vi.fn();
vi.mock('@/shared/composables/useDomainStatus', () => ({
  useDomainStatus: () => mockUseDomainStatus(),
}));

const mockDomain = {
  identifier: 'domain-123',
  extid: 'dm-test-extid',
  domainid: 'dom_123',
  custid: 'cust_123',
  display_domain: 'test.example.com',
  base_domain: 'example.com',
  subdomain: 'test',
  trd: 'test',
  tld: 'com',
  sld: 'example',
  is_apex: false,
  verified: false,
  txt_validation_host: '_challenge.test',
  txt_validation_value: 'verify123',
  vhost: null,
  brand: null,
  created: new Date('2024-01-01'),
  updated: new Date('2024-01-01'),
};

function mountComponent(options: { canEmailConfig?: boolean; domainOverrides?: object } = {}) {
  return mount(DomainsTableDomainCell, {
    props: {
      domain: { ...mockDomain, ...(options.domainOverrides || {}) },
      orgid: 'org_ext_123',
      canEmailConfig: options.canEmailConfig ?? false,
    },
    global: {
      stubs: {
        RouterLink: {
          name: 'RouterLink',
          template: '<a :data-to="JSON.stringify(to)" :class="$attrs.class"><slot /></a>',
          props: ['to'],
        },
      },
    },
  });
}

describe('DomainsTableDomainCell', () => {
  beforeEach(() => {
    // Default: no warning or error (verified state)
    mockUseDomainStatus.mockReturnValue({
      isWarning: false,
      isError: false,
      displayStatus: 'Verified',
    });
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  describe('domain name link', () => {
    it('always routes the display-domain link to DomainDetail', () => {
      const wrapper = mountComponent();

      const link = wrapper.find('a[data-to]');
      const to = JSON.parse(link.attributes('data-to')!);

      expect(to.name).toBe('DomainDetail');
      expect(to.params).toEqual({
        orgid: 'org_ext_123',
        extid: 'dm-test-extid',
      });
      expect(link.text()).toBe('test.example.com');
    });
  });

  describe('DNS warning/error states (UI consistency)', () => {
    it('shows clickable warning link when isWarning is true', () => {
      mockUseDomainStatus.mockReturnValue({
        isWarning: true,
        isError: false,
        displayStatus: 'DNS Check Required',
      });

      const wrapper = mountComponent();

      // Should show warning link
      const warningLink = wrapper.find('.text-amber-600');
      expect(warningLink.exists()).toBe(true);
      expect(warningLink.text()).toContain('DNS Check Required');
    });

    it('shows clickable warning link when isError is true', () => {
      mockUseDomainStatus.mockReturnValue({
        isWarning: false,
        isError: true,
        displayStatus: 'DNS Error',
      });

      const wrapper = mountComponent();

      // Should show error link (same amber styling)
      const errorLink = wrapper.find('.text-amber-600');
      expect(errorLink.exists()).toBe(true);
      expect(errorLink.text()).toContain('DNS Error');
    });

    it('warning link routes to verify page', () => {
      mockUseDomainStatus.mockReturnValue({
        isWarning: true,
        isError: false,
        displayStatus: 'DNS Check Required',
      });

      const wrapper = mountComponent();

      const warningLink = wrapper.find('.text-amber-600');
      const to = warningLink.attributes('data-to');
      expect(to).toBe('"/org/org_ext_123/domains/dm-test-extid/verify"');
    });

    it('shows alert icon in warning state', () => {
      mockUseDomainStatus.mockReturnValue({
        isWarning: true,
        isError: false,
        displayStatus: 'DNS Check Required',
      });

      const wrapper = mountComponent();

      const alertIcon = wrapper.find('[data-icon-name="alert-circle"]');
      expect(alertIcon.exists()).toBe(true);
    });

    it('hides DomainVerificationInfo when in warning/error state', () => {
      mockUseDomainStatus.mockReturnValue({
        isWarning: true,
        isError: false,
        displayStatus: 'DNS Check Required',
      });

      const wrapper = mountComponent();

      // Should NOT show the verification info component
      const verificationInfo = wrapper.find('[data-testid="verification-info"]');
      expect(verificationInfo.exists()).toBe(false);
    });

    it('shows DomainVerificationInfo when no warning/error', () => {
      mockUseDomainStatus.mockReturnValue({
        isWarning: false,
        isError: false,
        displayStatus: 'Verified',
      });

      const wrapper = mountComponent();

      // Should show the verification info component
      const verificationInfo = wrapper.find('[data-testid="verification-info"]');
      expect(verificationInfo.exists()).toBe(true);
    });

    it('hides age timestamp when in warning/error state', () => {
      mockUseDomainStatus.mockReturnValue({
        isWarning: true,
        isError: false,
        displayStatus: 'DNS Check Required',
      });

      const wrapper = mountComponent();

      // Should NOT show age timestamp (which uses 3 days ago from mock)
      expect(wrapper.text()).not.toContain('3 days ago');
    });

    it('shows age timestamp when no warning/error', () => {
      mockUseDomainStatus.mockReturnValue({
        isWarning: false,
        isError: false,
        displayStatus: 'Verified',
      });

      const wrapper = mountComponent();

      // Should show the i18n key for age (which contains formatDistanceToNow)
      // The actual rendered text will use i18n interpolation with the mocked date-fns
      expect(wrapper.text()).toContain('web.domains.added_formatdistancetonow_domain_created_addsuffix_true');
    });
  });
});
