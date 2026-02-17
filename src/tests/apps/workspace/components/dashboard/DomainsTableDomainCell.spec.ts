// src/tests/apps/workspace/components/dashboard/DomainsTableDomainCell.spec.ts

import { mount } from '@vue/test-utils';
import { describe, it, expect, vi, afterEach } from 'vitest';
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
    template: '<div class="domain-verification-info" />',
    props: ['mode', 'domain', 'orgid'],
  },
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

function mountComponent(canBrand = false) {
  return mount(DomainsTableDomainCell, {
    props: {
      domain: mockDomain,
      orgid: 'org_ext_123',
      canBrand,
    },
    global: {
      stubs: {
        RouterLink: {
          name: 'RouterLink',
          template: '<a :data-to="JSON.stringify(to)"><slot /></a>',
          props: ['to'],
        },
      },
    },
  });
}

describe('DomainsTableDomainCell', () => {
  afterEach(() => {
    vi.clearAllMocks();
  });

  describe('canBrand routing', () => {
    it('links to DomainVerify when canBrand is false', () => {
      const wrapper = mountComponent(false);

      const link = wrapper.find('a[data-to]');
      const to = JSON.parse(link.attributes('data-to')!);

      expect(to.name).toBe('DomainVerify');
      expect(to.params).toEqual({
        orgid: 'org_ext_123',
        extid: 'dm-test-extid',
      });
    });

    it('links to DomainBrand when canBrand is true', () => {
      const wrapper = mountComponent(true);

      const link = wrapper.find('a[data-to]');
      const to = JSON.parse(link.attributes('data-to')!);

      expect(to.name).toBe('DomainBrand');
      expect(to.params).toEqual({
        orgid: 'org_ext_123',
        extid: 'dm-test-extid',
      });
    });

    it('displays the domain name regardless of canBrand', () => {
      const withoutBrand = mountComponent(false);
      const withBrand = mountComponent(true);

      expect(withoutBrand.find('a[data-to]').text()).toBe('test.example.com');
      expect(withBrand.find('a[data-to]').text()).toBe('test.example.com');
    });
  });
});
