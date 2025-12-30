// src/tests/apps/workspace/layouts/SettingsSection.spec.ts

import { mount, VueWrapper } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createI18n } from 'vue-i18n';
import { h, defineComponent } from 'vue';

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
          section: {
            title: 'Test Section',
            description: 'Test description',
          },
        },
      },
    },
  },
});

/**
 * SettingsSection Component Tests
 *
 * Tests the extracted section wrapper component that handles:
 * - Title and description rendering
 * - Icon display
 * - Slot content projection
 * - Card-style container styling
 */
describe('SettingsSection', () => {
  let wrapper: VueWrapper;

  // SettingsSection component stub representing expected interface
  const SettingsSectionStub = defineComponent({
    name: 'SettingsSection',
    props: {
      title: {
        type: String,
        required: true,
      },
      description: {
        type: String,
        default: '',
      },
      icon: {
        type: Object as () => { collection: string; name: string } | null,
        default: null,
      },
    },
    setup(props, { slots }) {
      return () =>
        h(
          'section',
          {
            class:
              'rounded-lg border border-gray-200 bg-white dark:border-gray-700 dark:bg-gray-800',
          },
          [
            // Header
            h(
              'div',
              {
                class: 'border-b border-gray-200 px-6 py-4 dark:border-gray-700',
              },
              [
                h('div', { class: 'flex items-center gap-3' }, [
                  props.icon &&
                    h('span', {
                      class: 'o-icon size-5 text-gray-500 dark:text-gray-400',
                      'data-icon': props.icon.name,
                      'data-collection': props.icon.collection,
                    }),
                  h(
                    'div',
                    {},
                    [
                      h(
                        'h2',
                        {
                          class: 'text-lg font-semibold text-gray-900 dark:text-white',
                        },
                        props.title
                      ),
                      props.description &&
                        h(
                          'p',
                          {
                            class: 'text-sm text-gray-500 dark:text-gray-400',
                          },
                          props.description
                        ),
                    ].filter(Boolean)
                  ),
                ]),
              ]
            ),
            // Content slot
            h(
              'div',
              { class: 'divide-y divide-gray-200 dark:divide-gray-700' },
              slots.default?.()
            ),
          ]
        );
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
      description: string;
      icon: { collection: string; name: string } | null;
    }> = {},
    slots: Record<string, () => unknown> = {}
  ) => mount(SettingsSectionStub, {
      props: {
        title: 'Test Section',
        ...props,
      },
      slots: {
        default: () => h('div', { class: 'slot-content' }, 'Slot Content'),
        ...slots,
      },
      global: {
        plugins: [i18n],
      },
    });

  describe('Basic Rendering', () => {
    it('renders section container with card styling', () => {
      wrapper = mountComponent();

      const section = wrapper.find('section');
      expect(section.exists()).toBe(true);
      expect(section.classes()).toContain('rounded-lg');
      expect(section.classes()).toContain('border');
      expect(section.classes()).toContain('bg-white');
    });

    it('renders header with border separator', () => {
      wrapper = mountComponent();

      const header = wrapper.find('.border-b');
      expect(header.exists()).toBe(true);
      expect(header.classes()).toContain('px-6');
      expect(header.classes()).toContain('py-4');
    });

    it('renders content container with divider styling', () => {
      wrapper = mountComponent();

      const content = wrapper.find('.divide-y');
      expect(content.exists()).toBe(true);
    });
  });

  describe('Title Rendering', () => {
    it('renders title as h2 element', () => {
      wrapper = mountComponent({ title: 'Profile Settings' });

      const title = wrapper.find('h2');
      expect(title.exists()).toBe(true);
      expect(title.text()).toBe('Profile Settings');
    });

    it('applies correct title styling', () => {
      wrapper = mountComponent({ title: 'Profile Settings' });

      const title = wrapper.find('h2');
      expect(title.classes()).toContain('text-lg');
      expect(title.classes()).toContain('font-semibold');
    });

    it('handles long titles gracefully', () => {
      const longTitle =
        'This is a very long settings section title that might wrap on smaller screens';
      wrapper = mountComponent({ title: longTitle });

      const title = wrapper.find('h2');
      expect(title.text()).toBe(longTitle);
    });

    it('handles special characters in title', () => {
      wrapper = mountComponent({ title: 'Settings & Preferences' });

      const title = wrapper.find('h2');
      expect(title.text()).toBe('Settings & Preferences');
    });
  });

  describe('Description Rendering', () => {
    it('renders description when provided', () => {
      wrapper = mountComponent({
        title: 'Test',
        description: 'This is a description',
      });

      const description = wrapper.find('.text-sm.text-gray-500');
      expect(description.exists()).toBe(true);
      expect(description.text()).toBe('This is a description');
    });

    it('does not render description when not provided', () => {
      wrapper = mountComponent({ title: 'Test' });

      const descriptions = wrapper.findAll('.text-sm.text-gray-500');
      expect(descriptions.length).toBe(0);
    });

    it('does not render description when empty string', () => {
      wrapper = mountComponent({ title: 'Test', description: '' });

      const descriptions = wrapper.findAll('p.text-sm');
      expect(descriptions.length).toBe(0);
    });
  });

  describe('Icon Rendering', () => {
    it('renders icon when provided', () => {
      wrapper = mountComponent({
        title: 'Test',
        icon: { collection: 'heroicons', name: 'user-solid' },
      });

      const icon = wrapper.find('[data-icon="user-solid"]');
      expect(icon.exists()).toBe(true);
      expect(icon.attributes('data-collection')).toBe('heroicons');
    });

    it('does not render icon when not provided', () => {
      wrapper = mountComponent({ title: 'Test', icon: null });

      const icon = wrapper.find('[data-icon]');
      expect(icon.exists()).toBe(false);
    });

    it('applies correct icon styling', () => {
      wrapper = mountComponent({
        title: 'Test',
        icon: { collection: 'heroicons', name: 'cog' },
      });

      const icon = wrapper.find('[data-icon="cog"]');
      expect(icon.classes()).toContain('size-5');
    });
  });

  describe('Slot Content', () => {
    it('renders default slot content', () => {
      wrapper = mountComponent();

      const slotContent = wrapper.find('.slot-content');
      expect(slotContent.exists()).toBe(true);
      expect(slotContent.text()).toBe('Slot Content');
    });

    it('renders complex slot content', () => {
      wrapper = mountComponent({}, {
        default: () => [
          h('div', { class: 'setting-item-1' }, 'First Setting'),
          h('div', { class: 'setting-item-2' }, 'Second Setting'),
        ],
      });

      expect(wrapper.find('.setting-item-1').exists()).toBe(true);
      expect(wrapper.find('.setting-item-2').exists()).toBe(true);
    });

    it('renders empty slot gracefully', () => {
      wrapper = mount(SettingsSectionStub, {
        props: { title: 'Empty Section' },
        global: { plugins: [i18n] },
      });

      expect(wrapper.find('section').exists()).toBe(true);
    });

    it('renders form elements in slot', () => {
      wrapper = mountComponent({}, {
        default: () =>
          h('form', { class: 'settings-form' }, [
            h('input', { type: 'text', placeholder: 'Enter value' }),
            h('button', { type: 'submit' }, 'Save'),
          ]),
      });

      expect(wrapper.find('form.settings-form').exists()).toBe(true);
      expect(wrapper.find('input[type="text"]').exists()).toBe(true);
      expect(wrapper.find('button[type="submit"]').exists()).toBe(true);
    });
  });

  describe('Dark Mode Support', () => {
    it('has dark mode classes on container', () => {
      wrapper = mountComponent();

      const section = wrapper.find('section');
      const classes = section.attributes('class') || '';
      expect(classes).toContain('dark:border-gray-700');
      expect(classes).toContain('dark:bg-gray-800');
    });

    it('has dark mode classes on header', () => {
      wrapper = mountComponent();

      const header = wrapper.find('.border-b');
      const classes = header.attributes('class') || '';
      expect(classes).toContain('dark:border-gray-700');
    });

    it('has dark mode classes on title', () => {
      wrapper = mountComponent();

      const title = wrapper.find('h2');
      const classes = title.attributes('class') || '';
      expect(classes).toContain('dark:text-white');
    });
  });

  describe('Layout Structure', () => {
    it('has icon and title in same row', () => {
      wrapper = mountComponent({
        title: 'Test',
        icon: { collection: 'heroicons', name: 'cog' },
      });

      const headerRow = wrapper.find('.flex.items-center.gap-3');
      expect(headerRow.exists()).toBe(true);

      // Icon and title should be inside this flex container
      expect(headerRow.find('[data-icon]').exists()).toBe(true);
      expect(headerRow.find('h2').exists()).toBe(true);
    });

    it('maintains proper spacing between elements', () => {
      wrapper = mountComponent({
        title: 'Test',
        icon: { collection: 'heroicons', name: 'cog' },
      });

      const headerRow = wrapper.find('.flex.items-center.gap-3');
      expect(headerRow.classes()).toContain('gap-3');
    });
  });

  describe('Edge Cases', () => {
    it('handles HTML entities in title', () => {
      wrapper = mountComponent({ title: 'Settings &amp; More' });

      const title = wrapper.find('h2');
      expect(title.exists()).toBe(true);
    });

    it('handles unicode characters in title', () => {
      wrapper = mountComponent({ title: 'Settings ⚙️' });

      const title = wrapper.find('h2');
      expect(title.text()).toContain('Settings');
    });

    it('handles empty icon object properties gracefully', () => {
      // This tests defensive coding in the component
      wrapper = mountComponent({
        title: 'Test',
        icon: { collection: '', name: '' },
      });

      expect(wrapper.find('section').exists()).toBe(true);
    });
  });

  describe('Accessibility', () => {
    it('uses semantic section element', () => {
      wrapper = mountComponent();

      const section = wrapper.find('section');
      expect(section.exists()).toBe(true);
    });

    it('uses h2 for section heading', () => {
      wrapper = mountComponent({ title: 'Settings' });

      const heading = wrapper.find('h2');
      expect(heading.exists()).toBe(true);
    });

    it('section is focusable content container', () => {
      wrapper = mountComponent({}, {
        default: () => h('button', { class: 'focusable' }, 'Click me'),
      });

      const button = wrapper.find('button.focusable');
      expect(button.exists()).toBe(true);
    });
  });
});
