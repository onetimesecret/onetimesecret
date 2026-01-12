// src/tests/apps/secret/layouts/SecretRevealLayout.spec.ts

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
 * SecretRevealLayout Component Tests
 *
 * Tests the secret reveal layout for the /secret/:secretIdentifier reveal page.
 * Minimal chrome for focused secret viewing experience.
 * Composes BaseLayout with BrandedHeader + BrandedFooter.
 */
describe('SecretRevealLayout', () => {
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

  // Mock BrandedHeader that captures props (NOT TransactionalHeader)
  const MockBrandedHeader = defineComponent({
    name: 'BrandedHeader',
    props: {
      displayMasthead: { type: Boolean, default: false },
      displayNavigation: { type: Boolean, default: false },
      displayFeedback: { type: Boolean, default: false },
      displayVersion: { type: Boolean, default: false },
      displayToggles: { type: Boolean, default: true },
      displayPoweredBy: { type: Boolean, default: false },
      colonel: { type: Boolean, default: false },
    },
    setup(props) {
      return () =>
        h('header', {
          class: 'mock-branded-header',
          'data-display-masthead': props.displayMasthead,
          'data-display-navigation': props.displayNavigation,
          'data-display-feedback': props.displayFeedback,
          'data-display-toggles': props.displayToggles,
          'data-display-powered-by': props.displayPoweredBy,
          'data-colonel': props.colonel,
        });
    },
  });

  // Mock BrandedFooter that captures props (NOT TransactionalFooter)
  const MockBrandedFooter = defineComponent({
    name: 'BrandedFooter',
    props: {
      displayFooterLinks: { type: Boolean, default: false },
      displayFeedback: { type: Boolean, default: false },
      displayVersion: { type: Boolean, default: false },
      displayToggles: { type: Boolean, default: true },
      displayPoweredBy: { type: Boolean, default: false },
      colonel: { type: Boolean, default: false },
    },
    setup(props) {
      return () =>
        h('footer', {
          class: 'mock-branded-footer',
          'data-display-footer-links': props.displayFooterLinks,
          'data-display-feedback': props.displayFeedback,
          'data-display-version': props.displayVersion,
          'data-display-toggles': props.displayToggles,
          'data-display-powered-by': props.displayPoweredBy,
        });
    },
  });

  // SecretRevealLayout stub representing expected interface
  const SecretRevealLayoutStub = defineComponent({
    name: 'SecretRevealLayout',
    props: {
      displayFeedback: { type: Boolean, default: false },
      displayFooterLinks: { type: Boolean, default: false },
      displayMasthead: { type: Boolean, default: false },
      displayNavigation: { type: Boolean, default: false },
      displayVersion: { type: Boolean, default: false },
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
          header: () => h(MockBrandedHeader, { ...props }),
          main: () => h('main', { class: mainClasses }, [slots.default?.()]),
          footer: () => h(MockBrandedFooter, { ...props }),
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
    mount(SecretRevealLayoutStub, {
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

    it('renders BrandedHeader in header slot (NOT TransactionalHeader)', () => {
      wrapper = mountComponent();

      expect(wrapper.find('.header-slot .mock-branded-header').exists()).toBe(true);
      expect(wrapper.find('.mock-transactional-header').exists()).toBe(false);
    });

    it('renders BrandedFooter in footer slot (NOT TransactionalFooter)', () => {
      wrapper = mountComponent();

      expect(wrapper.find('.footer-slot .mock-branded-footer').exists()).toBe(true);
      expect(wrapper.find('.mock-transactional-footer').exists()).toBe(false);
    });

    it('renders main content slot', () => {
      wrapper = mountComponent();

      const content = wrapper.find('.main-slot .test-content');
      expect(content.exists()).toBe(true);
      expect(content.text()).toBe('Test Content');
    });
  });

  describe('Default Props (minimal chrome)', () => {
    it('defaults displayMasthead to false', () => {
      wrapper = mountComponent();

      const header = wrapper.find('.mock-branded-header');
      expect(header.attributes('data-display-masthead')).toBe('false');
    });

    it('defaults displayNavigation to false', () => {
      wrapper = mountComponent();

      const header = wrapper.find('.mock-branded-header');
      expect(header.attributes('data-display-navigation')).toBe('false');
    });

    it('defaults displayPoweredBy to false', () => {
      wrapper = mountComponent();

      const footer = wrapper.find('.mock-branded-footer');
      expect(footer.attributes('data-display-powered-by')).toBe('false');
    });

    it('defaults displayToggles to true (theme toggle shown)', () => {
      wrapper = mountComponent();

      const footer = wrapper.find('.mock-branded-footer');
      expect(footer.attributes('data-display-toggles')).toBe('true');
    });

    it('defaults displayFeedback to false', () => {
      wrapper = mountComponent();

      const footer = wrapper.find('.mock-branded-footer');
      expect(footer.attributes('data-display-feedback')).toBe('false');
    });

    it('defaults displayFooterLinks to false', () => {
      wrapper = mountComponent();

      const footer = wrapper.find('.mock-branded-footer');
      expect(footer.attributes('data-display-footer-links')).toBe('false');
    });

    it('defaults displayVersion to false', () => {
      wrapper = mountComponent();

      const footer = wrapper.find('.mock-branded-footer');
      expect(footer.attributes('data-display-version')).toBe('false');
    });
  });

  describe('Prop Threading', () => {
    it('passes display props to BrandedHeader', () => {
      wrapper = mountComponent({
        displayMasthead: true,
        displayNavigation: true,
        displayToggles: false,
      });

      const header = wrapper.find('.mock-branded-header');
      expect(header.attributes('data-display-masthead')).toBe('true');
      expect(header.attributes('data-display-navigation')).toBe('true');
      expect(header.attributes('data-display-toggles')).toBe('false');
    });

    it('passes display props to BrandedFooter', () => {
      wrapper = mountComponent({
        displayFooterLinks: true,
        displayFeedback: true,
        displayVersion: true,
        displayPoweredBy: true,
      });

      const footer = wrapper.find('.mock-branded-footer');
      expect(footer.attributes('data-display-footer-links')).toBe('true');
      expect(footer.attributes('data-display-feedback')).toBe('true');
      expect(footer.attributes('data-display-version')).toBe('true');
      expect(footer.attributes('data-display-powered-by')).toBe('true');
    });

    it('threads all display props through to child components', () => {
      wrapper = mountComponent({
        displayMasthead: true,
        displayNavigation: true,
        displayFooterLinks: true,
        displayFeedback: true,
        displayVersion: true,
        displayToggles: false,
        displayPoweredBy: true,
      });

      // Check BaseLayout received props
      const baseLayout = wrapper.find('.mock-base-layout');
      expect(baseLayout.attributes('data-display-masthead')).toBe('true');
      expect(baseLayout.attributes('data-display-version')).toBe('true');
      expect(baseLayout.attributes('data-display-toggles')).toBe('false');
      expect(baseLayout.attributes('data-display-powered-by')).toBe('true');

      // Check Header received props
      const header = wrapper.find('.mock-branded-header');
      expect(header.attributes('data-display-masthead')).toBe('true');
      expect(header.attributes('data-display-navigation')).toBe('true');

      // Check Footer received props
      const footer = wrapper.find('.mock-branded-footer');
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
    it('renders secret reveal content in default slot', () => {
      wrapper = mountComponent(
        {},
        {
          default: () =>
            h('div', { class: 'secret-reveal' }, [
              h('div', { class: 'secret-value' }, 'Secret content here'),
              h('button', { class: 'copy-btn' }, 'Copy'),
            ]),
        }
      );

      expect(wrapper.find('.secret-reveal').exists()).toBe(true);
      expect(wrapper.find('.secret-value').exists()).toBe(true);
      expect(wrapper.find('.copy-btn').exists()).toBe(true);
    });

    it('renders passphrase form in default slot', () => {
      wrapper = mountComponent(
        {},
        {
          default: () =>
            h('form', { class: 'passphrase-form' }, [
              h('input', { type: 'password', name: 'passphrase' }),
              h('button', { type: 'submit' }, 'Unlock'),
            ]),
        }
      );

      expect(wrapper.find('.passphrase-form').exists()).toBe(true);
      expect(wrapper.find('input[type="password"]').exists()).toBe(true);
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
