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

function detailPayload(overrides: { role?: string; verified?: boolean } = {}) {
  return {
    shrimp: '',
    record: {
      extid: PUBLIC_ID,
      email: 'alice@example.com',
      role: overrides.role ?? 'customer',
      verified: overrides.verified ?? false,
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
      expect(wrapper.find('[data-testid="profile-email"]').text()).toContain('alice@example.com');
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
