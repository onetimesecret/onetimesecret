// src/tests/shared/components/layout/ManagementHeader.spec.ts

import { mount, VueWrapper } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createTestingPinia } from '@pinia/testing';
import ManagementHeader from '@/shared/components/layout/ManagementHeader.vue';
import { nextTick } from 'vue';
import { createTestI18n } from '@tests/setup';

// Mock MastHead component
vi.mock('@/shared/components/layout/MastHead.vue', () => ({
  default: {
    name: 'MastHead',
    template: `<div class="masthead" :data-display-masthead="displayMasthead" :data-display-navigation="displayNavigation">
      <slot name="context-switchers"></slot>
    </div>`,
    props: ['displayMasthead', 'displayNavigation', 'displayPrimaryNav', 'colonel', 'logo'],
  },
}));

// Mock ImprovedPrimaryNav component
vi.mock('@/shared/components/navigation/ImprovedPrimaryNav.vue', () => ({
  default: {
    name: 'ImprovedPrimaryNav',
    template: '<nav class="primary-nav">Primary Navigation</nav>',
  },
}));

// Mock i18n
const i18n = createTestI18n();

describe('ManagementHeader', () => {
  let wrapper: VueWrapper;

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
    storeState: Record<string, unknown> = {}
  ) => mount(ManagementHeader, {
      props: {
        displayMasthead: true,
        displayNavigation: true,
        displayPrimaryNav: true,
        colonel: false,
        ...props,
      },
      global: {
        plugins: [
          i18n,
          createTestingPinia({
            createSpy: vi.fn,
            initialState: {
              bootstrap: {
                authenticated: storeState.authenticated ?? true,
                ui: {
                  header:
                    storeState.header !== undefined
                      ? storeState.header
                      : { navigation: { enabled: true } },
                },
              },
            },
          }),
        ],
      },
      slots: {
        default: '<div class="slot-content">Context Bar Content</div>',
      },
    });

  describe('Slot Passthrough', () => {
    it('passes default slot content to MastHead context-switchers slot', async () => {
      wrapper = mountComponent({}, { authenticated: true });
      await nextTick();

      const masthead = wrapper.find('.masthead');
      expect(masthead.exists()).toBe(true);
      expect(masthead.html()).toContain('slot-content');
      expect(masthead.html()).toContain('Context Bar Content');
    });

    it('renders MastHead when displayMasthead is true', async () => {
      wrapper = mountComponent({ displayMasthead: true });
      await nextTick();

      const masthead = wrapper.find('.masthead');
      expect(masthead.exists()).toBe(true);
    });

    it('hides MastHead when displayMasthead is false', async () => {
      wrapper = mountComponent({ displayMasthead: false });
      await nextTick();

      const masthead = wrapper.find('.masthead');
      expect(masthead.exists()).toBe(false);
    });
  });

  describe('Primary Nav Visibility', () => {
    it('shows primary nav when authenticated and displayPrimaryNav is true', async () => {
      wrapper = mountComponent(
        { displayNavigation: true, displayPrimaryNav: true },
        { authenticated: true }
      );
      await nextTick();

      const primaryNav = wrapper.find('.primary-nav');
      expect(primaryNav.exists()).toBe(true);
    });

    it('hides primary nav when displayNavigation is false', async () => {
      wrapper = mountComponent(
        { displayNavigation: false, displayPrimaryNav: true },
        { authenticated: true }
      );
      await nextTick();

      const primaryNav = wrapper.find('.primary-nav');
      expect(primaryNav.exists()).toBe(false);
    });

    it('hides primary nav when displayPrimaryNav is false', async () => {
      wrapper = mountComponent(
        { displayNavigation: true, displayPrimaryNav: false },
        { authenticated: true }
      );
      await nextTick();

      const primaryNav = wrapper.find('.primary-nav');
      expect(primaryNav.exists()).toBe(false);
    });

    it('hides primary nav for unauthenticated users', async () => {
      wrapper = mountComponent(
        { displayNavigation: true, displayPrimaryNav: true },
        { authenticated: false }
      );
      await nextTick();

      const primaryNav = wrapper.find('.primary-nav');
      expect(primaryNav.exists()).toBe(false);
    });
  });

  describe('Primary Nav md Breakpoint', () => {
    it('applies hidden md:block classes to primary nav container', async () => {
      wrapper = mountComponent(
        { displayNavigation: true, displayPrimaryNav: true },
        { authenticated: true }
      );
      await nextTick();

      // The container div around ImprovedPrimaryNav should have hidden md:block
      const navContainer = wrapper.find('.hidden.md\\:block');
      expect(navContainer.exists()).toBe(true);
    });
  });

  describe('Props Passthrough', () => {
    it('passes displayMasthead prop to MastHead', async () => {
      wrapper = mountComponent({ displayMasthead: true });
      await nextTick();

      const masthead = wrapper.find('.masthead');
      expect(masthead.attributes('data-display-masthead')).toBe('true');
    });

    it('passes displayNavigation prop to MastHead', async () => {
      wrapper = mountComponent({ displayNavigation: true });
      await nextTick();

      const masthead = wrapper.find('.masthead');
      expect(masthead.attributes('data-display-navigation')).toBe('true');
    });
  });

  describe('Layout Structure', () => {
    it('renders header element as root', async () => {
      wrapper = mountComponent();
      await nextTick();

      const header = wrapper.find('header');
      expect(header.exists()).toBe(true);
    });

    it('applies border and background classes to header', async () => {
      wrapper = mountComponent();
      await nextTick();

      const header = wrapper.find('header');
      expect(header.classes()).toContain('border-b');
      expect(header.classes()).toContain('bg-white');
    });

    it('uses max-w-4xl container for content', async () => {
      wrapper = mountComponent();
      await nextTick();

      const container = wrapper.find('.max-w-4xl');
      expect(container.exists()).toBe(true);
    });
  });

  // HEADER_ENABLED gate (#3362): operator config collapses the entire
  // <header> banner landmark — no empty landmark, no whitespace band.
  describe('HEADER_ENABLED gate', () => {
    it('removes the <header> element when header.enabled is false', async () => {
      wrapper = mountComponent({}, { header: { enabled: false } });
      await nextTick();

      expect(wrapper.find('header').exists()).toBe(false);
      // Content collapses with the landmark, not merely emptied.
      expect(wrapper.find('.masthead').exists()).toBe(false);
    });

    it('renders the <header> element when header.enabled is true', async () => {
      wrapper = mountComponent({}, { header: { enabled: true } });
      await nextTick();

      expect(wrapper.find('header').exists()).toBe(true);
    });

    it('renders the <header> element when header.enabled is omitted (default true)', async () => {
      wrapper = mountComponent({}, { header: { navigation: { enabled: true } } });
      await nextTick();

      expect(wrapper.find('header').exists()).toBe(true);
    });

    it('renders the <header> element when header config is entirely absent (store getter undefined)', async () => {
      // The bootstrap store returns undefined when state.ui.header is unset;
      // headerConfig?.enabled !== false must treat that as enabled, not hidden.
      wrapper = mountComponent({}, { header: null });
      await nextTick();

      expect(wrapper.find('header').exists()).toBe(true);
    });
  });
});
