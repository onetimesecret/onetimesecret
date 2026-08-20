// src/tests/apps/admin/AdminCustomerDetail.spec.ts

import { flushPromises, mount, VueWrapper } from '@vue/test-utils';
import { AxiosError } from 'axios';
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
/** Purge is gated on the account EMAIL (suspend still uses the public id). */
const PURGE_TOKEN = 'alice@example.com';

function detailPayload(
  overrides: {
    role?: string;
    verified?: boolean;
    suspended?: boolean;
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
        truncated: false,
        items: [
          {
            secret_id: 's1',
            shortid: 'sh1',
            state: 'new',
            created: 1700000000,
            expiration: 1700003600,
          },
        ],
      },
      receipts: {
        count: 1,
        truncated: false,
        items: [{ receipt_id: 'r1', shortid: 'rh1', state: 'viewed', created: 1700000050 }],
      },
      organizations: [
        { organization_id: 'o1', extid: 'og_acme', display_name: 'Acme', is_default: true },
      ],

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
    global: {
      plugins: [i18n],
      // The active-sessions and diagnostics panels are self-contained children
      // with their own specs; stub them so this view's tests don't fetch their
      // endpoints or match their error `role="alert"`.
      stubs: { AdminCustomerSessionsSection: true, AdminAccountDiagnosticsSection: true },
    },
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

    // The endpoint reads a bounded page off the per-owner index, so a short
    // list is not proof of a short history. `truncated` is how the server says
    // "this is partial" — the view must never render a partial list as if it
    // were the whole record.
    it('says nothing about truncation when the payload is complete', async () => {
      mockApi.get.mockResolvedValue({ data: detailPayload() });
      wrapper = mountView();
      await flushPromises();

      expect(wrapper.find('[data-testid="secrets-truncated"]').exists()).toBe(false);
      expect(wrapper.find('[data-testid="receipts-truncated"]').exists()).toBe(false);
    });

    it('flags a partial secrets/receipts list when the server truncated it', async () => {
      const payload = detailPayload();
      payload.details.secrets.truncated = true;
      payload.details.receipts.truncated = true;
      mockApi.get.mockResolvedValue({ data: payload });
      wrapper = mountView();
      await flushPromises();

      expect(wrapper.find('[data-testid="secrets-truncated"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="receipts-truncated"]').exists()).toBe(true);
      // The rest of the record still renders — truncation is not an error state.
      expect(wrapper.find('[data-testid="detail-content"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="secrets-table"]').text()).toContain('sh1');
    });

    it('renders the not-found panel on a 404', async () => {
      mockApi.get.mockRejectedValue(Object.assign(new Error('nf'), { response: { status: 404 } }));
      wrapper = mountView();
      await flushPromises();

      expect(wrapper.find('[data-testid="detail-not-found"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="detail-content"]').exists()).toBe(false);
    });

    it('renders the error panel on a non-404 failure', async () => {
      mockApi.get.mockRejectedValue(
        Object.assign(new Error('boom'), { response: { status: 500 } })
      );
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

    it('renders an "Open" link for each organization that navigates to AdminOrganizationDetail', async () => {
      mockApi.get.mockResolvedValue({ data: detailPayload() });
      wrapper = mountView();
      await flushPromises();

      // The organization link routes to the detail page (data-testid set by the component)
      const orgLink = wrapper.find('[data-testid="organization-link"]');
      expect(orgLink.exists()).toBe(true);
    });
  });

  // ---- Guarded actions (CONTRACT 3 / D4) -----------------------------------

  describe('purge — typed-confirmation gate', () => {
    beforeEach(async () => {
      mockApi.get.mockResolvedValue({ data: detailPayload() });
      wrapper = mountView();
      await flushPromises();
    });

    it('opens a danger dialog whose confirm stays disabled until the account email is retyped', async () => {
      await wrapper.find('[data-testid="purge-button"]').trigger('click');
      await flushPromises();

      // Typed-confirmation input is present and confirm is disabled.
      expect(dialogInput(wrapper).exists()).toBe(true);
      expect(dialogSubmit(wrapper).attributes('disabled')).toBeDefined();

      // Wrong text keeps it disabled…
      await dialogInput(wrapper).setValue('not-the-id');
      expect(dialogSubmit(wrapper).attributes('disabled')).toBeDefined();

      // …the public id is NOT the purge token any more; only the email is.
      await dialogInput(wrapper).setValue(PUBLIC_ID);
      expect(dialogSubmit(wrapper).attributes('disabled')).toBeDefined();

      // …exact account email enables it.
      await dialogInput(wrapper).setValue(PURGE_TOKEN);
      expect(dialogSubmit(wrapper).attributes('disabled')).toBeUndefined();
    });

    it('DELETEs the customer, notifies, and routes back to the list on confirm', async () => {
      mockApi.delete.mockResolvedValue({ data: mutationAck() });

      await wrapper.find('[data-testid="purge-button"]').trigger('click');
      await dialogInput(wrapper).setValue(PURGE_TOKEN);
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
      mockApi.delete.mockRejectedValue(axiosError(422, { error: 'Cannot purge anonymous user' }));

      await wrapper.find('[data-testid="purge-button"]').trigger('click');
      await dialogInput(wrapper).setValue(PURGE_TOKEN);
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
      expect(showMock).toHaveBeenCalledWith(
        'web.admin.customers.actions.verify.success',
        'success'
      );
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

  it('does not render billing or plan controls on the customer detail page', async () => {
    mockApi.get.mockResolvedValue({ data: detailPayload() });
    wrapper = mountView();
    await flushPromises();

    expect(wrapper.find('[data-testid="billing-section"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="plan-select"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="checkout-link-button"]').exists()).toBe(false);
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
