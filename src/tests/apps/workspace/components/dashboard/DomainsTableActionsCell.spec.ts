// src/tests/apps/workspace/components/dashboard/DomainsTableActionsCell.spec.ts

import { mount } from '@vue/test-utils';
import { describe, it, expect, vi, afterEach } from 'vitest';
import DomainsTableActionsCell from '@/apps/workspace/components/dashboard/DomainsTableActionsCell.vue';

// Mock vue-i18n
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key: string) => {
      const translations: Record<string, string> = {
        'web.domains.manage_brand': 'Manage Brand',
        'web.domains.verify_domain': 'Verify Domain',
        'web.COMMON.remove': 'Remove',
      };
      return translations[key] ?? key;
    },
  }),
}));

// Mock HeadlessUI MenuItem to render slot content with v-if support
vi.mock('@headlessui/vue', () => ({
  MenuItem: {
    name: 'MenuItem',
    template: '<div role="menuitem"><slot :active="false" /></div>',
  },
}));

// Mock MinimalDropdownMenu to expose menu-items slot
vi.mock('@/shared/components/ui/MinimalDropdownMenu.vue', () => ({
  default: {
    name: 'MinimalDropdownMenu',
    template: '<div class="dropdown"><slot name="menu-items" /></div>',
  },
}));

// Mock OIcon
vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="o-icon" />',
    props: ['collection', 'name'],
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
  return mount(DomainsTableActionsCell, {
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

describe('DomainsTableActionsCell', () => {
  afterEach(() => {
    vi.clearAllMocks();
  });

  describe('canBrand entitlement gating', () => {
    it('hides "Manage Brand" menu item when canBrand is false', () => {
      const wrapper = mountComponent(false);

      const menuItems = wrapper.findAll('[role="menuitem"]');
      const texts = menuItems.map((item) => item.text());

      expect(texts).not.toContain('Manage Brand');
      expect(texts).toContain('Verify Domain');
      expect(texts).toContain('Remove');
    });

    it('shows "Manage Brand" menu item when canBrand is true', () => {
      const wrapper = mountComponent(true);

      const menuItems = wrapper.findAll('[role="menuitem"]');
      const texts = menuItems.map((item) => item.text());

      expect(texts).toContain('Manage Brand');
      expect(texts).toContain('Verify Domain');
      expect(texts).toContain('Remove');
    });

    it('renders 2 menu items without branding, 3 with branding', () => {
      const withoutBrand = mountComponent(false);
      const withBrand = mountComponent(true);

      expect(withoutBrand.findAll('[role="menuitem"]')).toHaveLength(2);
      expect(withBrand.findAll('[role="menuitem"]')).toHaveLength(3);
    });

    it('links "Manage Brand" to DomainBrand route with correct params', () => {
      const wrapper = mountComponent(true);

      const links = wrapper.findAll('a[data-to]');
      const brandLink = links.find((link) => link.text() === 'Manage Brand');

      expect(brandLink).toBeDefined();
      const to = JSON.parse(brandLink!.attributes('data-to')!);
      expect(to).toEqual({
        name: 'DomainBrand',
        params: { orgid: 'org_ext_123', extid: 'dm-test-extid' },
      });
    });
  });
});
