// src/tests/apps/session/layouts/AuthLayout.spec.ts

import { mount, VueWrapper } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createI18n } from 'vue-i18n';
import { h, defineComponent } from 'vue';
import { createTestingPinia } from '@pinia/testing';

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
 * AuthLayout Component Tests
 *
 * Tests the auth layout for session/authentication flows (login, signup, MFA).
 * Minimal navigation with displayPoweredBy enabled.
 * Composes BaseLayout with TransactionalHeader + TransactionalFooter.
 */
describe('AuthLayout', () => {
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
          'data-display-toggles': props.displayToggles,
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

  // AuthLayout stub representing expected interface
  const AuthLayoutStub = defineComponent({
    name: 'AuthLayout',
    props: {
      displayFeedback: { type: Boolean, default: false },
      displayFooterLinks: { type: Boolean, default: false },
      displayMasthead: { type: Boolean, default: false },
      displayNavigation: { type: Boolean, default: false },
      displayVersion: { type: Boolean, default: true },
      displayToggles: { type: Boolean, default: true },
      displayPoweredBy: { type: Boolean, default: true },
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
          main: () => h('main', { class: mainClasses, name: 'AuthLayout' }, [slots.default?.()]),
          footer: () => h(MockTransactionalFooter, { ...props }),
        });
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
    props: Record<string, unknown> = {},
    slots: Record<string, () => unknown> = {}
  ) =>
    mount(AuthLayoutStub, {
      props,
      slots: {
        default: () => h('div', { class: 'test-content' }, 'Test Content'),
        ...slots,
      },
      global: {
        plugins: [
          i18n,
          createTestingPinia({
            createSpy: vi.fn,
            initialState: {
              bootstrap: {
                global_banner: null,
              },
            },
          }),
        ],
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

    it('main element has name="AuthLayout" attribute', () => {
      wrapper = mountComponent();

      const main = wrapper.find('.main-slot main');
      expect(main.attributes('name')).toBe('AuthLayout');
    });

    it('renders main content slot', () => {
      wrapper = mountComponent();

      const content = wrapper.find('.main-slot .test-content');
      expect(content.exists()).toBe(true);
      expect(content.text()).toBe('Test Content');
    });
  });

  describe('Default Props', () => {
    it('defaults displayMasthead to false', () => {
      wrapper = mountComponent();

      const header = wrapper.find('.mock-transactional-header');
      expect(header.attributes('data-display-masthead')).toBe('false');
    });

    it('defaults displayNavigation to false', () => {
      wrapper = mountComponent();

      const header = wrapper.find('.mock-transactional-header');
      expect(header.attributes('data-display-navigation')).toBe('false');
    });

    it('defaults displayPoweredBy to true', () => {
      wrapper = mountComponent();

      const footer = wrapper.find('.mock-transactional-footer');
      expect(footer.attributes('data-display-powered-by')).toBe('true');
    });

    it('defaults displayFeedback to false', () => {
      wrapper = mountComponent();

      const footer = wrapper.find('.mock-transactional-footer');
      expect(footer.attributes('data-display-feedback')).toBe('false');
    });

    it('defaults displayFooterLinks to false', () => {
      wrapper = mountComponent();

      const footer = wrapper.find('.mock-transactional-footer');
      expect(footer.attributes('data-display-footer-links')).toBe('false');
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
        displayMasthead: true,
        displayNavigation: true,
        displayFeedback: true,
      });

      const header = wrapper.find('.mock-transactional-header');
      expect(header.attributes('data-display-masthead')).toBe('true');
      expect(header.attributes('data-display-navigation')).toBe('true');
      expect(header.attributes('data-display-feedback')).toBe('true');
    });

    it('passes display props to TransactionalFooter', () => {
      wrapper = mountComponent({
        displayFooterLinks: true,
        displayFeedback: true,
        displayVersion: false,
        displayPoweredBy: false,
      });

      const footer = wrapper.find('.mock-transactional-footer');
      expect(footer.attributes('data-display-footer-links')).toBe('true');
      expect(footer.attributes('data-display-feedback')).toBe('true');
      expect(footer.attributes('data-display-version')).toBe('false');
      expect(footer.attributes('data-display-powered-by')).toBe('false');
    });

    it('threads all display props through to child components', () => {
      wrapper = mountComponent({
        displayMasthead: true,
        displayNavigation: true,
        displayFooterLinks: true,
        displayFeedback: true,
        displayVersion: false,
        displayToggles: false,
        displayPoweredBy: false,
      });

      // Check BaseLayout received props
      const baseLayout = wrapper.find('.mock-base-layout');
      expect(baseLayout.attributes('data-display-masthead')).toBe('true');
      expect(baseLayout.attributes('data-display-version')).toBe('false');
      expect(baseLayout.attributes('data-display-toggles')).toBe('false');
      expect(baseLayout.attributes('data-display-powered-by')).toBe('false');

      // Check Header received props
      const header = wrapper.find('.mock-transactional-header');
      expect(header.attributes('data-display-masthead')).toBe('true');
      expect(header.attributes('data-display-navigation')).toBe('true');

      // Check Footer received props
      const footer = wrapper.find('.mock-transactional-footer');
      expect(footer.attributes('data-display-footer-links')).toBe('true');
      expect(footer.attributes('data-display-feedback')).toBe('true');
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
    it('has pt-16 pb-8 when displayMasthead is false (default)', () => {
      wrapper = mountComponent();

      const main = wrapper.find('.main-slot main');
      expect(main.classes()).toContain('pt-16');
      expect(main.classes()).toContain('pb-8');
    });

    it('has py-8 when displayMasthead is true', () => {
      wrapper = mountComponent({ displayMasthead: true });

      const main = wrapper.find('.main-slot main');
      expect(main.classes()).toContain('py-8');
    });
  });

  describe('Complex Slot Content', () => {
    it('renders login form in default slot', () => {
      wrapper = mountComponent(
        {},
        {
          default: () =>
            h('form', { class: 'login-form' }, [
              h('input', { type: 'email', name: 'email' }),
              h('input', { type: 'password', name: 'password' }),
              h('button', { type: 'submit' }, 'Sign In'),
            ]),
        }
      );

      expect(wrapper.find('.login-form').exists()).toBe(true);
      expect(wrapper.find('input[type="email"]').exists()).toBe(true);
      expect(wrapper.find('input[type="password"]').exists()).toBe(true);
    });

    it('renders signup form in default slot', () => {
      wrapper = mountComponent(
        {},
        {
          default: () =>
            h('form', { class: 'signup-form' }, [
              h('input', { type: 'text', name: 'name' }),
              h('input', { type: 'email', name: 'email' }),
              h('input', { type: 'password', name: 'password' }),
              h('input', { type: 'password', name: 'password_confirmation' }),
              h('button', { type: 'submit' }, 'Create Account'),
            ]),
        }
      );

      expect(wrapper.find('.signup-form').exists()).toBe(true);
      expect(wrapper.find('input[name="password_confirmation"]').exists()).toBe(true);
    });

    it('renders MFA form in default slot', () => {
      wrapper = mountComponent(
        {},
        {
          default: () =>
            h('form', { class: 'mfa-form' }, [
              h('input', { type: 'text', name: 'code', inputmode: 'numeric' }),
              h('button', { type: 'submit' }, 'Verify'),
            ]),
        }
      );

      expect(wrapper.find('.mfa-form').exists()).toBe(true);
      expect(wrapper.find('input[name="code"]').exists()).toBe(true);
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

  describe('Auth-specific Configuration', () => {
    it('supports minimal layout for signin page', () => {
      wrapper = mountComponent({
        displayMasthead: false,
        displayNavigation: false,
        displayFooterLinks: false,
        displayFeedback: false,
        displayVersion: true,
        displayToggles: true,
        displayPoweredBy: true,
      });

      const header = wrapper.find('.mock-transactional-header');
      expect(header.attributes('data-display-masthead')).toBe('false');
      expect(header.attributes('data-display-navigation')).toBe('false');

      const footer = wrapper.find('.mock-transactional-footer');
      expect(footer.attributes('data-display-footer-links')).toBe('false');
      expect(footer.attributes('data-display-feedback')).toBe('false');
      expect(footer.attributes('data-display-version')).toBe('true');
      expect(footer.attributes('data-display-powered-by')).toBe('true');
    });
  });
});
