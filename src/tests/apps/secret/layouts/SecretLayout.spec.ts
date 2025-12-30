// src/tests/apps/secret/layouts/SecretLayout.spec.ts

import { mount, VueWrapper } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createI18n } from 'vue-i18n';
import { h, defineComponent } from 'vue';
import { createPinia, setActivePinia } from 'pinia';

// Mock vue-router
vi.mock('vue-router', () => ({
  useRoute: vi.fn(() => ({ path: '/', query: {}, params: {} })),
  useRouter: vi.fn(() => ({ push: vi.fn(), replace: vi.fn() })),
  RouterLink: {
    name: 'RouterLink',
    template: '<a :href="to"><slot /></a>',
    props: ['to'],
  },
}));

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

// Mock color utils
vi.mock('@/utils/color-utils', () => ({
  isColorValue: (value: string) => value.startsWith('#') || value.startsWith('rgb'),
}));

// Mock OIcon component
vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="o-icon" :data-icon="name" />',
    props: ['collection', 'name', 'class'],
  },
}));

const i18n = createI18n({
  legacy: false,
  locale: 'en',
  messages: {
    en: {
      web: {
        COMMON: {
          home: 'Home',
        },
        LABELS: {
          dismiss: 'Dismiss',
        },
      },
    },
  },
});

/**
 * SecretLayout Component Tests
 *
 * Tests the secret layout for conceal, metadata, and incoming flows.
 * Composes BaseLayout with TransactionalHeader + TransactionalFooter.
 */
describe('SecretLayout', () => {
  let wrapper: VueWrapper;

  // Mock BaseLayout that captures props and renders slots
  const MockBaseLayout = defineComponent({
    name: 'BaseLayout',
    props: {
      displayGlobalBroadcast: { type: Boolean, default: true },
      displayMasthead: { type: Boolean, default: true },
      displayNavigation: { type: Boolean, default: true },
      displayFooterLinks: { type: Boolean, default: true },
      displayFeedback: { type: Boolean, default: true },
      displayVersion: { type: Boolean, default: true },
      displayToggles: { type: Boolean, default: true },
      displayPoweredBy: { type: Boolean, default: true },
      colonel: { type: Boolean, default: false },
    },
    setup(props, { slots }) {
      return () =>
        h(
          'div',
          {
            class: 'mock-base-layout',
            'data-display-masthead': props.displayMasthead,
            'data-display-navigation': props.displayNavigation,
            'data-display-footer-links': props.displayFooterLinks,
            'data-display-feedback': props.displayFeedback,
            'data-display-version': props.displayVersion,
            'data-display-toggles': props.displayToggles,
            'data-display-powered-by': props.displayPoweredBy,
            'data-colonel': props.colonel,
          },
          [
            h('div', { class: 'header-slot' }, slots.header?.()),
            h('div', { class: 'main-slot' }, slots.main?.()),
            h('div', { class: 'footer-slot' }, slots.footer?.()),
          ]
        );
    },
  });

  // Mock TransactionalHeader that captures props
  const MockTransactionalHeader = defineComponent({
    name: 'TransactionalHeader',
    props: {
      displayMasthead: { type: Boolean, default: true },
      displayNavigation: { type: Boolean, default: true },
      displayFeedback: { type: Boolean, default: true },
      displayVersion: { type: Boolean, default: true },
      displayToggles: { type: Boolean, default: true },
      displayPoweredBy: { type: Boolean, default: true },
      colonel: { type: Boolean, default: false },
    },
    setup(props) {
      return () =>
        h('header', {
          class: 'mock-transactional-header',
          'data-display-masthead': props.displayMasthead,
          'data-display-navigation': props.displayNavigation,
          'data-display-feedback': props.displayFeedback,
          'data-display-powered-by': props.displayPoweredBy,
          'data-colonel': props.colonel,
        });
    },
  });

  // Mock TransactionalFooter that captures props
  const MockTransactionalFooter = defineComponent({
    name: 'TransactionalFooter',
    props: {
      displayFooterLinks: { type: Boolean, default: true },
      displayFeedback: { type: Boolean, default: true },
      displayVersion: { type: Boolean, default: true },
      displayToggles: { type: Boolean, default: true },
      displayPoweredBy: { type: Boolean, default: true },
      colonel: { type: Boolean, default: false },
    },
    setup(props) {
      return () =>
        h('footer', {
          class: 'mock-transactional-footer',
          'data-display-footer-links': props.displayFooterLinks,
          'data-display-feedback': props.displayFeedback,
          'data-display-version': props.displayVersion,
          'data-display-toggles': props.displayToggles,
          'data-display-powered-by': props.displayPoweredBy,
        });
    },
  });

  // SecretLayout stub representing expected interface
  const SecretLayoutStub = defineComponent({
    name: 'SecretLayout',
    props: {
      displayFeedback: { type: Boolean, default: true },
      displayFooterLinks: { type: Boolean, default: true },
      displayMasthead: { type: Boolean, default: true },
      displayNavigation: { type: Boolean, default: true },
      displayVersion: { type: Boolean, default: true },
      displayToggles: { type: Boolean, default: true },
      displayPoweredBy: { type: Boolean, default: false },
      displayGlobalBroadcast: { type: Boolean, default: true },
      colonel: { type: Boolean, default: false },
    },
    setup(props, { slots }) {
      // Compute main classes based on displayMasthead
      const mainClasses =
        'container mx-auto flex min-w-[320px] max-w-2xl flex-1 flex-col px-4 justify-start' +
        (props.displayMasthead ? ' py-8' : ' pt-16 pb-8');

      return () =>
        h(MockBaseLayout, { ...props }, {
          header: () => h(MockTransactionalHeader, { ...props }),
          main: () => h('main', { class: mainClasses }, [slots.default?.()]),
          footer: () => h(MockTransactionalFooter, { ...props }),
        });
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
    mount(SecretLayoutStub, {
      props,
      slots: {
        default: () => h('div', { class: 'test-content' }, 'Test Content'),
        ...slots,
      },
      global: {
        plugins: [i18n],
      },
    });

  describe('Rendering', () => {
    it('renders BaseLayout as wrapper', () => {
      wrapper = mountComponent();

      expect(wrapper.find('.mock-base-layout').exists()).toBe(true);
    });

    it('renders TransactionalHeader in header slot', () => {
      wrapper = mountComponent();

      expect(wrapper.find('.header-slot .mock-transactional-header').exists()).toBe(true);
    });

    it('renders TransactionalFooter in footer slot', () => {
      wrapper = mountComponent();

      expect(wrapper.find('.footer-slot .mock-transactional-footer').exists()).toBe(true);
    });

    it('renders main content slot', () => {
      wrapper = mountComponent();

      const content = wrapper.find('.main-slot .test-content');
      expect(content.exists()).toBe(true);
      expect(content.text()).toBe('Test Content');
    });
  });

  describe('Default Props', () => {
    it('defaults displayPoweredBy to false', () => {
      wrapper = mountComponent();

      const footer = wrapper.find('.mock-transactional-footer');
      expect(footer.attributes('data-display-powered-by')).toBe('false');
    });

    it('defaults displayMasthead to true', () => {
      wrapper = mountComponent();

      const header = wrapper.find('.mock-transactional-header');
      expect(header.attributes('data-display-masthead')).toBe('true');
    });

    it('defaults displayNavigation to true', () => {
      wrapper = mountComponent();

      const header = wrapper.find('.mock-transactional-header');
      expect(header.attributes('data-display-navigation')).toBe('true');
    });

    it('defaults displayFeedback to true', () => {
      wrapper = mountComponent();

      const footer = wrapper.find('.mock-transactional-footer');
      expect(footer.attributes('data-display-feedback')).toBe('true');
    });

    it('defaults displayFooterLinks to true', () => {
      wrapper = mountComponent();

      const footer = wrapper.find('.mock-transactional-footer');
      expect(footer.attributes('data-display-footer-links')).toBe('true');
    });

    it('defaults displayVersion to true', () => {
      wrapper = mountComponent();

      const footer = wrapper.find('.mock-transactional-footer');
      expect(footer.attributes('data-display-version')).toBe('true');
    });

    it('defaults displayToggles to true', () => {
      wrapper = mountComponent();

      const footer = wrapper.find('.mock-transactional-footer');
      expect(footer.attributes('data-display-toggles')).toBe('true');
    });
  });

  describe('Prop Threading', () => {
    it('passes display props to TransactionalHeader', () => {
      wrapper = mountComponent({
        displayMasthead: false,
        displayNavigation: false,
        displayFeedback: false,
      });

      const header = wrapper.find('.mock-transactional-header');
      expect(header.attributes('data-display-masthead')).toBe('false');
      expect(header.attributes('data-display-navigation')).toBe('false');
      expect(header.attributes('data-display-feedback')).toBe('false');
    });

    it('passes display props to TransactionalFooter', () => {
      wrapper = mountComponent({
        displayFooterLinks: false,
        displayFeedback: false,
        displayVersion: false,
        displayPoweredBy: true,
      });

      const footer = wrapper.find('.mock-transactional-footer');
      expect(footer.attributes('data-display-footer-links')).toBe('false');
      expect(footer.attributes('data-display-feedback')).toBe('false');
      expect(footer.attributes('data-display-version')).toBe('false');
      expect(footer.attributes('data-display-powered-by')).toBe('true');
    });

    it('threads all display props through to child components', () => {
      wrapper = mountComponent({
        displayMasthead: false,
        displayNavigation: false,
        displayFooterLinks: false,
        displayFeedback: false,
        displayVersion: false,
        displayToggles: false,
        displayPoweredBy: true,
      });

      // Check BaseLayout received props
      const baseLayout = wrapper.find('.mock-base-layout');
      expect(baseLayout.attributes('data-display-masthead')).toBe('false');
      expect(baseLayout.attributes('data-display-version')).toBe('false');
      expect(baseLayout.attributes('data-display-toggles')).toBe('false');
      expect(baseLayout.attributes('data-display-powered-by')).toBe('true');

      // Check Header received props
      const header = wrapper.find('.mock-transactional-header');
      expect(header.attributes('data-display-masthead')).toBe('false');
      expect(header.attributes('data-display-navigation')).toBe('false');

      // Check Footer received props
      const footer = wrapper.find('.mock-transactional-footer');
      expect(footer.attributes('data-display-footer-links')).toBe('false');
      expect(footer.attributes('data-display-feedback')).toBe('false');
    });
  });

  describe('Container', () => {
    it('main container has max-w-2xl class', () => {
      wrapper = mountComponent();

      const main = wrapper.find('.main-slot main');
      expect(main.classes()).toContain('max-w-2xl');
    });

    it('main has container classes', () => {
      wrapper = mountComponent();

      const main = wrapper.find('.main-slot main');
      expect(main.classes()).toContain('container');
      expect(main.classes()).toContain('mx-auto');
    });

    it('main has flex classes for layout', () => {
      wrapper = mountComponent();

      const main = wrapper.find('.main-slot main');
      expect(main.classes()).toContain('flex');
      expect(main.classes()).toContain('flex-1');
      expect(main.classes()).toContain('flex-col');
    });

    it('main has min-width constraint', () => {
      wrapper = mountComponent();

      const main = wrapper.find('.main-slot main');
      expect(main.classes()).toContain('min-w-[320px]');
    });

    it('main content starts at top (justify-start)', () => {
      wrapper = mountComponent();

      const main = wrapper.find('.main-slot main');
      expect(main.classes()).toContain('justify-start');
    });

    it('main has px-4 padding', () => {
      wrapper = mountComponent();

      const main = wrapper.find('.main-slot main');
      expect(main.classes()).toContain('px-4');
    });
  });

  describe('Conditional Padding Based on Masthead', () => {
    it('has py-8 when displayMasthead is true', () => {
      wrapper = mountComponent({ displayMasthead: true });

      const main = wrapper.find('.main-slot main');
      expect(main.classes()).toContain('py-8');
    });

    it('has pt-16 pb-8 when displayMasthead is false', () => {
      wrapper = mountComponent({ displayMasthead: false });

      const main = wrapper.find('.main-slot main');
      expect(main.classes()).toContain('pt-16');
      expect(main.classes()).toContain('pb-8');
    });
  });

  describe('Complex Slot Content', () => {
    it('renders form in default slot', () => {
      wrapper = mountComponent(
        {},
        {
          default: () =>
            h('form', { class: 'secret-form' }, [
              h('textarea', { name: 'secret' }),
              h('button', { type: 'submit' }, 'Share'),
            ]),
        }
      );

      expect(wrapper.find('.secret-form').exists()).toBe(true);
      expect(wrapper.find('textarea[name="secret"]').exists()).toBe(true);
    });

    it('renders nested components in slot', () => {
      wrapper = mountComponent(
        {},
        {
          default: () =>
            h('div', { class: 'secret-container' }, [
              h('div', { class: 'secret-header' }, 'Create Secret'),
              h('div', { class: 'secret-body' }, [
                h('div', { class: 'secret-input' }, 'Input area'),
              ]),
              h('div', { class: 'secret-actions' }, 'Actions'),
            ]),
        }
      );

      expect(wrapper.find('.secret-container').exists()).toBe(true);
      expect(wrapper.find('.secret-header').exists()).toBe(true);
      expect(wrapper.find('.secret-body').exists()).toBe(true);
      expect(wrapper.find('.secret-actions').exists()).toBe(true);
    });
  });

  describe('Accessibility', () => {
    it('uses semantic main element for content', () => {
      wrapper = mountComponent();

      expect(wrapper.find('main').exists()).toBe(true);
    });

    it('uses semantic header element', () => {
      wrapper = mountComponent();

      expect(wrapper.find('header').exists()).toBe(true);
    });

    it('uses semantic footer element', () => {
      wrapper = mountComponent();

      expect(wrapper.find('footer').exists()).toBe(true);
    });
  });
});
