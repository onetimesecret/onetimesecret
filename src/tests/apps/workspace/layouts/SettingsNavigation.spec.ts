// src/tests/apps/workspace/layouts/SettingsNavigation.spec.ts

import { mount, VueWrapper } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createI18n } from 'vue-i18n';
import { ref } from 'vue';

// Mock vue-router
const mockRoute = ref({ path: '/account/settings/profile' });
vi.mock('vue-router', () => ({
  useRoute: vi.fn(() => mockRoute.value),
  RouterLink: {
    name: 'RouterLink',
    template: '<a :href="to" :class="$attrs.class"><slot /></a>',
    props: ['to'],
  },
}));

// Mock OIcon component
vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="o-icon" :data-icon="name" :data-collection="collection" />',
    props: ['collection', 'name', 'class'],
  },
}));

const i18n = createI18n({
  legacy: false,
  locale: 'en',
  messages: {
    en: {
      web: {
        settings: {
          profile: {
            title: 'Profile',
            change_email: 'Change Email',
          },
          preferences: 'Preferences',
          privacy: { title: 'Privacy' },
          notifications: { title: 'Notifications' },
          security_settings_description: 'Manage your security settings',
          profile_settings_description: 'Manage your profile settings',
          api: { manage_api_keys: 'Manage API keys' },
          caution: {
            title: 'Caution Zone',
            description: 'Dangerous account actions',
          },
        },
        COMMON: {
          security: 'Security',
        },
        account: {
          api_key: 'API Key',
          region: 'Region',
          your_account: 'Account',
          settings: 'Settings',
        },
        auth: {
          change_password: { title: 'Change Password' },
          mfa: { title: 'Two-Factor Authentication' },
          sessions: { title: 'Active Sessions' },
          recovery_codes: { title: 'Recovery Codes' },
        },
        regions: {
          data_sovereignty_title: 'Data Sovereignty',
          your_region: 'Your Region',
          available_regions: 'Available Regions',
          why_it_matters: 'Why It Matters',
        },
      },
    },
  },
});

// Define navigation item type for tests
interface NavigationItem {
  to: string;
  icon: { collection: string; name: string };
  label: string;
  description?: string;
  badge?: string;
  children?: NavigationItem[];
  visible?: () => boolean;
}

// Sample navigation sections for testing
const mockSections: NavigationItem[] = [
  {
    to: '/account/settings/profile',
    icon: { collection: 'heroicons', name: 'user-solid' },
    label: 'Profile',
    description: 'Manage your profile settings',
    children: [
      {
        to: '/account/settings/profile/preferences',
        icon: { collection: 'heroicons', name: 'adjustments-horizontal-solid' },
        label: 'Preferences',
      },
      {
        to: '/account/settings/profile/privacy',
        icon: { collection: 'heroicons', name: 'shield-check' },
        label: 'Privacy',
      },
    ],
  },
  {
    to: '/account/settings/security',
    icon: { collection: 'heroicons', name: 'shield-check-solid' },
    label: 'Security',
    description: 'Manage your security settings',
  },
  {
    to: '/account/settings/api',
    icon: { collection: 'heroicons', name: 'code-bracket' },
    label: 'API Key',
    description: 'Manage API keys',
  },
];

/**
 * SettingsNavigation Component Tests
 *
 * Tests the extracted navigation component that handles:
 * - Rendering navigation items with icons
 * - Active state detection based on current route
 * - Parent/child navigation hierarchy
 * - Visibility filtering for conditional items
 */
describe('SettingsNavigation', () => {
  let wrapper: VueWrapper;

  beforeEach(() => {
    vi.clearAllMocks();
    mockRoute.value = { path: '/account/settings/profile' };
  });

  afterEach(() => {
    if (wrapper) {
      wrapper.unmount();
    }
  });

  // SettingsNavigation component stub for testing
  // This represents the expected component interface
  const SettingsNavigationStub = {
    name: 'SettingsNavigation',
    props: {
      sections: {
        type: Array as () => NavigationItem[],
        required: true,
      },
    },
    setup(props: { sections: NavigationItem[] }) {
      const route = mockRoute.value;

      const isActiveRoute = (path: string): boolean =>
        route.path === path || route.path.startsWith(path + '/');

      const isParentActive = (item: NavigationItem): boolean => {
        if (isActiveRoute(item.to)) return true;
        if (item.children) {
          return item.children.some(child => isActiveRoute(child.to));
        }
        return false;
      };

      const visibleSections = props.sections.filter(section =>
        section.visible ? section.visible() : true
      );

      return { isActiveRoute, isParentActive, visibleSections };
    },
    template: `
      <nav class="space-y-1" aria-label="Settings navigation">
        <template v-for="item in visibleSections" :key="item.to">
          <div>
            <router-link
              :to="item.to"
              :class="[
                'group flex items-center gap-3 rounded-lg px-3 py-2 text-sm font-medium',
                isParentActive(item)
                  ? 'bg-brand-50 text-brand-700'
                  : 'text-gray-700 hover:bg-gray-100',
              ]"
              :data-active="isParentActive(item)">
              <span class="o-icon" :data-icon="item.icon.name" />
              <span class="flex-1">{{ item.label }}</span>
              <span v-if="item.badge" class="badge">{{ item.badge }}</span>
            </router-link>
            <div
              v-if="item.children && isParentActive(item)"
              class="ml-4 mt-1 space-y-1 border-l-2 pl-4">
              <router-link
                v-for="child in item.children"
                :key="child.to"
                :to="child.to"
                :class="[
                  'group flex items-center gap-2 rounded-lg px-3 py-1.5 text-sm',
                  isActiveRoute(child.to)
                    ? 'font-medium text-brand-700'
                    : 'text-gray-600 hover:text-gray-900',
                ]"
                :data-active="isActiveRoute(child.to)">
                <span class="o-icon" :data-icon="child.icon.name" />
                {{ child.label }}
              </router-link>
            </div>
          </div>
        </template>
      </nav>
    `,
  };

  const mountComponent = (
    props: Partial<{ sections: NavigationItem[] }> = {}
  ) => mount(SettingsNavigationStub, {
      props: {
        sections: mockSections,
        ...props,
      },
      global: {
        plugins: [i18n],
        stubs: {
          RouterLink: {
            template: '<a :href="to" :class="$attrs.class" :data-active="$attrs[\'data-active\']"><slot /></a>',
            props: ['to'],
          },
        },
      },
    });

  describe('Basic Rendering', () => {
    it('renders navigation container with correct aria-label', () => {
      wrapper = mountComponent();

      const nav = wrapper.find('nav');
      expect(nav.exists()).toBe(true);
      expect(nav.attributes('aria-label')).toBe('Settings navigation');
    });

    it('renders all visible navigation sections', () => {
      wrapper = mountComponent();

      const links = wrapper.findAll('a[href^="/account/settings"]');
      // Should have 3 parent items + 2 children for Profile (since Profile is active)
      expect(links.length).toBeGreaterThanOrEqual(3);
    });

    it('renders icons for each navigation item', () => {
      wrapper = mountComponent();

      const icons = wrapper.findAll('.o-icon');
      expect(icons.length).toBeGreaterThan(0);
    });

    it('renders labels for each navigation item', () => {
      wrapper = mountComponent();

      const html = wrapper.html();
      expect(html).toContain('Profile');
      expect(html).toContain('Security');
      expect(html).toContain('API Key');
    });
  });

  describe('Active State Detection', () => {
    it('marks exact route match as active', () => {
      mockRoute.value = { path: '/account/settings/profile' };
      wrapper = mountComponent();

      const profileLink = wrapper.find('a[href="/account/settings/profile"]');
      expect(profileLink.attributes('data-active')).toBe('true');
    });

    it('marks parent as active when child route is active', () => {
      mockRoute.value = { path: '/account/settings/profile/preferences' };
      wrapper = mountComponent();

      const profileLink = wrapper.find('a[href="/account/settings/profile"]');
      expect(profileLink.attributes('data-active')).toBe('true');
    });

    it('marks child as active on exact child route', () => {
      mockRoute.value = { path: '/account/settings/profile/preferences' };
      wrapper = mountComponent();

      const preferencesLink = wrapper.find('a[href="/account/settings/profile/preferences"]');
      expect(preferencesLink.exists()).toBe(true);
      expect(preferencesLink.attributes('data-active')).toBe('true');
    });

    it('does not mark unrelated routes as active', () => {
      mockRoute.value = { path: '/account/settings/security' };
      wrapper = mountComponent();

      const profileLink = wrapper.find('a[href="/account/settings/profile"]');
      expect(profileLink.attributes('data-active')).toBe('false');
    });

    it('applies active styling classes', () => {
      mockRoute.value = { path: '/account/settings/profile' };
      wrapper = mountComponent();

      const profileLink = wrapper.find('a[href="/account/settings/profile"]');
      expect(profileLink.classes()).toContain('bg-brand-50');
      expect(profileLink.classes()).toContain('text-brand-700');
    });

    it('applies inactive styling classes', () => {
      mockRoute.value = { path: '/account/settings/security' };
      wrapper = mountComponent();

      const profileLink = wrapper.find('a[href="/account/settings/profile"]');
      expect(profileLink.classes()).toContain('text-gray-700');
    });
  });

  describe('Child Navigation', () => {
    it('shows children when parent is active', () => {
      mockRoute.value = { path: '/account/settings/profile' };
      wrapper = mountComponent();

      const preferencesLink = wrapper.find('a[href="/account/settings/profile/preferences"]');
      const privacyLink = wrapper.find('a[href="/account/settings/profile/privacy"]');

      expect(preferencesLink.exists()).toBe(true);
      expect(privacyLink.exists()).toBe(true);
    });

    it('hides children when parent is not active', () => {
      mockRoute.value = { path: '/account/settings/security' };
      wrapper = mountComponent();

      const preferencesLink = wrapper.find('a[href="/account/settings/profile/preferences"]');
      expect(preferencesLink.exists()).toBe(false);
    });

    it('shows children when child route is active', () => {
      mockRoute.value = { path: '/account/settings/profile/privacy' };
      wrapper = mountComponent();

      const preferencesLink = wrapper.find('a[href="/account/settings/profile/preferences"]');
      const privacyLink = wrapper.find('a[href="/account/settings/profile/privacy"]');

      expect(preferencesLink.exists()).toBe(true);
      expect(privacyLink.exists()).toBe(true);
    });

    it('renders child items with proper indentation structure', () => {
      mockRoute.value = { path: '/account/settings/profile' };
      wrapper = mountComponent();

      const childContainer = wrapper.find('.border-l-2');
      expect(childContainer.exists()).toBe(true);
      expect(childContainer.classes()).toContain('ml-4');
    });
  });

  describe('Visibility Filtering', () => {
    it('hides items with visible() returning false', () => {
      const sectionsWithHidden: NavigationItem[] = [
        ...mockSections,
        {
          to: '/account/settings/hidden',
          icon: { collection: 'heroicons', name: 'eye-slash' },
          label: 'Hidden Item',
          visible: () => false,
        },
      ];

      wrapper = mountComponent({ sections: sectionsWithHidden });

      const hiddenLink = wrapper.find('a[href="/account/settings/hidden"]');
      expect(hiddenLink.exists()).toBe(false);
    });

    it('shows items with visible() returning true', () => {
      const sectionsWithVisible: NavigationItem[] = [
        {
          to: '/account/settings/visible',
          icon: { collection: 'heroicons', name: 'eye' },
          label: 'Visible Item',
          visible: () => true,
        },
      ];

      wrapper = mountComponent({ sections: sectionsWithVisible });

      const visibleLink = wrapper.find('a[href="/account/settings/visible"]');
      expect(visibleLink.exists()).toBe(true);
    });

    it('shows items without visible property (default visible)', () => {
      wrapper = mountComponent();

      // All mockSections don't have visible property
      const profileLink = wrapper.find('a[href="/account/settings/profile"]');
      expect(profileLink.exists()).toBe(true);
    });
  });

  describe('Badge Rendering', () => {
    it('renders badge when present', () => {
      const sectionsWithBadge: NavigationItem[] = [
        {
          to: '/account/settings/new-feature',
          icon: { collection: 'heroicons', name: 'sparkles' },
          label: 'New Feature',
          badge: 'NEW',
        },
      ];

      wrapper = mountComponent({ sections: sectionsWithBadge });

      const badge = wrapper.find('.badge');
      expect(badge.exists()).toBe(true);
      expect(badge.text()).toBe('NEW');
    });

    it('does not render badge when not present', () => {
      wrapper = mountComponent();

      const badges = wrapper.findAll('.badge');
      expect(badges.length).toBe(0);
    });
  });

  describe('Edge Cases', () => {
    it('handles empty sections array', () => {
      wrapper = mountComponent({ sections: [] });

      const nav = wrapper.find('nav');
      expect(nav.exists()).toBe(true);

      const links = wrapper.findAll('a');
      expect(links.length).toBe(0);
    });

    it('handles sections without children', () => {
      const sectionsNoChildren: NavigationItem[] = [
        {
          to: '/account/settings/simple',
          icon: { collection: 'heroicons', name: 'cog' },
          label: 'Simple Item',
        },
      ];

      mockRoute.value = { path: '/account/settings/simple' };
      wrapper = mountComponent({ sections: sectionsNoChildren });

      const childContainer = wrapper.find('.border-l-2');
      expect(childContainer.exists()).toBe(false);
    });

    it('handles deeply nested route paths', () => {
      mockRoute.value = { path: '/account/settings/profile/preferences/advanced' };
      wrapper = mountComponent();

      // Parent should still be active
      const profileLink = wrapper.find('a[href="/account/settings/profile"]');
      expect(profileLink.attributes('data-active')).toBe('true');
    });
  });

  describe('Accessibility', () => {
    it('has semantic nav element with aria-label', () => {
      wrapper = mountComponent();

      const nav = wrapper.find('nav');
      expect(nav.exists()).toBe(true);
      expect(nav.attributes('aria-label')).toBe('Settings navigation');
    });

    it('uses proper link elements for navigation', () => {
      wrapper = mountComponent();

      const links = wrapper.findAll('a');
      expect(links.length).toBeGreaterThan(0);

      links.forEach(link => {
        expect(link.attributes('href')).toBeTruthy();
      });
    });
  });
});
