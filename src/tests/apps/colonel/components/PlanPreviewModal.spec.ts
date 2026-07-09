// src/tests/apps/colonel/components/PlanPreviewModal.spec.ts

import { mount, VueWrapper } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createTestingPinia } from '@pinia/testing';
import PlanPreviewModal from '@/shared/components/modals/PlanPreviewModal.vue';
import { useOrganizationStore } from '@/shared/stores/organizationStore';
import { createTestI18n } from '@tests/setup';
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
const mockGet = vi.fn();
vi.mock('@/api', () => ({
  createApi: () => ({
    post: mockPost,
    get: mockGet,
  }),
}));

// Default plans data for tests
const defaultPlansResponse = {
  data: {
    plans: [
      { planid: 'free_v1', name: 'Free', tier: 'free' },
      { planid: 'identity_v1', name: 'Identity Plus', tier: 'identity' },
      { planid: 'multi_team_v1', name: 'Multi-Team', tier: 'multi_team' },
    ],
    source: 'local_config' as const,
  },
};

const i18n = createTestI18n();

describe('PlanPreviewModal', () => {
  let wrapper: VueWrapper;
  let fetchMock: ReturnType<typeof vi.fn>;

  beforeEach(() => {
    vi.clearAllMocks();
    mockPost.mockReset();
    mockGet.mockReset();

    // Default: return plans for GET requests
    mockGet.mockResolvedValue(defaultPlansResponse);

    // Mock global fetch for bootstrapStore.refresh()
    fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      json: () => Promise.resolve({
        entitlement_preview_planid: null,
        entitlement_preview_plan_name: null,
      }),
    });
    vi.stubGlobal('fetch', fetchMock);
  });

  afterEach(() => {
    if (wrapper) {
      wrapper.unmount();
    }
    vi.unstubAllGlobals();
  });

  const mountComponent = async (
    props: { isOpen?: boolean } = {},
    bootstrapState: Record<string, unknown> = {}
  ) => {
    const pinia = createTestingPinia({
      createSpy: vi.fn,
      initialState: {
        bootstrap: {
          entitlement_preview_planid: bootstrapState.entitlement_preview_planid ?? null,
          entitlement_preview_plan_name: bootstrapState.entitlement_preview_plan_name ?? null,
          ...bootstrapState,
        },
      },
    });

    const component = mount(PlanPreviewModal, {
      props: {
        isOpen: true,
        ...props,
      },
      global: {
        plugins: [i18n, pinia],
        // organizationStore calls useApi() at setup; provide a stub so the
        // store can be instantiated (its actions are stubbed by testing pinia).
        provide: {
          api: { get: mockGet, post: mockPost, put: vi.fn(), delete: vi.fn() },
        },
      },
    });

    // Wait for plans to load
    await nextTick();
    await nextTick();

    return component;
  };

  describe('Rendering', () => {
    it('renders the modal when isOpen prop is true', async () => {
      wrapper = await mountComponent({ isOpen: true });
      expect(wrapper.find('[role="dialog"]').exists()).toBe(true);
    });

    it('does not render content when isOpen prop is false', async () => {
      wrapper = await mountComponent({ isOpen: false });
      // TransitionRoot hides content when show is false
      expect(wrapper.find('.dialog-panel').exists()).toBe(false);
    });

    it('renders all available plan options', async () => {
      wrapper = await mountComponent();
      const html = wrapper.html();

      expect(html).toContain('Free');
      expect(html).toContain('Identity Plus');
      expect(html).toContain('Multi-Team');
    });

    it('renders modal title from i18n', async () => {
      wrapper = await mountComponent();
      expect(wrapper.text()).toContain('web.colonel.previewPlanMode');
    });
  });

  describe('Current Test Plan Display', () => {
    it('shows test mode badge when override is active', async () => {
      wrapper = await mountComponent({}, {
        entitlement_preview_planid: 'identity_v1',
        entitlement_preview_plan_name: 'Identity Plus',
      });

      expect(wrapper.text()).toContain('web.colonel.previewModeActive');
    });

    it('shows current test plan name when testing', async () => {
      wrapper = await mountComponent({}, {
        entitlement_preview_planid: 'identity_v1',
        entitlement_preview_plan_name: 'Identity Plus',
      });

      expect(wrapper.text()).toContain('Identity Plus');
    });

    it('does not show test mode badge when no override is active', async () => {
      wrapper = await mountComponent({}, {
        entitlement_preview_planid: null,
      });

      expect(wrapper.text()).not.toContain('web.colonel.previewModeActive');
    });

    it('shows reset button when test mode is active', async () => {
      wrapper = await mountComponent({}, {
        entitlement_preview_planid: 'identity_v1',
      });

      const resetButton = wrapper.findAll('button').find(
        btn => btn.text().includes('web.colonel.resetToActual')
      );

      expect(resetButton?.exists()).toBe(true);
    });

    it('does not show reset button when test mode is inactive', async () => {
      wrapper = await mountComponent({}, {
        entitlement_preview_planid: null,
      });

      const resetButton = wrapper.findAll('button').find(
        btn => btn.text().includes('web.colonel.resetToActual')
      );

      expect(resetButton).toBeUndefined();
    });
  });

  describe('Plan Selection', () => {
    it('calls API with correct planid when plan is selected', async () => {
      mockPost.mockResolvedValueOnce({
        data: {
          status: 'active',
          preview_planid: 'identity_v1',
          preview_plan_name: 'Identity Plus',
        },
      });

      wrapper = await mountComponent();

      const planButton = wrapper.findAll('button').find(
        btn => btn.text().includes('Identity Plus')
      );

      expect(planButton?.exists()).toBe(true);
      await planButton!.trigger('click');
      await nextTick();
      await nextTick(); // Wait for refresh to complete

      expect(mockPost).toHaveBeenCalledWith(
        '/api/colonel/entitlement-preview',
        { planid: 'identity_v1' }
      );

      // Should emit close after successful operation
      expect(wrapper.emitted('close')).toBeTruthy();
    });

    it('calls API with null planid when reset is clicked', async () => {
      mockPost.mockResolvedValueOnce({
        data: { status: 'cleared', actual_planid: 'free' },
      });

      wrapper = await mountComponent({}, {
        entitlement_preview_planid: 'identity_v1',
      });

      const resetButton = wrapper.findAll('button').find(
        btn => btn.text().includes('web.colonel.resetToActual')
      );

      expect(resetButton?.exists()).toBe(true);
      await resetButton!.trigger('click');
      await nextTick();
      await nextTick(); // Wait for refresh to complete

      expect(mockPost).toHaveBeenCalledWith(
        '/api/colonel/entitlement-preview',
        { planid: null }
      );

      // Should emit close after successful operation
      expect(wrapper.emitted('close')).toBeTruthy();
    });

    it('displays error message when API call fails', async () => {
      mockPost.mockRejectedValueOnce(new Error('Server error'));

      wrapper = await mountComponent();

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

  // Regression: the modal must refetch org records after a preview toggle.
  // The server applies the preview override on every read (ADR-020), so
  // fetchOrganizations() returns preview-corrected entitlements/limits;
  // without it the UI keeps gating against the previously loaded records.
  describe('Org state refresh', () => {
    it('refetches organizations after activating preview mode', async () => {
      mockPost.mockResolvedValueOnce({ data: { status: 'active' } });

      wrapper = await mountComponent();
      const orgStore = useOrganizationStore();

      const planButton = wrapper.findAll('button').find(
        btn => btn.text().includes('Identity Plus')
      );
      await planButton!.trigger('click');
      await nextTick();
      await nextTick();

      expect(orgStore.fetchOrganizations).toHaveBeenCalled();
    });

    it('refetches organizations after resetting to actual plan', async () => {
      mockPost.mockResolvedValueOnce({
        data: { status: 'cleared', actual_planid: 'free' },
      });

      wrapper = await mountComponent({}, {
        entitlement_preview_planid: 'identity_v1',
      });
      const orgStore = useOrganizationStore();

      const resetButton = wrapper.findAll('button').find(
        btn => btn.text().includes('web.colonel.resetToActual')
      );
      await resetButton!.trigger('click');
      await nextTick();
      await nextTick();

      expect(orgStore.fetchOrganizations).toHaveBeenCalled();
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

      wrapper = await mountComponent();

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
      wrapper = await mountComponent();

      const cancelButton = wrapper.findAll('button').find(
        btn => btn.text().includes('web.COMMON.word_cancel')
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

      wrapper = await mountComponent();

      // Start loading
      const planButton = wrapper.findAll('button').find(
        btn => btn.text().includes('Free')
      );
      await planButton!.trigger('click');
      await nextTick();

      // Try to close
      const cancelButton = wrapper.findAll('button').find(
        btn => btn.text().includes('web.COMMON.word_cancel')
      );
      await cancelButton!.trigger('click');

      // Should not emit close while loading
      expect(wrapper.emitted('close')).toBeFalsy();

      // Clean up
      resolvePromise!({ data: { status: 'active' } });
    });
  });

  describe('Visual Indicators', () => {
    it('highlights currently active test plan with amber styling', async () => {
      wrapper = await mountComponent({}, {
        entitlement_preview_planid: 'identity_v1',
      });

      const html = wrapper.html();

      // The active plan button should have amber border
      expect(html).toContain('border-amber-500');
    });

    it('shows check icon on active test plan', async () => {
      wrapper = await mountComponent({}, {
        entitlement_preview_planid: 'multi_team_v1',
      });

      // The check icon should be present for the active plan
      const checkIcon = wrapper.find('.o-icon');
      expect(checkIcon.exists()).toBe(true);
    });
  });

  describe('Edge Cases', () => {
    it('handles missing window state gracefully', async () => {
      await expect(async () => {
        wrapper = await mountComponent({}, {});
      }).not.toThrow();
    });

    it('handles bootstrap state errors gracefully', async () => {
      // The usePreviewPlanMode composable handles errors internally
      wrapper = await mountComponent({}, {});
      expect(wrapper.find('[role="dialog"]').exists()).toBe(true);
    });
  });
});
