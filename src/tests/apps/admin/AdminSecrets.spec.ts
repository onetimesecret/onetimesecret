// src/tests/apps/admin/AdminSecrets.spec.ts

import { AxiosError } from 'axios';
import { createPinia, setActivePinia } from 'pinia';
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

// Render HeadlessUI dialog markup synchronously (mirrors AdminCustomerDetail.spec).
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

import AdminSecrets from '@/apps/admin/views/AdminSecrets.vue';
import { createTestI18n } from '@tests/setup';

const i18n = createTestI18n();

const SECRET_ID = 's1';
const SHORT_ID = 'abc123';
const RECEIPT_URL = `/api/colonel/secrets/${SECRET_ID}`;

function receiptPayload() {
  return {
    shrimp: '',
    record: {
      secret_id: SECRET_ID,
      shortid: SHORT_ID,
      state: 'received',
      lifespan: 3600,
      created: 1700000000,
      updated: 1700000100,
      expiration: 1700003600,
      age: 172800,
      owner_id: 'ext_owner',
      receipt_id: 'r1',
      has_ciphertext: true,
      ciphertext_length: 256,
    },
    details: {
      metadata: {
        receipt_id: 'r1',
        shortid: 'rh1',
        state: 'viewed',
        secret_ttl: 3600,
        recipients: ['alice@example.com'],
        has_passphrase: false,
        share_domain: 'example.com',
        created: 1700000000,
        secret_expired: false,
      },
      owner: { user_id: 'objid_owner', email: 'o***@e***.com', role: 'customer', verified: true },
    },
  };
}

const mountView = (pinia: ReturnType<typeof createPinia>) =>
  mount(AdminSecrets, {
    global: { plugins: [pinia, i18n], stubs: { JsonViewer: true } },
  });

/** Type the key into the lookup input and submit the lookup form. */
async function lookup(w: VueWrapper, key = SECRET_ID) {
  await w.find('[data-testid="secret-lookup-input"]').setValue(key);
  await w.find('[data-testid="secret-lookup-form"]').trigger('submit');
  await flushPromises();
}

const dialogInput = (w: VueWrapper) => w.find('#admin-confirm-input');
const dialogSubmit = (w: VueWrapper) => w.find('[data-testid="admin-confirm-submit"]');
const dialogForm = (w: VueWrapper) => w.find('[data-testid="admin-confirm-dialog"] form');

describe('AdminSecrets (lookup-first inspect + guarded delete — ticket #30)', () => {
  let wrapper: VueWrapper;
  let pinia: ReturnType<typeof createPinia>;

  beforeEach(() => {
    pinia = createPinia();
    setActivePinia(pinia);
    vi.clearAllMocks();
  });
  afterEach(() => wrapper?.unmount());

  // ---- Lookup ----------------------------------------------------------------

  it('renders the lookup form and calls NOTHING on mount (no browse-all list)', async () => {
    wrapper = mountView(pinia);
    await flushPromises();

    // Lookup-first by design review: the list endpoint still exists
    // server-side but the UI must never call it (or anything else) on mount.
    expect(mockApi.get).not.toHaveBeenCalled();
    expect(wrapper.find('[data-testid="secret-lookup-form"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="secret-lookup-result"]').exists()).toBe(false);
  });

  it('disables the lookup submit until a key is entered', async () => {
    wrapper = mountView(pinia);

    const submit = wrapper.find('[data-testid="secret-lookup-submit"]');
    expect(submit.attributes('disabled')).toBeDefined();

    await wrapper.find('[data-testid="secret-lookup-input"]').setValue(SECRET_ID);
    expect(submit.attributes('disabled')).toBeUndefined();
  });

  it('fetches GetSecretReceipt for the entered key and renders the read-out', async () => {
    mockApi.get.mockResolvedValue({ data: receiptPayload() });
    wrapper = mountView(pinia);

    await lookup(wrapper);

    expect(mockApi.get).toHaveBeenCalledWith(RECEIPT_URL, undefined);
    const result = wrapper.find('[data-testid="secret-lookup-result"]');
    expect(result.exists()).toBe(true);
    expect(wrapper.find('[data-testid="secret-field-secretId"]').text()).toContain(SECRET_ID);
    // Receipt + owner sub-sections render from details.
    expect(wrapper.find('[data-testid="receipt-field-receiptId"]').text()).toContain('r1');
    expect(wrapper.find('[data-testid="owner-field-email"]').text()).toContain('o***@e***.com');
  });

  it('renders the not-found panel on a 404', async () => {
    mockApi.get.mockRejectedValue(
      Object.assign(new Error('nf'), { response: { status: 404 } })
    );
    wrapper = mountView(pinia);

    await lookup(wrapper, 'does-not-exist');

    expect(wrapper.find('[data-testid="secret-lookup-not-found"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="secret-lookup-result"]').exists()).toBe(false);
  });

  it('renders the load-error panel with retry on a network failure', async () => {
    mockApi.get.mockRejectedValueOnce(new Error('Network Error'));
    wrapper = mountView(pinia);

    await lookup(wrapper);

    const errorPanel = wrapper.find('[data-testid="secret-lookup-error"]');
    expect(errorPanel.exists()).toBe(true);

    mockApi.get.mockResolvedValue({ data: receiptPayload() });
    await errorPanel.find('button').trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-testid="secret-lookup-error"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="secret-lookup-result"]').exists()).toBe(true);
  });

  // ---- Guarded delete (D4) --------------------------------------------------

  describe('delete — typed-confirmation gate', () => {
    beforeEach(async () => {
      mockApi.get.mockResolvedValue({ data: receiptPayload() });
      wrapper = mountView(pinia);
      await lookup(wrapper);
    });

    it('opens a danger dialog whose confirm stays disabled until the short id is retyped', async () => {
      await wrapper.find('[data-testid="secret-delete-button"]').trigger('click');
      await flushPromises();

      expect(dialogInput(wrapper).exists()).toBe(true);
      expect(dialogSubmit(wrapper).attributes('disabled')).toBeDefined();

      await dialogInput(wrapper).setValue('not-the-id');
      expect(dialogSubmit(wrapper).attributes('disabled')).toBeDefined();

      await dialogInput(wrapper).setValue(SHORT_ID);
      expect(dialogSubmit(wrapper).attributes('disabled')).toBeUndefined();
    });

    it('DELETEs the secret, notifies, and clears the read-out on confirm', async () => {
      mockApi.delete.mockResolvedValue({
        data: {
          shrimp: '',
          record: {
            deleted: true,
            secret: { secret_id: SECRET_ID, shortid: SHORT_ID, state: 'received', owner_id: 'ext_owner' },
            metadata: { receipt_id: 'r1', shortid: 'rh1' },
          },
          details: { message: 'Secret and associated receipt deleted successfully' },
        },
      });

      await wrapper.find('[data-testid="secret-delete-button"]').trigger('click');
      await dialogInput(wrapper).setValue(SHORT_ID);
      await dialogForm(wrapper).trigger('submit');
      await flushPromises();

      expect(mockApi.delete).toHaveBeenCalledWith(RECEIPT_URL);
      expect(showMock).toHaveBeenCalledWith('web.admin.secrets.actions.delete.success', 'success');
      // The read-out clears back to the lookup prompt (the secret is gone).
      expect(wrapper.find('[data-testid="secret-lookup-result"]').exists()).toBe(false);
      const input = wrapper.find('[data-testid="secret-lookup-input"]')
        .element as HTMLInputElement;
      expect(input.value).toBe('');
    });

    it('does NOT delete when submitted without a matching token', async () => {
      mockApi.delete.mockResolvedValue({ data: {} });
      await wrapper.find('[data-testid="secret-delete-button"]').trigger('click');
      await dialogInput(wrapper).setValue('wrong');
      await dialogForm(wrapper).trigger('submit');
      await flushPromises();

      expect(mockApi.delete).not.toHaveBeenCalled();
      expect(showMock).not.toHaveBeenCalled();
    });

    it('surfaces the backend error in the dialog and stays put on failure', async () => {
      mockApi.delete.mockRejectedValue(axiosError(422, { error: 'Secret not found' }));

      await wrapper.find('[data-testid="secret-delete-button"]').trigger('click');
      await dialogInput(wrapper).setValue(SHORT_ID);
      await dialogForm(wrapper).trigger('submit');
      await flushPromises();

      expect(wrapper.find('[role="alert"]').text()).toContain('Secret not found');
      expect(showMock).not.toHaveBeenCalled();
      // The read-out stays so the operator can retry or cancel.
      expect(wrapper.find('[data-testid="secret-lookup-result"]').exists()).toBe(true);
    });
  });
});
