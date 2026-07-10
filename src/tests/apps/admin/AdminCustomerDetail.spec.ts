// src/tests/apps/admin/AdminCustomerDetail.spec.ts

import { AxiosError } from 'axios';
import { flushPromises, mount, VueWrapper } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

/** Build a real AxiosError so the shared classifier extracts `data.error`. */
function axiosError(status: number, data: unknown, message = 'Request failed'): AxiosError {
  const err = new AxiosError(message);
  err.response = { status, data, statusText: '', headers: {}, config: {} as never };
  return err;
}

const mockApi = {
  get: vi.fn(),
  post: vi.fn(),
  delete: vi.fn(),
};
vi.mock('@/shared/composables/useApi', () => ({ useApi: () => mockApi }));

const pushMock = vi.fn();
vi.mock('vue-router', () => ({
  useRouter: () => ({ push: pushMock }),
  useRoute: () => ({ params: { id: 'ur_alice' } }),
}));

const showMock = vi.fn();
vi.mock('@/shared/stores/notificationsStore', () => ({
  useNotificationsStore: () => ({ show: showMock }),
}));

vi.mock('@/utils/format', () => ({
  formatDisplayDateTime: (d: Date) => `DT:${d.toISOString()}`,
}));

vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="o-icon" :data-name="name" />',
    props: ['collection', 'name', 'class', 'size', 'aria-label'],
  },
}));

// Render HeadlessUI dialog markup synchronously (mirrors AdminConfirmDialog.spec).
vi.mock('@headlessui/vue', () => ({
  Dialog: {
    name: 'Dialog',
    template: '<div role="dialog" @close="$emit(\'close\')"><slot /></div>',
    props: ['class'],
    emits: ['close'],
  },
  DialogPanel: {
    name: 'DialogPanel',
    template: '<div class="dialog-panel" :data-testid="$attrs[\'data-testid\']"><slot /></div>',
    props: ['class'],
  },
  DialogTitle: { name: 'DialogTitle', template: '<h3><slot /></h3>', props: ['as', 'class'] },
  TransitionRoot: {
    name: 'TransitionRoot',
    template: '<div v-if="show"><slot /></div>',
    props: ['as', 'show'],
  },
  TransitionChild: { name: 'TransitionChild', template: '<div><slot /></div>', props: ['as'] },
}));

import AdminCustomerDetail from '@/apps/admin/views/AdminCustomerDetail.vue';
import { createTestI18n } from '@tests/setup';

const i18n = createTestI18n();

const PUBLIC_ID = 'ur_alice';

type BillingOverride = {
  enabled?: boolean;
  stripeAvailable?: boolean;
  stripeReason?: string | null;
  invoice?: boolean;
};

function billingPayload(overrides: BillingOverride = {}) {
  const available = overrides.stripeAvailable ?? false;
  return {
    enabled: overrides.enabled ?? false,
    plan_id: 'basic',
    organization: {
      extid: 'og_acme',
      display_name: 'Acme',
      planid: 'basic',
      subscription_status: available ? 'active' : null,
      subscription_period_end: null,
    },
    stripe: {
      available,
      reason: available ? null : (overrides.stripeReason ?? 'Billing is not configured'),
      customer_id: available ? 'cus_123' : null,
      dashboard_url: available ? 'https://dashboard.stripe.com/customers/cus_123' : null,
      subscription: available
        ? { id: 'sub_123', status: 'active', current_period_end: 1700003600 }
        : null,
      latest_invoice:
        available && (overrides.invoice ?? true)
          ? {
              id: 'in_1',
              number: 'INV-0001',
              status: 'paid',
              currency: 'usd',
              total: 3500,
              created: 1700000000,
              hosted_invoice_url: 'https://invoice.stripe.com/i/in_1',
            }
          : null,
    },
  };
}

function detailPayload(
  overrides: {
    role?: string;
    verified?: boolean;
    suspended?: boolean;
    billing?: BillingOverride;
  } = {}
) {
  return {
    shrimp: '',
    record: {
      extid: PUBLIC_ID,
      email: 'alice@example.com',
      role: overrides.role ?? 'customer',
      verified: overrides.verified ?? false,
      suspended: overrides.suspended ?? false,
      suspended_at: overrides.suspended ? 1700000300 : null,
      suspended_by: overrides.suspended ? 'ur_colonel' : null,
      suspended_reason: overrides.suspended ? 'tos violation' : null,
      created: 1700000000,
      updated: 1700000100,
      last_login: 1700000200,
      planid: 'basic',
      locale: 'en',
    },
    details: {
      secrets: {
        count: 1,
        items: [
          { secret_id: 's1', shortid: 'sh1', state: 'new', created: 1700000000, expiration: 1700003600 },
        ],
      },
      receipts: {
        count: 1,
        items: [{ receipt_id: 'r1', shortid: 'rh1', state: 'viewed', created: 1700000050 }],
      },
      organizations: [
        { organization_id: 'o1', extid: 'og_acme', display_name: 'Acme', is_default: true },
      ],
      billing: billingPayload(overrides.billing),
      stats: { secrets_created: 5, secrets_shared: 2, emails_sent: 3 },
    },
  };
}

function mutationAck() {
  return { shrimp: '', record: { user_id: 'objid', extid: PUBLIC_ID }, details: { message: 'ok' } };
}

const mountView = () =>
  mount(AdminCustomerDetail, {
    props: { id: PUBLIC_ID },
    global: { plugins: [i18n] },
  });

const dialogInput = (w: VueWrapper) => w.find('#admin-confirm-input');
const dialogSubmit = (w: VueWrapper) => w.find('[data-testid="admin-confirm-submit"]');

describe('AdminCustomerDetail (ticket #22)', () => {
  let wrapper: VueWrapper;

  beforeEach(() => vi.clearAllMocks());
  afterEach(() => wrapper?.unmount());

  // ---- Read-out states ------------------------------------------------------

  describe('read-out + states', () => {
    it('fetches by public id on mount and renders the support read-out', async () => {
      mockApi.get.mockResolvedValue({ data: detailPayload() });
      wrapper = mountView();
      await flushPromises();

      expect(mockApi.get).toHaveBeenCalledWith('/api/colonel/users/ur_alice', undefined);
      expect(wrapper.find('[data-testid="detail-content"]').exists()).toBe(true);
      // Profile fields, stat tiles, secrets/receipts/orgs are all present.
      // Email is obscured by default (RevealEmail); full address hidden until reveal.
      expect(wrapper.find('[data-testid="profile-email"]').text()).toContain('a•••@e•••.com');
      expect(wrapper.find('[data-testid="profile-publicId"]').text()).toContain(PUBLIC_ID);
      expect(wrapper.find('[data-testid="stat-secrets"]').text()).toContain('1');
      expect(wrapper.find('[data-testid="secrets-table"]').text()).toContain('sh1');
      expect(wrapper.find('[data-testid="receipts-table"]').text()).toContain('rh1');
      expect(wrapper.find('[data-testid="organizations-list"]').text()).toContain('Acme');
    });

    it('renders the not-found panel on a 404', async () => {
      mockApi.get.mockRejectedValue(Object.assign(new Error('nf'), { response: { status: 404 } }));
      wrapper = mountView();
      await flushPromises();

      expect(wrapper.find('[data-testid="detail-not-found"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="detail-content"]').exists()).toBe(false);
    });

    it('renders the error panel on a non-404 failure', async () => {
      mockApi.get.mockRejectedValue(Object.assign(new Error('boom'), { response: { status: 500 } }));
      wrapper = mountView();
      await flushPromises();

      expect(wrapper.find('[data-testid="detail-error"]').exists()).toBe(true);
    });

    it('degrades to the error panel on a schema mismatch (contract tripwire)', async () => {
      mockApi.get.mockResolvedValue({ data: { record: { extid: 1 } } });
      wrapper = mountView();
      await flushPromises();

      expect(wrapper.find('[data-testid="detail-error"]').exists()).toBe(true);
    });
  });

  // ---- Guarded actions (CONTRACT 3 / D4) -----------------------------------

  describe('purge — typed-confirmation gate', () => {
    beforeEach(async () => {
      mockApi.get.mockResolvedValue({ data: detailPayload() });
      wrapper = mountView();
      await flushPromises();
    });

    it('opens a danger dialog whose confirm stays disabled until the public id is retyped', async () => {
      await wrapper.find('[data-testid="purge-button"]').trigger('click');
      await flushPromises();

      // Typed-confirmation input is present and confirm is disabled.
      expect(dialogInput(wrapper).exists()).toBe(true);
      expect(dialogSubmit(wrapper).attributes('disabled')).toBeDefined();

      // Wrong text keeps it disabled…
      await dialogInput(wrapper).setValue('not-the-id');
      expect(dialogSubmit(wrapper).attributes('disabled')).toBeDefined();

      // …exact public id enables it.
      await dialogInput(wrapper).setValue(PUBLIC_ID);
      expect(dialogSubmit(wrapper).attributes('disabled')).toBeUndefined();
    });

    it('DELETEs the customer, notifies, and routes back to the list on confirm', async () => {
      mockApi.delete.mockResolvedValue({ data: mutationAck() });

      await wrapper.find('[data-testid="purge-button"]').trigger('click');
      await dialogInput(wrapper).setValue(PUBLIC_ID);
      await wrapper.find('form').trigger('submit');
      await flushPromises();

      expect(mockApi.delete).toHaveBeenCalledWith('/api/colonel/users/ur_alice');
      expect(showMock).toHaveBeenCalledWith('web.admin.customers.actions.purge.success', 'success');
      expect(pushMock).toHaveBeenCalledWith({ name: 'AdminCustomers' });
    });

    it('does NOT delete when submitted without a matching token', async () => {
      mockApi.delete.mockResolvedValue({ data: mutationAck() });
      await wrapper.find('[data-testid="purge-button"]').trigger('click');
      await dialogInput(wrapper).setValue('wrong');
      await wrapper.find('form').trigger('submit');
      await flushPromises();

      expect(mockApi.delete).not.toHaveBeenCalled();
      expect(pushMock).not.toHaveBeenCalled();
    });

    it('surfaces the backend error in the dialog and stays put on failure', async () => {
      mockApi.delete.mockRejectedValue(
        axiosError(422, { error: 'Cannot purge anonymous user' })
      );

      await wrapper.find('[data-testid="purge-button"]').trigger('click');
      await dialogInput(wrapper).setValue(PUBLIC_ID);
      await wrapper.find('form').trigger('submit');
      await flushPromises();

      // Error shown in the dialog; no navigation, no success toast.
      expect(wrapper.find('[role="alert"]').text()).toContain('Cannot purge anonymous user');
      expect(pushMock).not.toHaveBeenCalled();
      expect(showMock).not.toHaveBeenCalled();
    });
  });

  describe('verify / unverify — simple confirm', () => {
    it('verifies an unverified customer and refreshes the record', async () => {
      mockApi.get.mockResolvedValue({ data: detailPayload({ verified: false }) });
      mockApi.post.mockResolvedValue({ data: mutationAck() });
      wrapper = mountView();
      await flushPromises();

      // Simple confirm: no typed input rendered.
      await wrapper.find('[data-testid="verify-button"]').trigger('click');
      await flushPromises();
      expect(dialogInput(wrapper).exists()).toBe(false);

      const getCallsBefore = mockApi.get.mock.calls.length;
      await wrapper.find('form').trigger('submit');
      await flushPromises();

      expect(mockApi.post).toHaveBeenCalledWith('/api/colonel/users/ur_alice/verify', {});
      expect(showMock).toHaveBeenCalledWith('web.admin.customers.actions.verify.success', 'success');
      // Success refreshes the resource (an extra GET), never navigates away.
      expect(mockApi.get.mock.calls.length).toBe(getCallsBefore + 1);
      expect(pushMock).not.toHaveBeenCalled();
    });

    it('shows unverify for a verified customer and calls the unverify endpoint', async () => {
      mockApi.get.mockResolvedValue({ data: detailPayload({ verified: true }) });
      mockApi.post.mockResolvedValue({ data: mutationAck() });
      wrapper = mountView();
      await flushPromises();

      expect(wrapper.find('[data-testid="verify-button"]').exists()).toBe(false);
      await wrapper.find('[data-testid="unverify-button"]').trigger('click');
      await wrapper.find('form').trigger('submit');
      await flushPromises();

      expect(mockApi.post).toHaveBeenCalledWith('/api/colonel/users/ur_alice/unverify', {});
    });
  });

  // ---- Billing card ----------------------------------------------------------

  describe('billing card', () => {
    it('renders plan from the model with the not-configured note when billing is disabled', async () => {
      mockApi.get.mockResolvedValue({ data: detailPayload({ billing: { enabled: false } }) });
      wrapper = mountView();
      await flushPromises();

      const section = wrapper.find('[data-testid="billing-section"]');
      expect(section.exists()).toBe(true);
      expect(section.find('[data-testid="billing-plan"]').text()).toContain('basic');
      expect(section.find('[data-testid="billing-disabled"]').exists()).toBe(true);
      expect(section.find('[data-testid="billing-stripe-link"]').exists()).toBe(false);
    });

    it('degrades to the unavailable note (still showing plan) when Stripe is unreachable', async () => {
      mockApi.get.mockResolvedValue({
        data: detailPayload({
          billing: { enabled: true, stripeAvailable: false, stripeReason: 'Stripe unavailable: timeout' },
        }),
      });
      wrapper = mountView();
      await flushPromises();

      const section = wrapper.find('[data-testid="billing-section"]');
      expect(section.find('[data-testid="billing-plan"]').text()).toContain('basic');
      expect(section.find('[data-testid="billing-unavailable"]').exists()).toBe(true);
      expect(section.find('[data-testid="billing-stripe-link"]').exists()).toBe(false);
      expect(section.find('[data-testid="billing-latestInvoice"]').exists()).toBe(false);
    });

    it('shows the latest invoice and the Stripe dashboard link when the live read worked', async () => {
      mockApi.get.mockResolvedValue({
        data: detailPayload({ billing: { enabled: true, stripeAvailable: true } }),
      });
      wrapper = mountView();
      await flushPromises();

      const section = wrapper.find('[data-testid="billing-section"]');
      const invoice = section.find('[data-testid="billing-latestInvoice"]');
      expect(invoice.exists()).toBe(true);
      // date · amount · status
      expect(invoice.text()).toContain('35.00 USD');
      expect(invoice.text()).toContain('paid');
      expect(section.find('[data-testid="billing-subscriptionStatus"]').text()).toContain('active');

      const link = section.find('[data-testid="billing-stripe-link"]');
      expect(link.exists()).toBe(true);
      expect(link.attributes('href')).toBe('https://dashboard.stripe.com/customers/cus_123');
      expect(link.attributes('target')).toBe('_blank');
    });
  });

  // ---- Suspend / unsuspend ----------------------------------------------------

  describe('suspend — typed-confirmation gate (reversible pause)', () => {
    beforeEach(async () => {
      mockApi.get.mockResolvedValue({ data: detailPayload() });
      wrapper = mountView();
      await flushPromises();
    });

    it('requires retyping the public id, then POSTs suspend with the reason', async () => {
      mockApi.post.mockResolvedValue({ data: mutationAck() });

      await wrapper.find('[data-testid="suspend-reason"]').setValue('abuse report');
      await wrapper.find('[data-testid="suspend-button"]').trigger('click');
      await flushPromises();

      // Typed-confirmation input present; confirm disabled until the id matches.
      expect(dialogInput(wrapper).exists()).toBe(true);
      expect(dialogSubmit(wrapper).attributes('disabled')).toBeDefined();

      await dialogInput(wrapper).setValue(PUBLIC_ID);
      expect(dialogSubmit(wrapper).attributes('disabled')).toBeUndefined();

      await wrapper.find('form').trigger('submit');
      await flushPromises();

      expect(mockApi.post).toHaveBeenCalledWith('/api/colonel/users/ur_alice/suspend', {
        reason: 'abuse report',
      });
      expect(showMock).toHaveBeenCalledWith(
        'web.admin.customers.actions.suspend.success',
        'success'
      );
      // Stays on the page and refreshes (suspension is reversible — not purge).
      expect(pushMock).not.toHaveBeenCalled();
    });

    it('omits the reason key when no reason is given', async () => {
      mockApi.post.mockResolvedValue({ data: mutationAck() });

      await wrapper.find('[data-testid="suspend-button"]').trigger('click');
      await dialogInput(wrapper).setValue(PUBLIC_ID);
      await wrapper.find('form').trigger('submit');
      await flushPromises();

      expect(mockApi.post).toHaveBeenCalledWith('/api/colonel/users/ur_alice/suspend', {});
    });

    it('does NOT suspend when submitted without a matching token', async () => {
      mockApi.post.mockResolvedValue({ data: mutationAck() });

      await wrapper.find('[data-testid="suspend-button"]').trigger('click');
      await dialogInput(wrapper).setValue('wrong');
      await wrapper.find('form').trigger('submit');
      await flushPromises();

      expect(mockApi.post).not.toHaveBeenCalled();
    });
  });

  describe('suspended state + unsuspend', () => {
    it('shows the SUSPENDED badge, suspension fields, and the unsuspend action', async () => {
      mockApi.get.mockResolvedValue({ data: detailPayload({ suspended: true }) });
      mockApi.post.mockResolvedValue({ data: mutationAck() });
      wrapper = mountView();
      await flushPromises();

      expect(wrapper.find('[data-testid="suspended-badge"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="profile-suspendedReason"]').text()).toContain(
        'tos violation'
      );
      expect(wrapper.find('[data-testid="suspend-button"]').exists()).toBe(false);

      // Unsuspend is a simple confirm (no typed input).
      await wrapper.find('[data-testid="unsuspend-button"]').trigger('click');
      await flushPromises();
      expect(dialogInput(wrapper).exists()).toBe(false);

      await wrapper.find('form').trigger('submit');
      await flushPromises();

      expect(mockApi.post).toHaveBeenCalledWith('/api/colonel/users/ur_alice/unsuspend', {});
      expect(showMock).toHaveBeenCalledWith(
        'web.admin.customers.actions.unsuspend.success',
        'success'
      );
    });

    it('hides the suspended badge and fields for a non-suspended customer', async () => {
      mockApi.get.mockResolvedValue({ data: detailPayload() });
      wrapper = mountView();
      await flushPromises();

      expect(wrapper.find('[data-testid="suspended-badge"]').exists()).toBe(false);
      expect(wrapper.find('[data-testid="profile-suspendedReason"]').exists()).toBe(false);
      expect(wrapper.find('[data-testid="unsuspend-button"]').exists()).toBe(false);
    });

    it('offers no suspend action for colonel accounts (privilege guard)', async () => {
      mockApi.get.mockResolvedValue({ data: detailPayload({ role: 'colonel' }) });
      wrapper = mountView();
      await flushPromises();

      expect(wrapper.find('[data-testid="suspend-button"]').exists()).toBe(false);
      expect(wrapper.find('[data-testid="suspend-reason"]').exists()).toBe(false);
    });
  });

  describe('change role — simple confirm', () => {
    it('is disabled until a different role is chosen, then posts the role change', async () => {
      mockApi.get.mockResolvedValue({ data: detailPayload({ role: 'customer' }) });
      mockApi.post.mockResolvedValue({ data: mutationAck() });
      wrapper = mountView();
      await flushPromises();

      // Apply is disabled while the selector still shows the current role.
      expect(wrapper.find('[data-testid="role-apply"]').attributes('disabled')).toBeDefined();

      await wrapper.find('[data-testid="role-select"]').setValue('admin');
      expect(wrapper.find('[data-testid="role-apply"]').attributes('disabled')).toBeUndefined();

      await wrapper.find('[data-testid="role-apply"]').trigger('click');
      await wrapper.find('form').trigger('submit');
      await flushPromises();

      expect(mockApi.post).toHaveBeenCalledWith('/api/colonel/users/ur_alice/role', {
        role: 'admin',
      });
      expect(showMock).toHaveBeenCalledWith('web.admin.customers.actions.role.success', 'success');
    });
  });
});
