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
        'web.domains.sso.configure_sso': 'Configure SSO',
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

function mountComponent({ canBrand = false, canManageSso = false } = {}) {
  return mount(DomainsTableActionsCell, {
    props: {
      domain: mockDomain,
      orgid: 'org_ext_123',
      canBrand,
      canManageSso,
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
      const wrapper = mountComponent({ canBrand: false });

      const menuItems = wrapper.findAll('[role="menuitem"]');
      const texts = menuItems.map((item) => item.text());

      expect(texts).not.toContain('Manage Brand');
      expect(texts).toContain('Verify Domain');
      expect(texts).toContain('Remove');
    });

    it('shows "Manage Brand" menu item when canBrand is true', () => {
      const wrapper = mountComponent({ canBrand: true });

      const menuItems = wrapper.findAll('[role="menuitem"]');
      const texts = menuItems.map((item) => item.text());

      expect(texts).toContain('Manage Brand');
      expect(texts).toContain('Verify Domain');
      expect(texts).toContain('Remove');
    });

    it('renders correct menu item count based on entitlements', () => {
      // Base: Verify Domain, Remove (2 items)
      const base = mountComponent();
      expect(base.findAll('[role="menuitem"]')).toHaveLength(2);

      // With branding only: Manage Brand, Verify Domain, Remove (3 items)
      const withBrand = mountComponent({ canBrand: true });
      expect(withBrand.findAll('[role="menuitem"]')).toHaveLength(3);

      // With SSO only: Verify Domain, Configure SSO, Remove (3 items)
      const withSso = mountComponent({ canManageSso: true });
      expect(withSso.findAll('[role="menuitem"]')).toHaveLength(3);

      // With both: Manage Brand, Verify Domain, Configure SSO, Remove (4 items)
      const withBoth = mountComponent({ canBrand: true, canManageSso: true });
      expect(withBoth.findAll('[role="menuitem"]')).toHaveLength(4);
    });

    it('links "Manage Brand" to DomainBrand route with correct params', () => {
      const wrapper = mountComponent({ canBrand: true });

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

  describe('canManageSso entitlement gating', () => {
    it('hides "Configure SSO" menu item when canManageSso is false', () => {
      const wrapper = mountComponent({ canManageSso: false });

      const menuItems = wrapper.findAll('[role="menuitem"]');
      const texts = menuItems.map((item) => item.text());

      expect(texts).not.toContain('Configure SSO');
      expect(texts).toContain('Verify Domain');
      expect(texts).toContain('Remove');
    });

    it('shows "Configure SSO" menu item when canManageSso is true', () => {
      const wrapper = mountComponent({ canManageSso: true });

      const menuItems = wrapper.findAll('[role="menuitem"]');
      const texts = menuItems.map((item) => item.text());

      expect(texts).toContain('Configure SSO');
    });

    it('links "Configure SSO" to DomainSso route with correct params', () => {
      const wrapper = mountComponent({ canManageSso: true });

      const links = wrapper.findAll('a[data-to]');
      const ssoLink = links.find((link) => link.text() === 'Configure SSO');

      expect(ssoLink).toBeDefined();
      const to = JSON.parse(ssoLink!.attributes('data-to')!);
      expect(to).toEqual({
        name: 'DomainSso',
        params: { orgid: 'org_ext_123', extid: 'dm-test-extid' },
      });
    });
  });

  describe('delete event emission', () => {
    it('emits delete event with domain extid when Remove button is clicked', async () => {
      const wrapper = mountComponent();

      // Find the Remove button by its text content
      const menuItems = wrapper.findAll('[role="menuitem"]');
      const removeMenuItem = menuItems.find((item) => item.text().includes('Remove'));
      expect(removeMenuItem).toBeDefined();

      // Find and click the button inside the menu item
      const removeButton = removeMenuItem!.find('button');
      expect(removeButton.exists()).toBe(true);

      await removeButton.trigger('click');

      // Verify delete event was emitted with correct payload
      const emitted = wrapper.emitted('delete');
      expect(emitted).toBeDefined();
      expect(emitted).toHaveLength(1);
      expect(emitted![0]).toEqual(['dm-test-extid']);
    });

    it('passes domain.extid (not identifier) to delete event', async () => {
      const wrapper = mountComponent();

      const removeButton = wrapper.find('button');
      await removeButton.trigger('click');

      const emitted = wrapper.emitted('delete');
      // extid should be 'dm-test-extid', not 'domain-123' (identifier)
      expect(emitted![0][0]).toBe(mockDomain.extid);
      expect(emitted![0][0]).not.toBe(mockDomain.identifier);
    });
  });
});
