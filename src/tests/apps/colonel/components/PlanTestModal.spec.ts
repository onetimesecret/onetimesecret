// src/tests/apps/colonel/components/PlanTestModal.spec.ts

import { mount, VueWrapper } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createI18n } from 'vue-i18n';
import { createPinia, setActivePinia } from 'pinia';
import PlanTestModal from '@/apps/colonel/components/PlanTestModal.vue';
import { WindowService } from '@/services/window.service';
import { nextTick } from 'vue';

// Mock HeadlessUI components
vi.mock('@headlessui/vue', () => ({
  Dialog: {
    name: 'Dialog',
    template: '<div role="dialog" @close="$emit(\'close\')"><slot /></div>',
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
    template: '<span class="o-icon" />',
    props: ['collection', 'name', 'class'],
  },
}));

// Mock API
const mockPost = vi.fn();
vi.mock('@/api', () => ({
  createApi: () => ({
    post: mockPost,
  }),
}));

const i18n = createI18n({
  legacy: false,
  locale: 'en',
  messages: {
    en: {
      web: {
        colonel: {
          testPlanMode: 'Test Plan Mode',
          testModeDescription: 'Temporarily override your plan to test features',
          currentActualPlan: 'Current Actual Plan',
          testModeActive: 'Test Mode Active',
          testingAsPlan: 'Testing as {planName}',
          availablePlans: 'Available Plans',
          resetToActual: 'Reset to Actual Plan',
        },
        COMMON: {
          processing: 'Processing...',
          word_cancel: 'Cancel',
        },
      },
    },
  },
});

describe('PlanTestModal', () => {
  let wrapper: VueWrapper;
  let pinia: ReturnType<typeof createPinia>;

  beforeEach(() => {
    pinia = createPinia();
    setActivePinia(pinia);
    vi.clearAllMocks();
    mockPost.mockReset();
  });

  afterEach(() => {
    if (wrapper) {
      wrapper.unmount();
    }
  });

  const mountComponent = (
    props: { isOpen?: boolean } = {},
    windowState: Record<string, unknown> = {}
  ) => {
    vi.spyOn(WindowService, 'get').mockImplementation((key: string) => windowState[key] ?? undefined);

    return mount(PlanTestModal, {
      props: {
        isOpen: true,
        ...props,
      },
      global: {
        plugins: [i18n, pinia],
      },
    });
  };

  describe('Rendering', () => {
    it('renders the modal when isOpen prop is true', () => {
      wrapper = mountComponent({ isOpen: true });
      expect(wrapper.find('[role="dialog"]').exists()).toBe(true);
    });

    it('does not render content when isOpen prop is false', () => {
      wrapper = mountComponent({ isOpen: false });
      // TransitionRoot hides content when show is false
      expect(wrapper.find('.dialog-panel').exists()).toBe(false);
    });

    it('renders all available plan options', () => {
      wrapper = mountComponent();
      const html = wrapper.html();

      expect(html).toContain('Free');
      expect(html).toContain('Identity Plus');
      expect(html).toContain('Multi-Team');
    });

    it('renders modal title from i18n', () => {
      wrapper = mountComponent();
      expect(wrapper.text()).toContain('Test Plan Mode');
    });
  });

  describe('Current Test Plan Display', () => {
    it('shows test mode badge when override is active', () => {
      wrapper = mountComponent({}, {
        entitlement_test_planid: 'identity_v1',
        entitlement_test_plan_name: 'Identity Plus',
      });

      expect(wrapper.text()).toContain('Test Mode Active');
    });

    it('shows current test plan name when testing', () => {
      wrapper = mountComponent({}, {
        entitlement_test_planid: 'identity_v1',
        entitlement_test_plan_name: 'Identity Plus',
      });

      expect(wrapper.text()).toContain('Identity Plus');
    });

    it('does not show test mode badge when no override is active', () => {
      wrapper = mountComponent({}, {
        entitlement_test_planid: null,
      });

      expect(wrapper.text()).not.toContain('Test Mode Active');
    });

    it('shows reset button when test mode is active', () => {
      wrapper = mountComponent({}, {
        entitlement_test_planid: 'identity_v1',
      });

      const resetButton = wrapper.findAll('button').find(
        btn => btn.text().includes('Reset to Actual Plan')
      );

      expect(resetButton?.exists()).toBe(true);
    });

    it('does not show reset button when test mode is inactive', () => {
      wrapper = mountComponent({}, {
        entitlement_test_planid: null,
      });

      const resetButton = wrapper.findAll('button').find(
        btn => btn.text().includes('Reset to Actual Plan')
      );

      expect(resetButton).toBeUndefined();
    });
  });

  describe('Plan Selection', () => {
    it('calls API with correct planid when plan is selected', async () => {
      mockPost.mockResolvedValueOnce({
        data: {
          status: 'active',
          test_planid: 'identity_v1',
          test_plan_name: 'Identity Plus',
        },
      });

      // Mock window.location.reload
      const reloadMock = vi.fn();
      Object.defineProperty(window, 'location', {
        value: { reload: reloadMock },
        writable: true,
      });

      wrapper = mountComponent();

      const planButton = wrapper.findAll('button').find(
        btn => btn.text().includes('Identity Plus')
      );

      expect(planButton?.exists()).toBe(true);
      await planButton!.trigger('click');
      await nextTick();

      expect(mockPost).toHaveBeenCalledWith(
        '/api/colonel/entitlement-test',
        { planid: 'identity_v1' },
        expect.objectContaining({
          headers: expect.objectContaining({
            'Content-Type': 'application/json',
          }),
        })
      );
    });

    it('calls API with null planid when reset is clicked', async () => {
      mockPost.mockResolvedValueOnce({
        data: { status: 'cleared', actual_planid: 'free' },
      });

      const reloadMock = vi.fn();
      Object.defineProperty(window, 'location', {
        value: { reload: reloadMock },
        writable: true,
      });

      wrapper = mountComponent({}, {
        entitlement_test_planid: 'identity_v1',
      });

      const resetButton = wrapper.findAll('button').find(
        btn => btn.text().includes('Reset to Actual Plan')
      );

      expect(resetButton?.exists()).toBe(true);
      await resetButton!.trigger('click');
      await nextTick();

      expect(mockPost).toHaveBeenCalledWith(
        '/api/colonel/entitlement-test',
        { planid: null },
        expect.objectContaining({
          headers: expect.objectContaining({
            'Content-Type': 'application/json',
          }),
        })
      );
    });

    it('displays error message when API call fails', async () => {
      mockPost.mockRejectedValueOnce(new Error('Server error'));

      wrapper = mountComponent();

      const planButton = wrapper.findAll('button').find(
        btn => btn.text().includes('Free')
      );

      await planButton!.trigger('click');
      await nextTick();
      // Allow error state to propagate
      await nextTick();

      expect(wrapper.text()).toContain('Failed to activate test mode');
    });
  });

  describe('Loading State', () => {
    it('disables buttons during API call', async () => {
      // Create a promise we can control
      let resolvePromise: (value: unknown) => void;
      const pendingPromise = new Promise(resolve => {
        resolvePromise = resolve;
      });
      mockPost.mockReturnValueOnce(pendingPromise);

      wrapper = mountComponent();

      const planButton = wrapper.findAll('button').find(
        btn => btn.text().includes('Free')
      );

      await planButton!.trigger('click');
      await nextTick();

      // All buttons should be disabled during loading
      const buttons = wrapper.findAll('button');
      const allDisabled = buttons.every(
        btn => btn.attributes('disabled') !== undefined
      );

      expect(allDisabled).toBe(true);

      // Clean up
      resolvePromise!({ data: { status: 'active' } });
    });
  });

  describe('Events', () => {
    it('emits close event when cancel button is clicked', async () => {
      wrapper = mountComponent();

      const cancelButton = wrapper.findAll('button').find(
        btn => btn.text().includes('Cancel')
      );

      expect(cancelButton?.exists()).toBe(true);
      await cancelButton!.trigger('click');

      expect(wrapper.emitted('close')).toBeTruthy();
    });

    it('does not emit close when loading', async () => {
      let resolvePromise: (value: unknown) => void;
      const pendingPromise = new Promise(resolve => {
        resolvePromise = resolve;
      });
      mockPost.mockReturnValueOnce(pendingPromise);

      wrapper = mountComponent();

      // Start loading
      const planButton = wrapper.findAll('button').find(
        btn => btn.text().includes('Free')
      );
      await planButton!.trigger('click');
      await nextTick();

      // Try to close
      const cancelButton = wrapper.findAll('button').find(
        btn => btn.text().includes('Cancel')
      );
      await cancelButton!.trigger('click');

      // Should not emit close while loading
      expect(wrapper.emitted('close')).toBeFalsy();

      // Clean up
      resolvePromise!({ data: { status: 'active' } });
    });
  });

  describe('Visual Indicators', () => {
    it('highlights currently active test plan with amber styling', () => {
      wrapper = mountComponent({}, {
        entitlement_test_planid: 'identity_v1',
      });

      const html = wrapper.html();

      // The active plan button should have amber border
      expect(html).toContain('border-amber-500');
    });

    it('shows check icon on active test plan', () => {
      wrapper = mountComponent({}, {
        entitlement_test_planid: 'multi_team_v1',
      });

      // The check icon should be present for the active plan
      const checkIcon = wrapper.find('.o-icon');
      expect(checkIcon.exists()).toBe(true);
    });
  });

  describe('Edge Cases', () => {
    it('handles missing window state gracefully', () => {
      expect(() => {
        wrapper = mountComponent({}, {});
      }).not.toThrow();
    });

    it('handles WindowService.get throwing error', () => {
      vi.spyOn(WindowService, 'get').mockImplementation(() => {
        throw new Error('WindowService error');
      });

      expect(() => {
        wrapper = mount(PlanTestModal, {
          props: { isOpen: true },
          global: {
            plugins: [i18n, pinia],
          },
        });
      }).not.toThrow();
    });
  });
});
