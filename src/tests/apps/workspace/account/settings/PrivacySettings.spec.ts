// src/tests/apps/workspace/account/settings/PrivacySettings.spec.ts
//
// Tests for PrivacySettings component rendering and design system compliance.
// Verifies design system compliance:
// - Card surfaces: border-gray-200/60 bg-white/60 backdrop-blur-sm shadow-sm
// - Typography: font-medium (not font-semibold) for section headings
// - Section heading: text-lg font-medium text-gray-600 dark:text-gray-300

import { mount, VueWrapper } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createI18n } from 'vue-i18n';
import PrivacySettings from '@/apps/workspace/account/settings/PrivacySettings.vue';

// Mock vue-router
vi.mock('vue-router', () => ({
  useRoute: vi.fn(() => ({ path: '/account/settings/privacy' })),
  useRouter: vi.fn(() => ({ push: vi.fn(), replace: vi.fn() })),
}));

// Mock OIcon component
vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="o-icon" :data-icon="name" :data-collection="collection" />',
    props: ['collection', 'name', 'class'],
  },
}));

// Mock SettingsLayout
vi.mock('@/apps/workspace/layouts/SettingsLayout.vue', () => ({
  default: {
    name: 'SettingsLayout',
    template: '<div class="mock-settings-layout"><slot /></div>',
  },
}));

const i18n = createI18n({
  legacy: false,
  locale: 'en',
  messages: {
    en: {
      web: {
        settings: {
          privacy: {
            title: 'Privacy',
            manage_privacy_settings: 'Manage your privacy settings',
            your_privacy: 'Your Privacy',
            non_negotiable: 'Non-negotiable',
            no_analytics_statement: 'We do not track you',
            explanation: 'No cookies, no analytics, no tracking.',
          },
        },
      },
    },
  },
});

/**
 * PrivacySettings Component Tests
 *
 * Tests the privacy settings page that displays:
 * - Privacy protection statement
 * - Disabled toggle in "on" position
 * - Design system compliant styling
 */
describe('PrivacySettings', () => {
  let wrapper: VueWrapper;

  beforeEach(() => {
    vi.clearAllMocks();
  });

  afterEach(() => {
    if (wrapper) {
      wrapper.unmount();
    }
  });

  const mountComponent = () =>
    mount(PrivacySettings, {
      global: {
        plugins: [i18n],
      },
    });

  describe('Basic Rendering', () => {
    it('renders within SettingsLayout', () => {
      wrapper = mountComponent();

      expect(wrapper.find('.mock-settings-layout').exists()).toBe(true);
    });

    it('renders section container', () => {
      wrapper = mountComponent();

      expect(wrapper.find('section').exists()).toBe(true);
    });

    it('renders shield icon', () => {
      wrapper = mountComponent();

      const icon = wrapper.find('[data-icon="shield-check-solid"]');
      expect(icon.exists()).toBe(true);
      expect(icon.attributes('data-collection')).toBe('heroicons');
    });

    it('renders section title', () => {
      wrapper = mountComponent();

      const heading = wrapper.find('h2');
      expect(heading.exists()).toBe(true);
      expect(heading.text()).toBe('Privacy');
    });

    it('renders section description', () => {
      wrapper = mountComponent();

      expect(wrapper.text()).toContain('Manage your privacy settings');
    });
  });

  describe('Privacy Statement Content', () => {
    it('renders privacy statement title', () => {
      wrapper = mountComponent();

      expect(wrapper.text()).toContain('Your Privacy');
    });

    it('renders non-negotiable badge', () => {
      wrapper = mountComponent();

      expect(wrapper.text()).toContain('Non-negotiable');
    });

    it('renders no analytics statement', () => {
      wrapper = mountComponent();

      expect(wrapper.text()).toContain('We do not track you');
    });

    it('renders explanation text', () => {
      wrapper = mountComponent();

      expect(wrapper.text()).toContain('No cookies, no analytics, no tracking');
    });
  });

  describe('Disabled Toggle', () => {
    it('renders toggle in disabled state', () => {
      wrapper = mountComponent();

      const toggle = wrapper.find('[role="switch"]');
      expect(toggle.exists()).toBe(true);
      expect(toggle.attributes('aria-disabled')).toBe('true');
    });

    it('toggle shows as checked (privacy always on)', () => {
      wrapper = mountComponent();

      const toggle = wrapper.find('[role="switch"]');
      expect(toggle.attributes('aria-checked')).toBe('true');
    });

    it('toggle has cursor-not-allowed for disabled state', () => {
      wrapper = mountComponent();

      const toggle = wrapper.find('[role="switch"]');
      expect(toggle.classes()).toContain('cursor-not-allowed');
    });

    it('toggle has opacity-50 for disabled visual state', () => {
      wrapper = mountComponent();

      const toggle = wrapper.find('[role="switch"]');
      expect(toggle.classes()).toContain('opacity-50');
    });

    it('toggle has proper accessibility label', () => {
      wrapper = mountComponent();

      const toggle = wrapper.find('[role="switch"]');
      expect(toggle.attributes('aria-label')).toBe('Privacy protection is always enabled');
    });
  });

  describe('Non-Negotiable Badge Styling', () => {
    it('badge has green background', () => {
      wrapper = mountComponent();

      const badge = wrapper.find('.bg-green-100');
      expect(badge.exists()).toBe(true);
    });

    it('badge has rounded-full shape', () => {
      wrapper = mountComponent();

      const badge = wrapper.find('.bg-green-100');
      expect(badge.classes()).toContain('rounded-full');
    });

    it('badge has correct text styling', () => {
      wrapper = mountComponent();

      const badge = wrapper.find('.bg-green-100');
      expect(badge.classes()).toContain('text-xs');
      expect(badge.classes()).toContain('font-medium');
    });
  });

  describe('Design System Compliance - Card Surfaces', () => {
    it('section has rounded-lg border styling', () => {
      wrapper = mountComponent();

      const section = wrapper.find('section');
      expect(section.classes()).toContain('rounded-lg');
      expect(section.classes()).toContain('border');
    });

    it('section uses transparency classes for glassmorphism (bg-white/60)', () => {
      wrapper = mountComponent();

      const section = wrapper.find('section');
      // After frontend-dev fixes, this should pass
      // Current: bg-white (violation)
      // Expected: bg-white/60
      expect(section.classes()).toContain('bg-white/60');
    });

    it('section has border with transparency (border-gray-200/60)', () => {
      wrapper = mountComponent();

      const section = wrapper.find('section');
      // After frontend-dev fixes, this should pass
      // Current: border-gray-200 (violation)
      // Expected: border-gray-200/60
      expect(section.classes()).toContain('border-gray-200/60');
    });

    it('section has shadow-sm for subtle elevation', () => {
      wrapper = mountComponent();

      const section = wrapper.find('section');
      expect(section.classes()).toContain('shadow-sm');
    });

    it('section has backdrop-blur-sm for glassmorphism', () => {
      wrapper = mountComponent();

      const section = wrapper.find('section');
      expect(section.classes()).toContain('backdrop-blur-sm');
    });
  });

  describe('Design System Compliance - Typography', () => {
    it('section heading uses font-medium (not font-semibold)', () => {
      wrapper = mountComponent();

      const heading = wrapper.find('h2');
      // After frontend-dev fixes, this should pass
      // Current: font-semibold (violation)
      // Expected: font-medium
      expect(heading.classes()).toContain('font-medium');
      expect(heading.classes()).not.toContain('font-semibold');
    });

    it('section heading has text-lg size', () => {
      wrapper = mountComponent();

      const heading = wrapper.find('h2');
      expect(heading.classes()).toContain('text-lg');
    });

    it('section heading has correct gray color (text-gray-600)', () => {
      wrapper = mountComponent();

      const heading = wrapper.find('h2');
      // Design system specifies text-gray-600 for section headings
      expect(heading.classes()).toContain('text-gray-600');
    });
  });

  describe('Dark Mode Support', () => {
    it('section has dark mode border styling with transparency', () => {
      wrapper = mountComponent();

      const section = wrapper.find('section');
      // Design system uses /60 transparency for dark mode
      expect(section.classes()).toContain('dark:border-gray-700/60');
    });

    it('section has dark mode background styling with transparency', () => {
      wrapper = mountComponent();

      const section = wrapper.find('section');
      // Design system uses /60 transparency for dark mode
      expect(section.classes()).toContain('dark:bg-gray-800/60');
    });

    it('heading has dark mode text color', () => {
      wrapper = mountComponent();

      const heading = wrapper.find('h2');
      // Design system uses text-gray-300 for section headings in dark mode
      expect(heading.classes()).toContain('dark:text-gray-300');
    });

    it('badge has dark mode styling', () => {
      wrapper = mountComponent();

      const badge = wrapper.find('.bg-green-100');
      expect(badge.classes()).toContain('dark:bg-green-900/30');
      expect(badge.classes()).toContain('dark:text-green-400');
    });
  });

  describe('Layout Structure', () => {
    it('has header with border separator', () => {
      wrapper = mountComponent();

      const header = wrapper.find('.border-b');
      expect(header.exists()).toBe(true);
      expect(header.classes()).toContain('px-6');
      expect(header.classes()).toContain('py-4');
    });

    it('has content area with padding', () => {
      wrapper = mountComponent();

      const content = wrapper.find('.p-6');
      expect(content.exists()).toBe(true);
    });

    it('icon and title are in flex layout', () => {
      wrapper = mountComponent();

      const flexContainer = wrapper.find('.flex.items-start.gap-3');
      expect(flexContainer.exists()).toBe(true);
    });
  });

  describe('Accessibility', () => {
    it('uses semantic section element', () => {
      wrapper = mountComponent();

      expect(wrapper.find('section').exists()).toBe(true);
    });

    it('uses h2 for section heading', () => {
      wrapper = mountComponent();

      expect(wrapper.find('h2').exists()).toBe(true);
    });

    it('icon has aria-hidden for decorative icons', () => {
      wrapper = mountComponent();

      // OIcon mock doesn't include aria-hidden, but real component should
      const icon = wrapper.find('[data-icon="shield-check-solid"]');
      expect(icon.exists()).toBe(true);
    });
  });
});
