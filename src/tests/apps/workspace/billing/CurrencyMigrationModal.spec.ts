// src/tests/apps/workspace/billing/CurrencyMigrationModal.spec.ts

import { mount, VueWrapper } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createI18n } from 'vue-i18n';
import { createPinia, setActivePinia } from 'pinia';
import CurrencyMigrationModal from '@/apps/workspace/billing/CurrencyMigrationModal.vue';
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

vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="o-icon" />',
    props: ['collection', 'name', 'class'],
  },
}));

// Mock BillingService
const mockMigrateCurrency = vi.fn();
vi.mock('@/services/billing.service', () => ({
  BillingService: {
    migrateCurrency: (...args: unknown[]) => mockMigrateCurrency(...args),
  },
}));

vi.mock('@/schemas/errors', () => ({
  classifyError: (err: unknown) => ({
    message: err instanceof Error ? err.message : String(err),
    type: 'human',
    severity: 'error',
  }),
}));

const futureDate = new Date(Date.now() + 86400 * 30 * 1000).toISOString();

const mockConflict = {
  error: true as const,
  code: 'currency_conflict' as const,
  message: 'Your account has an active subscription in EUR.',
  details: {
    existing_currency: 'eur',
    requested_currency: 'usd',
    current_plan: {
      name: 'Identity Plus',
      price_formatted: '€14.00/mo',
      current_period_end: futureDate,
    },
    requested_plan: {
      name: 'Team Plus',
      price_formatted: '$25.00/mo',
      price_id: 'price_usd_team_plus',
    },
    warnings: {
      has_credit_balance: false,
      credit_balance_amount: 0,
      has_pending_invoice_items: false,
      has_incompatible_coupons: false,
    },
  },
};

const i18n = createI18n({
  legacy: false,
  locale: 'en',
  messages: {
    en: {
      web: {
        billing: {
          currency_migration: {
            title: 'Currency Change Required',
            description: 'Your current subscription uses {from}. The selected plan is billed in {to}.',
            current_plan: 'Current plan:',
            new_plan: 'New plan:',
            current_period_ends: 'Current period ends:',
            choose_timing: 'When should the switch happen?',
            graceful_title: 'Switch at end of billing period',
            graceful_description: 'Your current plan stays active until {date}.',
            immediate_title: 'Switch immediately',
            immediate_description: 'Your current plan is cancelled now.',
            confirm: 'Confirm Currency Change',
            error: 'Currency migration failed. Please try again.',
            warning_credit_balance: 'You have a credit balance in {currency} that cannot be transferred.',
            warning_pending_items: 'You have pending invoice items.',
            warning_coupons: 'Active coupons may not be compatible.',
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

describe('CurrencyMigrationModal', () => {
  let wrapper: VueWrapper;
  let pinia: ReturnType<typeof createPinia>;

  beforeEach(() => {
    pinia = createPinia();
    setActivePinia(pinia);
    vi.clearAllMocks();
    mockMigrateCurrency.mockReset();
  });

  afterEach(() => {
    if (wrapper) wrapper.unmount();
  });

  const mountComponent = async (props: Partial<{
    open: boolean;
    orgExtId: string;
    conflict: typeof mockConflict | null;
  }> = {}) => {
    const mergedProps = {
      open: true,
      orgExtId: 'org_123',
      conflict: mockConflict,
      ...props,
    };
    const component = mount(CurrencyMigrationModal, {
      props: mergedProps as any,
      global: { plugins: [i18n, pinia] },
    });
    await nextTick();
    await nextTick();
    await nextTick();
    return component;
  };

  describe('Rendering', () => {
    it('renders when open is true with conflict data', async () => {
      wrapper = await mountComponent();
      expect(wrapper.find('[role="dialog"]').exists()).toBe(true);
      expect(wrapper.text()).toContain('Currency Change Required');
    });

    it('does not render when open is false', async () => {
      wrapper = await mountComponent({ open: false });
      expect(wrapper.find('.dialog-panel').exists()).toBe(false);
    });

    it('displays currency names from conflict', async () => {
      wrapper = await mountComponent();
      expect(wrapper.text()).toContain('EUR');
      expect(wrapper.text()).toContain('USD');
    });

    it('displays current and new plan names with formatted prices', async () => {
      wrapper = await mountComponent();
      expect(wrapper.text()).toContain('Identity Plus');
      expect(wrapper.text()).toContain('€14.00/mo');
      expect(wrapper.text()).toContain('Team Plus');
      expect(wrapper.text()).toContain('$25.00/mo');
    });

    it('displays formatted period end date', async () => {
      wrapper = await mountComponent();
      const html = wrapper.html();
      expect(html).toMatch(/20\d{2}/);
    });
  });

  describe('Warnings', () => {
    it('shows credit balance warning when present', async () => {
      const conflictWithWarnings = {
        ...mockConflict,
        details: {
          ...mockConflict.details,
          warnings: {
            ...mockConflict.details.warnings,
            has_credit_balance: true,
            credit_balance_amount: 500,
          },
        },
      };
      wrapper = await mountComponent({ conflict: conflictWithWarnings });
      expect(wrapper.text()).toContain('credit balance');
    });

    it('does not show warnings when none are active', async () => {
      wrapper = await mountComponent();
      expect(wrapper.text()).not.toContain('credit balance');
    });
  });

  describe('Mode Selection', () => {
    it('defaults to graceful mode', async () => {
      wrapper = await mountComponent();
      const gracefulRadio = wrapper.find('input[value="graceful"]');
      expect((gracefulRadio.element as HTMLInputElement).checked).toBe(true);
    });

    it('allows switching to immediate mode', async () => {
      wrapper = await mountComponent();
      const immediateRadio = wrapper.find('input[value="immediate"]');
      await immediateRadio.setValue(true);
      expect((immediateRadio.element as HTMLInputElement).checked).toBe(true);
    });

    it('shows both mode options with descriptions', async () => {
      wrapper = await mountComponent();
      expect(wrapper.text()).toContain('Switch at end of billing period');
      expect(wrapper.text()).toContain('Switch immediately');
    });
  });

  describe('Migration Execution', () => {
    it('calls migrateCurrency with graceful mode on confirm', async () => {
      mockMigrateCurrency.mockResolvedValueOnce({
        success: true,
        migration: { mode: 'graceful', cancel_at: 1704067200 },
      });

      wrapper = await mountComponent();
      const confirmBtn = wrapper.findAll('button').find(
        btn => btn.text().includes('Confirm')
      );
      await confirmBtn?.trigger('click');
      await nextTick();

      expect(mockMigrateCurrency).toHaveBeenCalledWith('org_123', {
        new_price_id: 'price_usd_team_plus',
        mode: 'graceful',
      });
    });

    it('calls migrateCurrency with immediate mode when selected', async () => {
      mockMigrateCurrency.mockResolvedValueOnce({
        success: true,
        migration: {
          mode: 'immediate',
          checkout_url: 'https://checkout.stripe.com/cs_123',
          refund_amount: 700,
          refund_formatted: '€7.00',
        },
      });

      wrapper = await mountComponent();
      const immediateRadio = wrapper.find('input[value="immediate"]');
      await immediateRadio.setValue(true);
      await nextTick();

      const confirmBtn = wrapper.findAll('button').find(
        btn => btn.text().includes('Confirm')
      );
      await confirmBtn?.trigger('click');
      await nextTick();

      expect(mockMigrateCurrency).toHaveBeenCalledWith('org_123', {
        new_price_id: 'price_usd_team_plus',
        mode: 'immediate',
      });
    });

    it('emits graceful-confirmed with cancel_at on graceful success', async () => {
      mockMigrateCurrency.mockResolvedValueOnce({
        success: true,
        migration: { mode: 'graceful', cancel_at: 1704067200 },
      });

      wrapper = await mountComponent();
      const confirmBtn = wrapper.findAll('button').find(
        btn => btn.text().includes('Confirm')
      );
      await confirmBtn?.trigger('click');
      await nextTick();
      await nextTick();

      expect(wrapper.emitted('graceful-confirmed')).toBeTruthy();
      expect(wrapper.emitted('graceful-confirmed')![0][0]).toBe(1704067200);
    });

    it('emits immediate-redirect with checkout URL on immediate success', async () => {
      mockMigrateCurrency.mockResolvedValueOnce({
        success: true,
        migration: {
          mode: 'immediate',
          checkout_url: 'https://checkout.stripe.com/cs_456',
          refund_amount: 700,
          refund_formatted: '€7.00',
        },
      });

      wrapper = await mountComponent();
      const immediateRadio = wrapper.find('input[value="immediate"]');
      await immediateRadio.setValue(true);
      await nextTick();

      const confirmBtn = wrapper.findAll('button').find(
        btn => btn.text().includes('Confirm')
      );
      await confirmBtn?.trigger('click');
      await nextTick();
      await nextTick();

      expect(wrapper.emitted('immediate-redirect')).toBeTruthy();
      expect(wrapper.emitted('immediate-redirect')![0][0]).toBe(
        'https://checkout.stripe.com/cs_456'
      );
    });
  });

  describe('Error Handling', () => {
    it('displays error when migration fails', async () => {
      mockMigrateCurrency.mockRejectedValueOnce(new Error('past_due subscription'));

      wrapper = await mountComponent();
      const confirmBtn = wrapper.findAll('button').find(
        btn => btn.text().includes('Confirm')
      );
      await confirmBtn?.trigger('click');
      await nextTick();
      await nextTick();

      expect(wrapper.text()).toContain('past_due subscription');
    });

    it('displays generic error when result.success is false', async () => {
      mockMigrateCurrency.mockResolvedValueOnce({ success: false });

      wrapper = await mountComponent();
      const confirmBtn = wrapper.findAll('button').find(
        btn => btn.text().includes('Confirm')
      );
      await confirmBtn?.trigger('click');
      await nextTick();
      await nextTick();

      expect(wrapper.text()).toContain('Currency migration failed');
    });
  });

  describe('Button States', () => {
    it('disables confirm when no conflict', async () => {
      wrapper = await mountComponent({ conflict: null });
      const confirmBtn = wrapper.findAll('button').find(
        btn => btn.text().includes('Confirm')
      );
      expect(confirmBtn?.attributes('disabled')).toBeDefined();
    });

    it('shows processing text during migration', async () => {
      let resolve: (v: unknown) => void;
      const pending = new Promise(r => { resolve = r; });
      mockMigrateCurrency.mockReturnValueOnce(pending);

      wrapper = await mountComponent();
      const confirmBtn = wrapper.findAll('button').find(
        btn => btn.text().includes('Confirm')
      );
      await confirmBtn?.trigger('click');
      await nextTick();

      expect(wrapper.text()).toContain('Processing');
      resolve!({ success: true, migration: { mode: 'graceful', cancel_at: 123 } });
    });

    it('prevents close while migrating', async () => {
      let resolve: (v: unknown) => void;
      const pending = new Promise(r => { resolve = r; });
      mockMigrateCurrency.mockReturnValueOnce(pending);

      wrapper = await mountComponent();
      const confirmBtn = wrapper.findAll('button').find(
        btn => btn.text().includes('Confirm')
      );
      await confirmBtn?.trigger('click');
      await nextTick();

      const cancelBtn = wrapper.findAll('button').find(
        btn => btn.text().includes('Cancel')
      );
      await cancelBtn?.trigger('click');

      expect(wrapper.emitted('close')).toBeFalsy();
      resolve!({ success: true, migration: { mode: 'graceful', cancel_at: 123 } });
    });
  });

  describe('Events', () => {
    it('emits close when cancel is clicked', async () => {
      wrapper = await mountComponent();
      const cancelBtn = wrapper.findAll('button').find(
        btn => btn.text().includes('Cancel')
      );
      await cancelBtn?.trigger('click');
      expect(wrapper.emitted('close')).toBeTruthy();
    });
  });
});
