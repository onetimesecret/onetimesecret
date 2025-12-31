// src/tests/apps/workspace/billing/PlanChangeModal.spec.ts

import { mount, VueWrapper } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createI18n } from 'vue-i18n';
import { createPinia, setActivePinia } from 'pinia';
import PlanChangeModal from '@/apps/workspace/billing/PlanChangeModal.vue';
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

// Mock BillingService
const mockPreviewPlanChange = vi.fn();
const mockChangePlan = vi.fn();

vi.mock('@/services/billing.service', () => ({
  BillingService: {
    previewPlanChange: (...args: unknown[]) => mockPreviewPlanChange(...args),
    changePlan: (...args: unknown[]) => mockChangePlan(...args),
  },
}));

// Test data
const mockCurrentPlan = {
  id: 'identity_plus_v1_monthly',
  stripe_price_id: 'price_current_123',
  name: 'Identity Plus',
  tier: 'single_team',
  interval: 'month',
  amount: 2900,
  currency: 'usd',
  region: 'us-east',
  display_order: 10,
  features: ['Feature 1'],
  limits: { teams: 1 },
  entitlements: ['create_secrets'],
};

const mockTargetPlan = {
  id: 'team_plus_v1_monthly',
  stripe_price_id: 'price_target_456',
  name: 'Team Plus',
  tier: 'multi_team',
  interval: 'month',
  amount: 9900,
  currency: 'usd',
  region: 'us-east',
  display_order: 20,
  features: ['Feature 1', 'Feature 2'],
  limits: { teams: 5 },
  entitlements: ['create_secrets', 'api_access'],
};

const mockPreviewResponse = {
  amount_due: 7000,
  subtotal: 9900,
  credit_applied: 2900,
  next_billing_date: Math.floor(Date.now() / 1000) + 86400 * 30,
  currency: 'usd',
  current_plan: {
    price_id: 'price_current_123',
    amount: 2900,
    interval: 'month',
  },
  new_plan: {
    price_id: 'price_target_456',
    amount: 9900,
    interval: 'month',
  },
};

const i18n = createI18n({
  legacy: false,
  locale: 'en',
  messages: {
    en: {
      web: {
        billing: {
          plans: {
            upgrade: 'Upgrade',
            downgrade: 'Downgrade',
            upgrade_to: 'Upgrade to {plan}?',
            downgrade_to: 'Downgrade to {plan}?',
            confirm_upgrade: 'Confirm Upgrade',
            confirm_downgrade: 'Confirm Downgrade',
            change_immediate: 'Your plan will change immediately.',
            current_plan_label: 'Current plan:',
            new_plan_label: 'New plan:',
            credit_label: 'Credit for unused time:',
            next_invoice: 'Next invoice',
            limits_update_notice: 'Your feature limits will update immediately after the plan change.',
            change_failed: 'Plan change failed. Please try again.',
          },
        },
        COMMON: {
          processing: 'Processing...',
          word_cancel: 'Cancel',
        },
      },
    },
  },
});

describe('PlanChangeModal', () => {
  let wrapper: VueWrapper;
  let pinia: ReturnType<typeof createPinia>;

  beforeEach(() => {
    pinia = createPinia();
    setActivePinia(pinia);
    vi.clearAllMocks();
    mockPreviewPlanChange.mockReset();
    mockChangePlan.mockReset();
  });

  afterEach(() => {
    if (wrapper) {
      wrapper.unmount();
    }
  });

  const mountComponent = async (props: {
    open?: boolean;
    orgExtId?: string;
    currentPlan?: typeof mockCurrentPlan | null;
    targetPlan?: typeof mockTargetPlan | null;
  } = {}) => {
    const component = mount(PlanChangeModal, {
      props: {
        open: true,
        orgExtId: 'org_123',
        currentPlan: mockCurrentPlan,
        targetPlan: mockTargetPlan,
        ...props,
      },
      global: {
        plugins: [i18n, pinia],
      },
    });

    // Wait for async operations
    await nextTick();
    await nextTick();

    return component;
  };

  describe('Rendering', () => {
    it('renders the modal when open prop is true', async () => {
      mockPreviewPlanChange.mockResolvedValueOnce(mockPreviewResponse);
      wrapper = await mountComponent({ open: true });
      expect(wrapper.find('[role="dialog"]').exists()).toBe(true);
    });

    it('does not render content when open prop is false', async () => {
      wrapper = await mountComponent({ open: false });
      expect(wrapper.find('.dialog-panel').exists()).toBe(false);
    });

    it('shows upgrade label when upgrading', async () => {
      mockPreviewPlanChange.mockResolvedValueOnce(mockPreviewResponse);
      wrapper = await mountComponent();
      expect(wrapper.text()).toContain('Upgrade');
    });

    it('shows downgrade label when downgrading', async () => {
      // Lower display_order indicates a downgrade (target order < current order)
      const downgradePlan = { ...mockTargetPlan, tier: 'free', display_order: 5 };
      mockPreviewPlanChange.mockResolvedValueOnce(mockPreviewResponse);
      wrapper = await mountComponent({ targetPlan: downgradePlan });
      expect(wrapper.text()).toContain('Downgrade');
    });
  });

  describe('Preview Loading', () => {
    it('loads proration preview when modal opens', async () => {
      mockPreviewPlanChange.mockResolvedValueOnce(mockPreviewResponse);
      wrapper = await mountComponent();

      expect(mockPreviewPlanChange).toHaveBeenCalledWith(
        'org_123',
        mockTargetPlan.stripe_price_id
      );
    });

    it('calls API for preview on mount with pending state', async () => {
      let resolvePreview: (value: unknown) => void;
      const pendingPromise = new Promise(resolve => {
        resolvePreview = resolve;
      });
      mockPreviewPlanChange.mockReturnValueOnce(pendingPromise);

      // Mount without awaiting extra nextTicks to catch loading state
      const component = mount(PlanChangeModal, {
        props: {
          open: true,
          orgExtId: 'org_123',
          currentPlan: mockCurrentPlan,
          targetPlan: mockTargetPlan,
        },
        global: {
          plugins: [i18n, pinia],
        },
      });

      // API should be called immediately on mount
      await nextTick();
      expect(mockPreviewPlanChange).toHaveBeenCalledWith('org_123', mockTargetPlan.stripe_price_id);

      // No preview data displayed yet (still loading)
      expect(component.text()).not.toContain('Identity Plus');

      // Clean up
      resolvePreview!(mockPreviewResponse);
      await nextTick();
      component.unmount();
    });

    it('displays preview data after loading', async () => {
      mockPreviewPlanChange.mockResolvedValueOnce(mockPreviewResponse);
      wrapper = await mountComponent();
      await nextTick();

      const html = wrapper.html();
      expect(html).toContain('Identity Plus');
      expect(html).toContain('Team Plus');
    });
  });

  describe('Error Handling', () => {
    it('displays error message when preview fails', async () => {
      mockPreviewPlanChange.mockRejectedValueOnce(new Error('API Error'));
      wrapper = await mountComponent();
      await nextTick();

      // classifyError extracts the error message, so we see the actual error
      expect(wrapper.text()).toContain('API Error');
    });

    it('displays error message when plan change fails', async () => {
      mockPreviewPlanChange.mockResolvedValueOnce(mockPreviewResponse);
      mockChangePlan.mockRejectedValueOnce(new Error('Change failed'));

      wrapper = await mountComponent();
      await nextTick();

      // Click confirm button
      const confirmButton = wrapper.findAll('button').find(
        btn => btn.text().includes('Confirm')
      );
      await confirmButton?.trigger('click');
      await nextTick();
      await nextTick();

      // classifyError extracts the error message, so we see the actual error
      expect(wrapper.text()).toContain('Change failed');
    });
  });

  describe('Plan Change Execution', () => {
    it('calls changePlan API when confirm is clicked', async () => {
      mockPreviewPlanChange.mockResolvedValueOnce(mockPreviewResponse);
      mockChangePlan.mockResolvedValueOnce({
        success: true,
        new_plan: 'team_plus_v1_monthly',
        status: 'active',
        current_period_end: Math.floor(Date.now() / 1000) + 86400 * 30,
      });

      wrapper = await mountComponent();
      await nextTick();

      const confirmButton = wrapper.findAll('button').find(
        btn => btn.text().includes('Confirm')
      );
      await confirmButton?.trigger('click');
      await nextTick();

      expect(mockChangePlan).toHaveBeenCalledWith(
        'org_123',
        mockTargetPlan.stripe_price_id
      );
    });

    it('emits success event after successful plan change', async () => {
      mockPreviewPlanChange.mockResolvedValueOnce(mockPreviewResponse);
      mockChangePlan.mockResolvedValueOnce({
        success: true,
        new_plan: 'team_plus_v1_monthly',
        status: 'active',
        current_period_end: Math.floor(Date.now() / 1000) + 86400 * 30,
      });

      wrapper = await mountComponent();
      await nextTick();

      const confirmButton = wrapper.findAll('button').find(
        btn => btn.text().includes('Confirm')
      );
      await confirmButton?.trigger('click');
      await nextTick();
      await nextTick();

      expect(wrapper.emitted('success')).toBeTruthy();
      expect(wrapper.emitted('success')![0]).toEqual(['team_plus_v1_monthly']);
    });
  });

  describe('Events', () => {
    it('emits close event when cancel button is clicked', async () => {
      mockPreviewPlanChange.mockResolvedValueOnce(mockPreviewResponse);
      wrapper = await mountComponent();
      await nextTick();

      const cancelButton = wrapper.findAll('button').find(
        btn => btn.text().includes('Cancel')
      );
      await cancelButton?.trigger('click');

      expect(wrapper.emitted('close')).toBeTruthy();
    });

    it('does not emit close when plan change is in progress', async () => {
      mockPreviewPlanChange.mockResolvedValueOnce(mockPreviewResponse);

      let resolveChange: (value: unknown) => void;
      const pendingPromise = new Promise(resolve => {
        resolveChange = resolve;
      });
      mockChangePlan.mockReturnValueOnce(pendingPromise);

      wrapper = await mountComponent();
      await nextTick();

      // Start plan change
      const confirmButton = wrapper.findAll('button').find(
        btn => btn.text().includes('Confirm')
      );
      await confirmButton?.trigger('click');
      await nextTick();

      // Try to close
      const cancelButton = wrapper.findAll('button').find(
        btn => btn.text().includes('Cancel')
      );
      await cancelButton?.trigger('click');

      // Should not emit close while changing
      expect(wrapper.emitted('close')).toBeFalsy();

      // Clean up
      resolveChange!({ success: true, new_plan: 'test' });
    });
  });

  describe('Button States', () => {
    it('disables confirm button while loading preview', async () => {
      let resolvePreview: (value: unknown) => void;
      const pendingPromise = new Promise(resolve => {
        resolvePreview = resolve;
      });
      mockPreviewPlanChange.mockReturnValueOnce(pendingPromise);

      wrapper = await mountComponent();

      const confirmButton = wrapper.findAll('button').find(
        btn => btn.text().includes('Confirm')
      );
      expect(confirmButton?.attributes('disabled')).toBeDefined();

      resolvePreview!(mockPreviewResponse);
    });

    it('disables confirm button when there is an error', async () => {
      mockPreviewPlanChange.mockRejectedValueOnce(new Error('API Error'));
      wrapper = await mountComponent();
      await nextTick();

      const confirmButton = wrapper.findAll('button').find(
        btn => btn.text().includes('Confirm')
      );
      expect(confirmButton?.attributes('disabled')).toBeDefined();
    });

    it('shows processing text on confirm button during plan change', async () => {
      mockPreviewPlanChange.mockResolvedValueOnce(mockPreviewResponse);

      let resolveChange: (value: unknown) => void;
      const pendingPromise = new Promise(resolve => {
        resolveChange = resolve;
      });
      mockChangePlan.mockReturnValueOnce(pendingPromise);

      wrapper = await mountComponent();
      await nextTick();

      const confirmButton = wrapper.findAll('button').find(
        btn => btn.text().includes('Confirm')
      );
      await confirmButton?.trigger('click');
      await nextTick();

      expect(wrapper.text()).toContain('Processing');

      resolveChange!({ success: true, new_plan: 'test' });
    });
  });

  describe('Proration Display', () => {
    it('shows credit applied when downgrading', async () => {
      mockPreviewPlanChange.mockResolvedValueOnce(mockPreviewResponse);
      wrapper = await mountComponent();
      await nextTick();

      // Preview has credit_applied: 2900
      expect(wrapper.text()).toContain('Credit for unused time');
    });
  });
});
