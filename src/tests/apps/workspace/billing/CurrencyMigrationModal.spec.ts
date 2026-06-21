// src/tests/apps/workspace/billing/CurrencyMigrationModal.spec.ts

import { mount, VueWrapper } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createPinia, setActivePinia } from 'pinia';
import CurrencyMigrationModal from '@/apps/workspace/billing/CurrencyMigrationModal.vue';
import { createTestI18n } from '@tests/setup';
import { createI18n } from 'vue-i18n';
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

const futureDate = Math.floor((Date.now() + 86400 * 30 * 1000) / 1000);

const mockConflict = {
  error: true as const,
  code: 'currency_conflict' as const,
  message: 'Your account has an active subscription in EUR.',
  details: {
    existing_currency: 'eur',
    requested_currency: 'cad',
    current_plan: {
      name: 'Identity Plus',
      price_formatted: '€14.00/mo',
      current_period_end: futureDate,
    },
    requested_plan: {
      name: 'Team Plus',
      price_formatted: '$25.00/mo',
      price_id: 'price_cad_team_plus',
    },
    warnings: {
      has_credit_balance: false,
      credit_balance_amount: 0,
      has_pending_invoice_items: false,
      has_incompatible_coupons: false,
    },
  },
};

const i18n = createTestI18n();

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
      expect(wrapper.text()).toContain('web.billing.currency_migration.title');
    });

    it('does not render when open is false', async () => {
      wrapper = await mountComponent({ open: false });
      expect(wrapper.find('.dialog-panel').exists()).toBe(false);
    });

    it('displays currency names from conflict', async () => {
      // Currency names (EUR/CAD) are interpolated into the description message's
      // {from}/{to} placeholders. Under pass-through i18n the description renders
      // as the raw key with no interpolation, so assert the description key is wired.
      wrapper = await mountComponent();
      expect(wrapper.text()).toContain('web.billing.currency_migration.description');
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
      expect(wrapper.text()).toContain('web.billing.currency_migration.warning_credit_balance');
    });

    it('does not show warnings when none are active', async () => {
      wrapper = await mountComponent();
      expect(wrapper.text()).not.toContain('web.billing.currency_migration.warning_credit_balance');
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
      expect(wrapper.text()).toContain('web.billing.currency_migration.graceful_title');
      expect(wrapper.text()).toContain('web.billing.currency_migration.immediate_title');
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
        btn => btn.text().includes('currency_migration.confirm')
      );
      await confirmBtn?.trigger('click');
      await nextTick();

      expect(mockMigrateCurrency).toHaveBeenCalledWith('org_123', {
        new_price_id: 'price_cad_team_plus',
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
        btn => btn.text().includes('currency_migration.confirm')
      );
      await confirmBtn?.trigger('click');
      await nextTick();

      expect(mockMigrateCurrency).toHaveBeenCalledWith('org_123', {
        new_price_id: 'price_cad_team_plus',
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
        btn => btn.text().includes('currency_migration.confirm')
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
        btn => btn.text().includes('currency_migration.confirm')
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
        btn => btn.text().includes('currency_migration.confirm')
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
        btn => btn.text().includes('currency_migration.confirm')
      );
      await confirmBtn?.trigger('click');
      await nextTick();
      await nextTick();

      expect(wrapper.text()).toContain('web.billing.currency_migration.error');
    });
  });

  describe('Button States', () => {
    it('disables confirm when no conflict', async () => {
      wrapper = await mountComponent({ conflict: null });
      const confirmBtn = wrapper.findAll('button').find(
        btn => btn.text().includes('currency_migration.confirm')
      );
      expect(confirmBtn?.attributes('disabled')).toBeDefined();
    });

    it('shows processing text during migration', async () => {
      let resolve: (v: unknown) => void;
      const pending = new Promise(r => { resolve = r; });
      mockMigrateCurrency.mockReturnValueOnce(pending);

      wrapper = await mountComponent();
      const confirmBtn = wrapper.findAll('button').find(
        btn => btn.text().includes('currency_migration.confirm')
      );
      await confirmBtn?.trigger('click');
      await nextTick();

      expect(wrapper.text()).toContain('web.COMMON.processing');
      resolve!({ success: true, migration: { mode: 'graceful', cancel_at: 123 } });
    });

    it('prevents close while migrating', async () => {
      let resolve: (v: unknown) => void;
      const pending = new Promise(r => { resolve = r; });
      mockMigrateCurrency.mockReturnValueOnce(pending);

      wrapper = await mountComponent();
      const confirmBtn = wrapper.findAll('button').find(
        btn => btn.text().includes('currency_migration.confirm')
      );
      await confirmBtn?.trigger('click');
      await nextTick();

      const cancelBtn = wrapper.findAll('button').find(
        btn => btn.text().includes('word_cancel')
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
        btn => btn.text().includes('word_cancel')
      );
      await cancelBtn?.trigger('click');
      expect(wrapper.emitted('close')).toBeTruthy();
    });
  });

  describe('Currency interpolation (real i18n)', () => {
    it('renders actual currency codes via interpolation', async () => {
      const realI18n = createI18n({
        legacy: false,
        locale: 'en',
        messages: {
          en: {
            'web.billing.currency_migration.description': 'Switch from {from} to {to}',
          },
        },
      });

      wrapper = mount(CurrencyMigrationModal, {
        props: { open: true, orgExtId: 'org_123', conflict: mockConflict },
        global: { plugins: [realI18n, pinia] },
      });
      await nextTick();

      expect(wrapper.text()).toContain('Switch from EUR to CAD');
    });
  });
});
