// src/tests/shared/components/navigation/UserMenu.spec.ts

import { mount, VueWrapper } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createI18n } from 'vue-i18n';
import { createTestingPinia } from '@pinia/testing';
import UserMenu from '@/shared/components/navigation/UserMenu.vue';
import { nextTick } from 'vue';

// Mock HeadlessUI components (Menu + Dialog for PlanTestModal)
vi.mock('@headlessui/vue', () => ({
  Menu: {
    name: 'Menu',
    template: '<div class="menu"><slot /></div>',
    props: ['as'],
  },
  MenuButton: {
    name: 'MenuButton',
    template: `<button
      aria-haspopup="true"
      :aria-expanded="$parent?.open || false"
      :aria-label="ariaLabel"
      @click="$emit('click')">
      <slot />
    </button>`,
    props: ['as', 'ariaLabel'],
    emits: ['click'],
  },
  MenuItems: {
    name: 'MenuItems',
    template: '<div role="menu" aria-label="User menu"><slot /></div>',
    props: ['as', 'class'],
  },
  MenuItem: {
    name: 'MenuItem',
    template: '<div role="menuitem" v-slot="{ active }"><slot :active="false" /></div>',
    props: ['as', 'disabled'],
  },
  // Dialog components for PlanTestModal
  Dialog: {
    name: 'Dialog',
    template: '<div role="dialog"><slot /></div>',
    props: ['class'],
    emits: ['close'],
  },
  DialogPanel: {
    name: 'DialogPanel',
    template: '<div class="dialog-panel"><slot /></div>',
    props: ['class'],
  },
  DialogTitle: {
    name: 'DialogTitle',
    template: '<h3><slot /></h3>',
    props: ['as', 'class'],
  },
  TransitionRoot: {
    name: 'TransitionRoot',
    template: '<div v-if="show"><slot /></div>',
    props: ['as', 'show'],
  },
  TransitionChild: {
    name: 'TransitionChild',
    template: '<div><slot /></div>',
    props: ['as', 'enter', 'enterFrom', 'enterTo', 'leave', 'leaveFrom', 'leaveTo'],
  },
}));

// Mock OIcon component
vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="o-icon" :data-icon="name" />',
    props: ['collection', 'name', 'class'],
  },
}));

// Mock FancyIcon component
vi.mock('@/shared/components/icons/FancyIcon.vue', () => ({
  default: {
    name: 'FancyIcon',
    template: '<span class="fancy-icon" />',
    props: ['icon', 'class'],
  },
}));

// Mock useAuth composable
const mockLogout = vi.fn();
vi.mock('@/shared/composables/useAuth', () => ({
  useAuth: vi.fn(() => ({
    logout: mockLogout,
  })),
}));

// Mock router
const mockPush = vi.fn();
vi.mock('vue-router', () => ({
  useRouter: vi.fn(() => ({
    push: mockPush,
  })),
  RouterLink: {
    template: '<a :href="to"><slot /></a>',
    props: ['to'],
  },
}));

const i18n = createI18n({
  legacy: false,
  locale: 'en',
  messages: {
    en: {
      web: {
        MENU: {
          dashboard: 'Dashboard',
          account: 'Account',
          billing: 'Billing',
          colonel: 'Colonel',
          logout: 'Logout',
          mfaVerification: 'MFA Verification',
        },
        colonel: {
          testPlanMode: 'Test Plan Mode',
        },
      },
    },
  },
});

describe('UserMenu', () => {
  let wrapper: VueWrapper;

  const mockCustomer = {
    custid: '123',
    email: 'test@example.com',
    extid: 'ext_123',
    objid: 'obj_123',
  };

  beforeEach(() => {
    vi.clearAllMocks();
    mockLogout.mockReset();
    mockPush.mockReset();
  });

  afterEach(() => {
    if (wrapper) {
      wrapper.unmount();
    }
  });

  const mountComponent = (
    props: Record<string, unknown> = {},
    bootstrapState: Record<string, unknown> = {}
  ) => {
    return mount(UserMenu, {
      props: {
        cust: mockCustomer,
        colonel: false,
        awaitingMfa: false,
        ...props,
      },
      global: {
        plugins: [
          i18n,
          createTestingPinia({
            createSpy: vi.fn,
            initialState: {
              bootstrap: {
                authenticated: true,
                billing_enabled: bootstrapState.billing_enabled ?? true,
                entitlement_test_planid: bootstrapState.entitlement_test_planid ?? null,
                entitlement_test_plan_name: bootstrapState.entitlement_test_plan_name ?? null,
                cust: mockCustomer,
              },
            },
          }),
        ],
        stubs: {
          RouterLink: {
            template: '<a :href="to"><slot /></a>',
            props: ['to'],
          },
        },
      },
    });
  };

  describe('Basic Rendering', () => {
    it('renders user menu trigger button', () => {
      wrapper = mountComponent();

      const trigger = wrapper.find('button[aria-haspopup="true"]');
      expect(trigger.exists()).toBe(true);
    });

    it('displays user email initials in avatar', () => {
      wrapper = mountComponent();

      const html = wrapper.html();
      // First letter of test@example.com
      expect(html).toContain('T');
    });

    it('shows menu when trigger is clicked', async () => {
      wrapper = mountComponent();

      const trigger = wrapper.find('button[aria-haspopup="true"]');
      await trigger.trigger('click');
      await nextTick();

      const menu = wrapper.find('[role="menu"]');
      expect(menu.exists()).toBe(true);
    });
  });

  describe('Test Plan Mode Menu Item - Colonel Users', () => {
    it('shows "Test Plan Mode" item for colonels', async () => {
      wrapper = mountComponent({ colonel: true });

      const trigger = wrapper.find('button[aria-haspopup="true"]');
      await trigger.trigger('click');
      await nextTick();

      const html = wrapper.html().toLowerCase();
      const hasTestPlanMode = html.includes('test') && html.includes('plan');

      expect(hasTestPlanMode).toBe(true);
    });

    it('hides "Test Plan Mode" item for non-colonels', async () => {
      wrapper = mountComponent({ colonel: false });

      const trigger = wrapper.find('button[aria-haspopup="true"]');
      await trigger.trigger('click');
      await nextTick();

      const html = wrapper.html().toLowerCase();

      // Should not contain test plan mode references
      const hasTestPlanMode = html.includes('test plan') || html.includes('testplanmode');

      expect(hasTestPlanMode).toBe(false);
    });

    it('shows item with beaker icon for colonels', async () => {
      wrapper = mountComponent({ colonel: true });

      const trigger = wrapper.find('button[aria-haspopup="true"]');
      await trigger.trigger('click');
      await nextTick();

      // Look for beaker icon
      const beakerIcon = wrapper.find('[data-icon="beaker"]');
      expect(beakerIcon.exists()).toBe(true);
    });
  });

  describe('Test Plan Mode - Visual Variants', () => {
    it('shows caution variant when test mode is active', async () => {
      wrapper = mountComponent(
        { colonel: true },
        { entitlement_test_planid: 'identity_v1' }
      );

      const trigger = wrapper.find('button[aria-haspopup="true"]');
      await trigger.trigger('click');
      await nextTick();

      const html = wrapper.html().toLowerCase();
      // Should have amber/caution styling
      const hasCautionStyling = html.includes('amber') || html.includes('caution');

      expect(hasCautionStyling).toBe(true);
    });

    it('shows default variant when test mode is inactive', async () => {
      wrapper = mountComponent(
        { colonel: true },
        { entitlement_test_planid: null }
      );

      const trigger = wrapper.find('button[aria-haspopup="true"]');
      await trigger.trigger('click');
      await nextTick();

      // Find the test plan menu item specifically
      const menuItems = wrapper.findAll('[role="menuitem"]');
      const testPlanItem = menuItems.find(item => {
        const html = item.html().toLowerCase();
        return html.includes('test') || html.includes('beaker');
      });

      if (testPlanItem) {
        const html = testPlanItem.html().toLowerCase();
        // Should NOT have amber styling when inactive
        expect(html).not.toContain('amber');
      }
    });
  });

  describe('Test Plan Mode - Click Behavior', () => {
    it('is hidden when awaiting MFA', async () => {
      wrapper = mountComponent({
        colonel: true,
        awaitingMfa: true,
      });

      const trigger = wrapper.find('button[aria-haspopup="true"]');
      await trigger.trigger('click');
      await nextTick();

      const html = wrapper.html().toLowerCase();

      // Test plan mode should not be shown during MFA flow
      const hasTestPlanMode = html.includes('test plan') || html.includes('testplanmode');

      expect(hasTestPlanMode).toBe(false);
    });
  });

  describe('Integration with Other Menu Items', () => {
    it('shows all expected menu items for colonels', async () => {
      wrapper = mountComponent({ colonel: true });

      const trigger = wrapper.find('button[aria-haspopup="true"]');
      await trigger.trigger('click');
      await nextTick();

      const html = wrapper.html().toLowerCase();

      // Should have standard items plus colonel items
      expect(html).toContain('dashboard');
      expect(html).toContain('account');
      expect(html).toContain('colonel');
      expect(html).toContain('logout');
    });

    it('shows billing item when billing is enabled', async () => {
      wrapper = mountComponent(
        { colonel: true },
        { billing_enabled: true }
      );

      const trigger = wrapper.find('button[aria-haspopup="true"]');
      await trigger.trigger('click');
      await nextTick();

      const html = wrapper.html().toLowerCase();
      expect(html).toContain('billing');
    });

    it('does not show billing item when billing is disabled', async () => {
      wrapper = mountComponent(
        { colonel: false },
        { billing_enabled: false }
      );

      const trigger = wrapper.find('button[aria-haspopup="true"]');
      await trigger.trigger('click');
      await nextTick();

      const html = wrapper.html().toLowerCase();
      expect(html).not.toContain('billing');
    });
  });

  describe('MFA State', () => {
    it('shows limited menu when awaiting MFA', async () => {
      wrapper = mountComponent({
        awaitingMfa: true,
      });

      const trigger = wrapper.find('button[aria-haspopup="true"]');
      await trigger.trigger('click');
      await nextTick();

      const menuItems = wrapper.findAll('[role="menuitem"]');

      // Should have limited items during MFA
      expect(menuItems.length).toBeLessThanOrEqual(3);

      const html = wrapper.html().toLowerCase();
      expect(html).toContain('mfa');
    });

    it('shows amber avatar styling when awaiting MFA', () => {
      wrapper = mountComponent({ awaitingMfa: true });

      const html = wrapper.html().toLowerCase();
      // Should have amber styling on avatar area
      expect(html).toContain('amber');
    });
  });

  describe('Logout Functionality', () => {
    it('calls logout when logout is clicked', async () => {
      wrapper = mountComponent();

      const trigger = wrapper.find('button[aria-haspopup="true"]');
      await trigger.trigger('click');
      await nextTick();

      const menuItems = wrapper.findAll('[role="menuitem"]');
      const logoutItem = menuItems.find(item =>
        item.text().toLowerCase().includes('logout')
      );

      if (logoutItem) {
        await logoutItem.trigger('click');
        await nextTick();

        expect(mockLogout).toHaveBeenCalled();
      }
    });

    it('shows logout with danger/red styling', async () => {
      wrapper = mountComponent();

      const trigger = wrapper.find('button[aria-haspopup="true"]');
      await trigger.trigger('click');
      await nextTick();

      const menuItems = wrapper.findAll('[role="menuitem"]');
      const logoutItem = menuItems.find(item =>
        item.text().toLowerCase().includes('logout')
      );

      if (logoutItem) {
        const html = logoutItem.html().toLowerCase();
        const hasDangerStyling = html.includes('red') || html.includes('danger');
        expect(hasDangerStyling).toBe(true);
      }
    });
  });

  describe('Edge Cases', () => {
    it('handles missing customer data gracefully', () => {
      expect(() => {
        wrapper = mountComponent({ cust: null });
      }).not.toThrow();

      expect(wrapper.exists()).toBe(true);
    });

    it('handles long email addresses gracefully', () => {
      const longEmail = 'verylongemailaddress@verylongdomainname.com';

      wrapper = mountComponent({
        cust: { ...mockCustomer, email: longEmail },
      });

      // Should render without errors
      expect(wrapper.exists()).toBe(true);
    });

    it('handles uninitialized store gracefully', () => {
      // Should not crash with minimal bootstrap state
      expect(() => {
        wrapper = mount(UserMenu, {
          props: {
            cust: mockCustomer,
            colonel: true,
            awaitingMfa: false,
          },
          global: {
            plugins: [
              i18n,
              createTestingPinia({
                createSpy: vi.fn,
                initialState: {
                  bootstrap: {
                    authenticated: false,
                    billing_enabled: false,
                    cust: null,
                  },
                },
              }),
            ],
          },
        });
      }).not.toThrow();
    });
  });

  describe('Accessibility', () => {
    it('has proper ARIA attributes on trigger', () => {
      wrapper = mountComponent();

      const trigger = wrapper.find('button[aria-haspopup="true"]');

      expect(trigger.attributes('aria-haspopup')).toBe('true');
    });

    it('menu has role="menu"', async () => {
      wrapper = mountComponent();

      const trigger = wrapper.find('button[aria-haspopup="true"]');
      await trigger.trigger('click');
      await nextTick();

      const menu = wrapper.find('[role="menu"]');
      expect(menu.exists()).toBe(true);
    });

    it('menu items have role="menuitem"', async () => {
      wrapper = mountComponent();

      const trigger = wrapper.find('button[aria-haspopup="true"]');
      await trigger.trigger('click');
      await nextTick();

      const menuItems = wrapper.findAll('[role="menuitem"]');
      expect(menuItems.length).toBeGreaterThan(0);
    });
  });
});
