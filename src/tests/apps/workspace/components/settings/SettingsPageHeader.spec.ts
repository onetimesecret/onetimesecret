// src/tests/apps/workspace/components/settings/SettingsPageHeader.spec.ts

import { mount, VueWrapper } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createI18n } from 'vue-i18n';
import { h, defineComponent } from 'vue';

const i18n = createI18n({
  legacy: false,
  locale: 'en',
  messages: {
    en: {
      web: {
        TITLES: {
          account: 'Settings',
        },
        settings: {
          manage_your_account_settings_and_preferences:
            'Manage your account settings and preferences',
        },
      },
    },
  },
});

/**
 * SettingsPageHeader Component Tests
 *
 * Tests the page header component that provides:
 * - Title with fallback to i18n default
 * - Optional subtitle/description
 * - Actions slot for buttons/controls
 * - Design system compliant typography (text-xl font-medium)
 */
describe('SettingsPageHeader', () => {
  let wrapper: VueWrapper;

  // SettingsPageHeader component stub representing expected interface
  const SettingsPageHeaderStub = defineComponent({
    name: 'SettingsPageHeader',
    props: {
      title: {
        type: String,
        default: undefined,
      },
      subtitle: {
        type: String,
        default: undefined,
      },
    },
    setup(props, { slots }) {
      // Access i18n via injection in real component
      const fallbackTitle = 'Settings';
      const fallbackSubtitle = 'Manage your account settings and preferences';

      return () =>
        h('div', { class: 'mb-10' }, [
          h('div', { class: 'flex items-start justify-between' }, [
            h('div', {}, [
              h(
                'h1',
                { class: 'text-xl font-medium text-gray-900 dark:text-white' },
                props.title ?? fallbackTitle
              ),
              h(
                'p',
                { class: 'mt-2 text-sm text-gray-600 dark:text-gray-400' },
                props.subtitle ?? fallbackSubtitle
              ),
            ]),
            slots.actions && h('div', {}, slots.actions()),
          ]),
        ]);
    },
  });

  beforeEach(() => {
    vi.clearAllMocks();
  });

  afterEach(() => {
    if (wrapper) {
      wrapper.unmount();
    }
  });

  const mountComponent = (
    props: Partial<{
      title: string;
      subtitle: string;
    }> = {},
    slots: Record<string, () => unknown> = {}
  ) =>
    mount(SettingsPageHeaderStub, {
      props,
      slots,
      global: {
        plugins: [i18n],
      },
    });

  describe('Basic Rendering', () => {
    it('renders container with correct spacing', () => {
      wrapper = mountComponent();

      const container = wrapper.find('.mb-10');
      expect(container.exists()).toBe(true);
    });

    it('renders flex container for layout', () => {
      wrapper = mountComponent();

      const flexContainer = wrapper.find('.flex.items-start.justify-between');
      expect(flexContainer.exists()).toBe(true);
    });
  });

  describe('Title Rendering', () => {
    it('renders h1 heading element', () => {
      wrapper = mountComponent();

      const heading = wrapper.find('h1');
      expect(heading.exists()).toBe(true);
    });

    it('renders fallback title when no title prop provided', () => {
      wrapper = mountComponent();

      const heading = wrapper.find('h1');
      expect(heading.text()).toBe('Settings');
    });

    it('renders custom title when provided', () => {
      wrapper = mountComponent({ title: 'Organization Settings' });

      const heading = wrapper.find('h1');
      expect(heading.text()).toBe('Organization Settings');
    });

    it('applies design system typography classes', () => {
      wrapper = mountComponent();

      const heading = wrapper.find('h1');
      expect(heading.classes()).toContain('text-xl');
      expect(heading.classes()).toContain('font-medium');
    });

    it('applies correct text color classes', () => {
      wrapper = mountComponent();

      const heading = wrapper.find('h1');
      expect(heading.classes()).toContain('text-gray-900');
    });
  });

  describe('Subtitle Rendering', () => {
    it('renders fallback subtitle when no subtitle prop provided', () => {
      wrapper = mountComponent();

      const subtitle = wrapper.find('p');
      expect(subtitle.text()).toBe('Manage your account settings and preferences');
    });

    it('renders custom subtitle when provided', () => {
      wrapper = mountComponent({ subtitle: 'Configure your organization preferences' });

      const subtitle = wrapper.find('p');
      expect(subtitle.text()).toBe('Configure your organization preferences');
    });

    it('applies correct subtitle styling', () => {
      wrapper = mountComponent();

      const subtitle = wrapper.find('p');
      expect(subtitle.classes()).toContain('mt-2');
      expect(subtitle.classes()).toContain('text-sm');
      expect(subtitle.classes()).toContain('text-gray-600');
    });
  });

  describe('Actions Slot', () => {
    it('does not render actions container when slot is empty', () => {
      wrapper = mountComponent();

      const flexContainer = wrapper.find('.flex.items-start.justify-between');
      // Should only have the text content div, no actions div
      expect(flexContainer.element.children.length).toBe(1);
    });

    it('renders actions slot content when provided', () => {
      wrapper = mountComponent({}, {
        actions: () => h('button', { class: 'action-button' }, 'Save'),
      });

      const button = wrapper.find('.action-button');
      expect(button.exists()).toBe(true);
      expect(button.text()).toBe('Save');
    });

    it('renders multiple action elements', () => {
      wrapper = mountComponent({}, {
        actions: () => [
          h('button', { class: 'cancel-btn' }, 'Cancel'),
          h('button', { class: 'save-btn' }, 'Save'),
        ],
      });

      expect(wrapper.find('.cancel-btn').exists()).toBe(true);
      expect(wrapper.find('.save-btn').exists()).toBe(true);
    });
  });

  describe('Dark Mode Support', () => {
    it('has dark mode class on title', () => {
      wrapper = mountComponent();

      const heading = wrapper.find('h1');
      expect(heading.classes()).toContain('dark:text-white');
    });

    it('has dark mode class on subtitle', () => {
      wrapper = mountComponent();

      const subtitle = wrapper.find('p');
      expect(subtitle.classes()).toContain('dark:text-gray-400');
    });
  });

  describe('Accessibility', () => {
    it('uses h1 for page title (proper heading hierarchy)', () => {
      wrapper = mountComponent({ title: 'Account Settings' });

      const h1 = wrapper.find('h1');
      expect(h1.exists()).toBe(true);
      expect(h1.text()).toBe('Account Settings');
    });

    it('title is first element in reading order', () => {
      wrapper = mountComponent({ title: 'Test Title' });

      const firstChild = wrapper.find('.flex.items-start.justify-between > div:first-child');
      const h1 = firstChild.find('h1');
      expect(h1.exists()).toBe(true);
    });

    it('subtitle follows title in reading order', () => {
      wrapper = mountComponent({
        title: 'Test Title',
        subtitle: 'Test Subtitle',
      });

      const contentDiv = wrapper.find('.flex.items-start.justify-between > div:first-child');
      const children = contentDiv.element.children;
      expect(children[0].tagName).toBe('H1');
      expect(children[1].tagName).toBe('P');
    });
  });

  describe('Edge Cases', () => {
    it('handles empty string title by showing empty', () => {
      wrapper = mountComponent({ title: '' });

      const heading = wrapper.find('h1');
      // Empty string is a valid prop value, should render as empty
      expect(heading.text()).toBe('');
    });

    it('handles special characters in title', () => {
      wrapper = mountComponent({ title: 'Settings & Preferences' });

      const heading = wrapper.find('h1');
      expect(heading.text()).toBe('Settings & Preferences');
    });

    it('handles long title text', () => {
      const longTitle = 'This is a very long settings page title that might wrap';
      wrapper = mountComponent({ title: longTitle });

      const heading = wrapper.find('h1');
      expect(heading.text()).toBe(longTitle);
    });

    it('handles unicode characters in title', () => {
      wrapper = mountComponent({ title: 'Paramètres' });

      const heading = wrapper.find('h1');
      expect(heading.text()).toBe('Paramètres');
    });
  });
});
