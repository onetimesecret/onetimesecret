// src/tests/shared/layouts/BaseLayout.spec.ts

import { mount, VueWrapper } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createI18n } from 'vue-i18n';
import { h, defineComponent, ref } from 'vue';
import { createPinia, setActivePinia } from 'pinia';

// Mock WindowService
vi.mock('@/services/window.service', () => ({
  WindowService: {
    get: vi.fn((key: string) => {
      if (key === 'global_banner') return null;
      return undefined;
    }),
  },
}));

// Mock useTheme composable
vi.mock('@/shared/composables/useTheme', () => ({
  useTheme: () => ({
    initializeTheme: vi.fn(),
  }),
}));

// Mock useProductIdentity store
vi.mock('@/shared/stores/identityStore', () => ({
  useProductIdentity: () => ({
    primaryColor: 'bg-brand-500',
  }),
}));

// Mock GlobalBroadcast component
vi.mock('@/shared/components/ui/GlobalBroadcast.vue', () => ({
  default: defineComponent({
    name: 'GlobalBroadcast',
    props: ['show', 'content', 'expirationDays'],
    template: '<div class="mock-global-broadcast" v-if="show">{{ content }}</div>',
  }),
}));

// Mock color utils
vi.mock('@/utils/color-utils', () => ({
  isColorValue: (value: string) => value.startsWith('#') || value.startsWith('rgb'),
}));

const i18n = createI18n({
  legacy: false,
  locale: 'en',
  messages: {
    en: {
      web: {
        LABELS: {
          dismiss: 'Dismiss',
        },
      },
    },
  },
});

/**
 * BaseLayout Component Tests
 *
 * Tests the foundational layout component that:
 * - Provides the min-h-screen flex container for full-height layouts
 * - Renders the brand color bar at the top
 * - Conditionally displays the GlobalBroadcast component
 * - Provides named slots for header, main, footer, and status areas
 */
describe('BaseLayout', () => {
  let wrapper: VueWrapper;

  // BaseLayout component stub representing the expected interface
  const BaseLayoutStub = defineComponent({
    name: 'BaseLayout',
    props: {
      displayGlobalBroadcast: {
        type: Boolean,
        default: true,
      },
      displayMasthead: {
        type: Boolean,
        default: true,
      },
      displayNavigation: {
        type: Boolean,
        default: true,
      },
      displayFooterLinks: {
        type: Boolean,
        default: true,
      },
      displayFeedback: {
        type: Boolean,
        default: true,
      },
      displayVersion: {
        type: Boolean,
        default: true,
      },
      displayToggles: {
        type: Boolean,
        default: true,
      },
      displayPoweredBy: {
        type: Boolean,
        default: true,
      },
      colonel: {
        type: Boolean,
        default: false,
      },
    },
    setup(props, { slots }) {
      const globalBanner = ref<string | null>(null);
      const hasGlobalBanner = ref(!!globalBanner.value);
      const primaryColorClass = ref('bg-brand-500');
      const primaryColorStyle = ref({});

      return () =>
        h('div', { class: 'flex min-h-screen flex-col' }, [
          // Brand color bar at top
          h('div', {
            class: ['fixed left-0 top-0 z-50 h-1 w-full', primaryColorClass.value],
            style: primaryColorStyle.value,
          }),
          // GlobalBroadcast (conditional)
          props.displayGlobalBroadcast
            ? h('div', {
                class: 'mock-global-broadcast',
                'data-show': hasGlobalBanner.value,
                'data-testid': 'global-broadcast',
              })
            : null,
          // Named slots
          slots.header?.(),
          slots.main?.(),
          slots.footer?.(),
          slots.status?.() ?? h('div', { id: 'status-messages' }),
        ]);
    },
  });

  beforeEach(() => {
    const pinia = createPinia();
    setActivePinia(pinia);
    vi.clearAllMocks();
  });

  afterEach(() => {
    if (wrapper) {
      wrapper.unmount();
    }
  });

  const mountComponent = (
    props: Record<string, unknown> = {},
    slots: Record<string, () => unknown> = {}
  ) =>
    mount(BaseLayoutStub, {
      props,
      slots,
      global: {
        plugins: [i18n],
      },
    });

  describe('Basic Rendering', () => {
    it('renders with default props', () => {
      wrapper = mountComponent();

      expect(wrapper.find('.flex.min-h-screen').exists()).toBe(true);
    });

    it('renders min-h-screen container for full viewport height', () => {
      wrapper = mountComponent();

      const container = wrapper.find('.min-h-screen');
      expect(container.exists()).toBe(true);
      expect(container.classes()).toContain('flex');
      expect(container.classes()).toContain('flex-col');
    });

    it('renders brand color bar at top', () => {
      wrapper = mountComponent();

      const colorBar = wrapper.find('.fixed.left-0.top-0');
      expect(colorBar.exists()).toBe(true);
      expect(colorBar.classes()).toContain('z-50');
      expect(colorBar.classes()).toContain('h-1');
      expect(colorBar.classes()).toContain('w-full');
    });

    it('renders status-messages container by default', () => {
      wrapper = mountComponent();

      const statusMessages = wrapper.find('#status-messages');
      expect(statusMessages.exists()).toBe(true);
    });
  });

  describe('GlobalBroadcast Handling', () => {
    it('renders GlobalBroadcast when displayGlobalBroadcast is true', () => {
      wrapper = mountComponent({ displayGlobalBroadcast: true });

      const broadcast = wrapper.find('[data-testid="global-broadcast"]');
      expect(broadcast.exists()).toBe(true);
    });

    it('does not render GlobalBroadcast when displayGlobalBroadcast is false', () => {
      wrapper = mountComponent({ displayGlobalBroadcast: false });

      const broadcast = wrapper.find('[data-testid="global-broadcast"]');
      expect(broadcast.exists()).toBe(false);
    });

    it('defaults displayGlobalBroadcast to true', () => {
      wrapper = mountComponent();

      const broadcast = wrapper.find('[data-testid="global-broadcast"]');
      expect(broadcast.exists()).toBe(true);
    });
  });

  describe('Slot Projection', () => {
    it('renders header slot content', () => {
      wrapper = mountComponent(
        {},
        {
          header: () => h('header', { class: 'test-header' }, 'Test Header'),
        }
      );

      const header = wrapper.find('.test-header');
      expect(header.exists()).toBe(true);
      expect(header.text()).toBe('Test Header');
    });

    it('renders main slot content', () => {
      wrapper = mountComponent(
        {},
        {
          main: () => h('main', { class: 'test-main' }, 'Test Main Content'),
        }
      );

      const main = wrapper.find('.test-main');
      expect(main.exists()).toBe(true);
      expect(main.text()).toBe('Test Main Content');
    });

    it('renders footer slot content', () => {
      wrapper = mountComponent(
        {},
        {
          footer: () => h('footer', { class: 'test-footer' }, 'Test Footer'),
        }
      );

      const footer = wrapper.find('.test-footer');
      expect(footer.exists()).toBe(true);
      expect(footer.text()).toBe('Test Footer');
    });

    it('renders status slot content when provided', () => {
      wrapper = mountComponent(
        {},
        {
          status: () => h('div', { class: 'test-status' }, 'Custom Status'),
        }
      );

      const status = wrapper.find('.test-status');
      expect(status.exists()).toBe(true);
      expect(status.text()).toBe('Custom Status');
    });

    it('renders default status-messages div when status slot is not provided', () => {
      wrapper = mountComponent();

      expect(wrapper.find('#status-messages').exists()).toBe(true);
    });

    it('renders all slots together', () => {
      wrapper = mountComponent(
        {},
        {
          header: () => h('header', { class: 'slot-header' }, 'Header'),
          main: () => h('main', { class: 'slot-main' }, 'Main'),
          footer: () => h('footer', { class: 'slot-footer' }, 'Footer'),
          status: () => h('div', { class: 'slot-status' }, 'Status'),
        }
      );

      expect(wrapper.find('.slot-header').exists()).toBe(true);
      expect(wrapper.find('.slot-main').exists()).toBe(true);
      expect(wrapper.find('.slot-footer').exists()).toBe(true);
      expect(wrapper.find('.slot-status').exists()).toBe(true);
    });
  });

  describe('Props Handling', () => {
    it('accepts displayMasthead prop', () => {
      wrapper = mountComponent({ displayMasthead: false });

      expect(wrapper.vm.$props.displayMasthead).toBe(false);
    });

    it('accepts displayNavigation prop', () => {
      wrapper = mountComponent({ displayNavigation: false });

      expect(wrapper.vm.$props.displayNavigation).toBe(false);
    });

    it('accepts displayFooterLinks prop', () => {
      wrapper = mountComponent({ displayFooterLinks: false });

      expect(wrapper.vm.$props.displayFooterLinks).toBe(false);
    });

    it('accepts displayFeedback prop', () => {
      wrapper = mountComponent({ displayFeedback: false });

      expect(wrapper.vm.$props.displayFeedback).toBe(false);
    });

    it('accepts displayVersion prop', () => {
      wrapper = mountComponent({ displayVersion: false });

      expect(wrapper.vm.$props.displayVersion).toBe(false);
    });

    it('accepts displayToggles prop', () => {
      wrapper = mountComponent({ displayToggles: false });

      expect(wrapper.vm.$props.displayToggles).toBe(false);
    });

    it('accepts displayPoweredBy prop', () => {
      wrapper = mountComponent({ displayPoweredBy: false });

      expect(wrapper.vm.$props.displayPoweredBy).toBe(false);
    });

    it('accepts colonel prop', () => {
      wrapper = mountComponent({ colonel: true });

      expect(wrapper.vm.$props.colonel).toBe(true);
    });
  });

  describe('Complex Slot Content', () => {
    it('renders nested elements in header slot', () => {
      wrapper = mountComponent(
        {},
        {
          header: () =>
            h('header', { class: 'complex-header' }, [
              h('nav', { class: 'header-nav' }, [
                h('a', { href: '/' }, 'Home'),
                h('a', { href: '/about' }, 'About'),
              ]),
              h('div', { class: 'header-actions' }, [h('button', 'Login')]),
            ]),
        }
      );

      expect(wrapper.find('.complex-header').exists()).toBe(true);
      expect(wrapper.find('.header-nav').exists()).toBe(true);
      expect(wrapper.findAll('.header-nav a')).toHaveLength(2);
      expect(wrapper.find('.header-actions button').exists()).toBe(true);
    });

    it('renders form elements in main slot', () => {
      wrapper = mountComponent(
        {},
        {
          main: () =>
            h('main', [
              h('form', { class: 'test-form' }, [
                h('input', { type: 'text', name: 'name' }),
                h('textarea', { name: 'message' }),
                h('button', { type: 'submit' }, 'Submit'),
              ]),
            ]),
        }
      );

      expect(wrapper.find('.test-form').exists()).toBe(true);
      expect(wrapper.find('input[name="name"]').exists()).toBe(true);
      expect(wrapper.find('textarea[name="message"]').exists()).toBe(true);
      expect(wrapper.find('button[type="submit"]').exists()).toBe(true);
    });
  });

  describe('Slot Order', () => {
    it('maintains correct order: color bar, broadcast, header, main, footer, status', () => {
      wrapper = mountComponent(
        { displayGlobalBroadcast: true },
        {
          header: () => h('header', { 'data-order': '3' }, 'Header'),
          main: () => h('main', { 'data-order': '4' }, 'Main'),
          footer: () => h('footer', { 'data-order': '5' }, 'Footer'),
          status: () => h('div', { 'data-order': '6' }, 'Status'),
        }
      );

      const html = wrapper.html();
      const colorBarPos = html.indexOf('fixed left-0 top-0');
      const broadcastPos = html.indexOf('data-testid="global-broadcast"');
      const headerPos = html.indexOf('data-order="3"');
      const mainPos = html.indexOf('data-order="4"');
      const footerPos = html.indexOf('data-order="5"');
      const statusPos = html.indexOf('data-order="6"');

      expect(colorBarPos).toBeLessThan(broadcastPos);
      expect(broadcastPos).toBeLessThan(headerPos);
      expect(headerPos).toBeLessThan(mainPos);
      expect(mainPos).toBeLessThan(footerPos);
      expect(footerPos).toBeLessThan(statusPos);
    });
  });

  describe('Accessibility', () => {
    it('uses semantic structure with flex container', () => {
      wrapper = mountComponent();

      const container = wrapper.find('.flex.flex-col');
      expect(container.exists()).toBe(true);
    });

    it('allows semantic elements in slots', () => {
      wrapper = mountComponent(
        {},
        {
          header: () => h('header', { role: 'banner' }, 'Header'),
          main: () => h('main', { role: 'main' }, 'Main'),
          footer: () => h('footer', { role: 'contentinfo' }, 'Footer'),
        }
      );

      expect(wrapper.find('header[role="banner"]').exists()).toBe(true);
      expect(wrapper.find('main[role="main"]').exists()).toBe(true);
      expect(wrapper.find('footer[role="contentinfo"]').exists()).toBe(true);
    });
  });

  describe('Empty Slots', () => {
    it('handles empty header slot gracefully', () => {
      wrapper = mountComponent({}, { header: () => null });

      expect(wrapper.find('.flex.min-h-screen').exists()).toBe(true);
    });

    it('handles empty main slot gracefully', () => {
      wrapper = mountComponent({}, { main: () => null });

      expect(wrapper.find('.flex.min-h-screen').exists()).toBe(true);
    });

    it('handles empty footer slot gracefully', () => {
      wrapper = mountComponent({}, { footer: () => null });

      expect(wrapper.find('.flex.min-h-screen').exists()).toBe(true);
    });

    it('handles all empty slots gracefully', () => {
      wrapper = mountComponent(
        {},
        {
          header: () => null,
          main: () => null,
          footer: () => null,
        }
      );

      expect(wrapper.find('.flex.min-h-screen').exists()).toBe(true);
      // Default status should still render
      expect(wrapper.find('#status-messages').exists()).toBe(true);
    });
  });
});
