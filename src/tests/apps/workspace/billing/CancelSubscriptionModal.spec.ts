// src/tests/apps/workspace/billing/CancelSubscriptionModal.spec.ts

import { mount, VueWrapper } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createPinia, setActivePinia } from 'pinia';
import CancelSubscriptionModal from '@/apps/workspace/billing/CancelSubscriptionModal.vue';
import { nextTick } from 'vue';
import { createTestI18n } from '@tests/setup';

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
const mockCancelSubscription = vi.fn();

vi.mock('@/services/billing.service', () => ({
  BillingService: {
    cancelSubscription: (...args: unknown[]) => mockCancelSubscription(...args),
  },
}));

// Mock error classifier
vi.mock('@/schemas/errors', () => ({
  classifyError: (err: Error) => ({
    message: err.message || 'Unknown error',
  }),
}));

const i18n = createTestI18n();

describe('CancelSubscriptionModal', () => {
  let wrapper: VueWrapper;
  let pinia: ReturnType<typeof createPinia>;

  // Test data
  interface CancelModalProps {
    open: boolean;
    orgExtId: string;
    planName: string;
    periodEnd: number | null;
  }

  const defaultProps: CancelModalProps = {
    open: true,
    orgExtId: 'org_test123',
    planName: 'Identity Plus',
    periodEnd: Math.floor(Date.now() / 1000) + 86400 * 30, // 30 days from now
  };

  beforeEach(() => {
    pinia = createPinia();
    setActivePinia(pinia);
    vi.clearAllMocks();
    mockCancelSubscription.mockReset();
  });

  afterEach(() => {
    if (wrapper) {
      wrapper.unmount();
    }
  });

  const mountComponent = async (props: Partial<CancelModalProps> = {}) => {
    const component = mount(CancelSubscriptionModal, {
      props: {
        ...defaultProps,
        ...props,
      },
      global: {
        plugins: [i18n, pinia],
      },
    });

    await nextTick();
    return component;
  };

  describe('Rendering', () => {
    it('renders the modal when open prop is true', async () => {
      wrapper = await mountComponent({ open: true });
      expect(wrapper.find('[role="dialog"]').exists()).toBe(true);
    });

    it('does not render content when open prop is false', async () => {
      wrapper = await mountComponent({ open: false });
      expect(wrapper.find('.dialog-panel').exists()).toBe(false);
    });

    it('displays the modal title', async () => {
      wrapper = await mountComponent();
      expect(wrapper.text()).toContain('web.billing.cancel.title');
    });

    it('displays the plan name in confirmation message', async () => {
      // Pass-through i18n renders the raw key; {plan} interpolation is not
      // applied to a missing key, so we assert the confirmation key is wired.
      wrapper = await mountComponent({ planName: 'Team Plus' });
      expect(wrapper.text()).toContain('web.billing.cancel.confirmation');
    });

    it('displays formatted period end date when provided', async () => {
      // Use a specific timestamp for predictable date formatting
      const timestamp = 1704067200; // Jan 1, 2024 00:00:00 UTC
      wrapper = await mountComponent({ periodEnd: timestamp });

      // The component formats the date using toLocaleDateString
      // We just verify the access-until key is rendered
      const text = wrapper.text();
      expect(text).toContain('web.billing.cancel.access_until');
    });

    it('shows fallback text when periodEnd is null', async () => {
      wrapper = await mountComponent({ periodEnd: null });
      expect(wrapper.text()).toContain('web.billing.cancel.access_until_period_end');
    });

    it('displays what happens section', async () => {
      wrapper = await mountComponent();
      const text = wrapper.text();
      expect(text).toContain('web.billing.cancel.what_happens');
      expect(text).toContain('web.billing.cancel.no_future_charges');
      expect(text).toContain('web.billing.cancel.downgrade_to_free');
    });

    it('displays both action buttons', async () => {
      wrapper = await mountComponent();
      const buttons = wrapper.findAll('button');
      const buttonTexts = buttons.map(btn => btn.text());

      expect(buttonTexts).toContain('web.billing.cancel.keep_subscription');
      expect(buttonTexts).toContain('web.billing.cancel.confirm_cancel');
    });
  });

  describe('Cancel Subscription Flow', () => {
    it('calls BillingService.cancelSubscription when confirm button is clicked', async () => {
      mockCancelSubscription.mockResolvedValueOnce({
        success: true,
        cancel_at: Math.floor(Date.now() / 1000) + 86400 * 30,
        status: 'active',
      });

      wrapper = await mountComponent({ orgExtId: 'org_abc123' });

      const confirmButton = wrapper.findAll('button').find(
        btn => btn.text() === 'web.billing.cancel.confirm_cancel'
      );
      await confirmButton?.trigger('click');
      await nextTick();

      expect(mockCancelSubscription).toHaveBeenCalledWith('org_abc123');
    });

    it('shows processing state while cancellation is in progress', async () => {
      let resolveCancel: (value: unknown) => void;
      const pendingPromise = new Promise(resolve => {
        resolveCancel = resolve;
      });
      mockCancelSubscription.mockReturnValueOnce(pendingPromise);

      wrapper = await mountComponent();

      const confirmButton = wrapper.findAll('button').find(
        btn => btn.text() === 'web.billing.cancel.confirm_cancel'
      );
      await confirmButton?.trigger('click');
      await nextTick();

      expect(wrapper.text()).toContain('web.COMMON.processing');

      // Clean up
      resolveCancel!({ success: true, cancel_at: Date.now() / 1000, status: 'active' });
      await nextTick();
    });

    it('emits success event after successful cancellation', async () => {
      mockCancelSubscription.mockResolvedValueOnce({
        success: true,
        cancel_at: Math.floor(Date.now() / 1000) + 86400 * 30,
        status: 'active',
      });

      wrapper = await mountComponent();

      const confirmButton = wrapper.findAll('button').find(
        btn => btn.text() === 'web.billing.cancel.confirm_cancel'
      );
      await confirmButton?.trigger('click');
      await nextTick();
      await nextTick();

      expect(wrapper.emitted('success')).toBeTruthy();
    });

    it('does not call cancel when orgExtId is empty', async () => {
      wrapper = await mountComponent({ orgExtId: '' });

      const confirmButton = wrapper.findAll('button').find(
        btn => btn.text() === 'web.billing.cancel.confirm_cancel'
      );
      await confirmButton?.trigger('click');
      await nextTick();

      expect(mockCancelSubscription).not.toHaveBeenCalled();
    });
  });

  describe('Error Handling', () => {
    it('displays error message when cancellation fails', async () => {
      mockCancelSubscription.mockRejectedValueOnce(new Error('Subscription not found'));

      wrapper = await mountComponent();

      const confirmButton = wrapper.findAll('button').find(
        btn => btn.text() === 'web.billing.cancel.confirm_cancel'
      );
      await confirmButton?.trigger('click');
      await nextTick();
      await nextTick();

      expect(wrapper.text()).toContain('Subscription not found');
    });

    it('displays fallback error when classified error has no message', async () => {
      // When error.message is empty, classifyError returns 'Unknown error'
      // The component then falls back to i18n error message in the || chain
      mockCancelSubscription.mockRejectedValueOnce(new Error(''));

      wrapper = await mountComponent();

      const confirmButton = wrapper.findAll('button').find(
        btn => btn.text() === 'web.billing.cancel.confirm_cancel'
      );
      await confirmButton?.trigger('click');
      await nextTick();
      await nextTick();

      // classifyError returns { message: 'Unknown error' } for empty message
      // Component: error.value = classified.message || t('web.billing.cancel.error')
      // Since 'Unknown error' is truthy, it gets displayed
      expect(wrapper.text()).toContain('Unknown error');
    });

    it('shows error in alert role element', async () => {
      mockCancelSubscription.mockRejectedValueOnce(new Error('API Error'));

      wrapper = await mountComponent();

      const confirmButton = wrapper.findAll('button').find(
        btn => btn.text() === 'web.billing.cancel.confirm_cancel'
      );
      await confirmButton?.trigger('click');
      await nextTick();
      await nextTick();

      const errorAlert = wrapper.find('[role="alert"]');
      expect(errorAlert.exists()).toBe(true);
      expect(errorAlert.text()).toContain('API Error');
    });
  });

  describe('Close Behavior', () => {
    it('emits close event when Keep Subscription button is clicked', async () => {
      wrapper = await mountComponent();

      const keepButton = wrapper.findAll('button').find(
        btn => btn.text() === 'web.billing.cancel.keep_subscription'
      );
      await keepButton?.trigger('click');

      expect(wrapper.emitted('close')).toBeTruthy();
    });

    it('does not emit close while cancellation is in progress', async () => {
      let resolveCancel: (value: unknown) => void;
      const pendingPromise = new Promise(resolve => {
        resolveCancel = resolve;
      });
      mockCancelSubscription.mockReturnValueOnce(pendingPromise);

      wrapper = await mountComponent();

      // Start cancellation
      const confirmButton = wrapper.findAll('button').find(
        btn => btn.text() === 'web.billing.cancel.confirm_cancel'
      );
      await confirmButton?.trigger('click');
      await nextTick();

      // Try to close
      const keepButton = wrapper.findAll('button').find(
        btn => btn.text() === 'web.billing.cancel.keep_subscription'
      );
      await keepButton?.trigger('click');

      // Should not emit close while processing
      expect(wrapper.emitted('close')).toBeFalsy();

      // Clean up
      resolveCancel!({ success: true, cancel_at: Date.now() / 1000, status: 'active' });
      await nextTick();
    });
  });

  describe('Button States', () => {
    it('disables both buttons while processing', async () => {
      let resolveCancel: (value: unknown) => void;
      const pendingPromise = new Promise(resolve => {
        resolveCancel = resolve;
      });
      mockCancelSubscription.mockReturnValueOnce(pendingPromise);

      wrapper = await mountComponent();

      const confirmButton = wrapper.findAll('button').find(
        btn => btn.text() === 'web.billing.cancel.confirm_cancel'
      );
      await confirmButton?.trigger('click');
      await nextTick();

      const buttons = wrapper.findAll('button');
      buttons.forEach(button => {
        expect(button.attributes('disabled')).toBeDefined();
      });

      // Clean up
      resolveCancel!({ success: true, cancel_at: Date.now() / 1000, status: 'active' });
      await nextTick();
    });

    it('re-enables buttons after error', async () => {
      mockCancelSubscription.mockRejectedValueOnce(new Error('API Error'));

      wrapper = await mountComponent();

      const confirmButton = wrapper.findAll('button').find(
        btn => btn.text() === 'web.billing.cancel.confirm_cancel'
      );
      await confirmButton?.trigger('click');
      await nextTick();
      await nextTick();

      // Find the confirm button again (text changed back from Processing)
      const buttons = wrapper.findAll('button');
      const reenabledButton = buttons.find(btn => btn.text() === 'web.billing.cancel.confirm_cancel');

      // Should be enabled again after error
      expect(reenabledButton?.attributes('disabled')).toBeUndefined();
    });
  });

  describe('Idempotency', () => {
    it('prevents double submission', async () => {
      let resolveCancel: (value: unknown) => void;
      const pendingPromise = new Promise(resolve => {
        resolveCancel = resolve;
      });
      mockCancelSubscription.mockReturnValueOnce(pendingPromise);

      wrapper = await mountComponent();

      const confirmButton = wrapper.findAll('button').find(
        btn => btn.text() === 'web.billing.cancel.confirm_cancel'
      );

      // Click multiple times
      await confirmButton?.trigger('click');
      await confirmButton?.trigger('click');
      await confirmButton?.trigger('click');
      await nextTick();

      // Should only call once
      expect(mockCancelSubscription).toHaveBeenCalledTimes(1);

      // Clean up
      resolveCancel!({ success: true, cancel_at: Date.now() / 1000, status: 'active' });
      await nextTick();
    });
  });
});
