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
// DialogPanel renders its default slot, which for DetailDrawer contains the
// header/body/footer slot outlets.
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

const LIST_URL = '/api/colonel/secrets';
const SECRET_ID = 's1';
const SHORT_ID = 'abc123';
const RECEIPT_URL = `/api/colonel/secrets/${SECRET_ID}`;

function secretsPayload() {
  return {
    shrimp: '',
    record: {},
    details: {
      secrets: [
        {
          secret_id: SECRET_ID,
          shortid: SHORT_ID,
          owner_id: 'ext_owner',
          state: 'received',
          created: 1700000000,
          expiration: 1700003600,
          lifespan: 3600,
          receipt_id: 'r1',
          age: 172800,
          has_ciphertext: true,
        },
      ],
      pagination: { page: 1, per_page: 50, total_count: 1, total_pages: 1 },
    },
  };
}

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

/** Route GETs by URL so the list + receipt fetches return distinct payloads. */
function routeGet() {
  mockApi.get.mockImplementation((url: string) => {
    if (url === RECEIPT_URL) return Promise.resolve({ data: receiptPayload() });
    return Promise.resolve({ data: secretsPayload() });
  });
}

const mountView = (pinia: ReturnType<typeof createPinia>) =>
  mount(AdminSecrets, {
    global: { plugins: [pinia, i18n], stubs: { JsonViewer: true } },
  });

const dialogInput = (w: VueWrapper) => w.find('#admin-confirm-input');
const dialogSubmit = (w: VueWrapper) => w.find('[data-testid="admin-confirm-submit"]');

describe('AdminSecrets (list + receipt + guarded delete — ticket #30)', () => {
  let wrapper: VueWrapper;
  let pinia: ReturnType<typeof createPinia>;

  beforeEach(() => {
    pinia = createPinia();
    setActivePinia(pinia);
    vi.clearAllMocks();
  });
  afterEach(() => wrapper?.unmount());

  // ---- List -----------------------------------------------------------------

  it('fetches the first page on mount and renders a row per secret', async () => {
    routeGet();
    wrapper = mountView(pinia);
    await flushPromises();

    expect(mockApi.get).toHaveBeenCalledWith(LIST_URL, {
      params: { page: 1, per_page: 50 },
    });
    const table = wrapper.find('[data-testid="secrets-table"]');
    expect(table.exists()).toBe(true);
    expect(table.text()).toContain(SHORT_ID);
    // Age rendered in whole days (172800s / 86400 = 2).
    expect(table.text()).toContain('2');
    // No filter bar (the list endpoint offers no server-side filter).
    expect(wrapper.find('[data-testid="secrets-filterbar"]').exists()).toBe(false);
  });

  it('shows the error banner + retry on a network failure', async () => {
    mockApi.get.mockRejectedValue(new Error('Network Error'));
    wrapper = mountView(pinia);
    await flushPromises();

    const banner = wrapper.find('[data-testid="secrets-error"]');
    expect(banner.exists()).toBe(true);

    routeGet();
    await banner.find('button').trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-testid="secrets-error"]').exists()).toBe(false);
  });

  // ---- Receipt drawer -------------------------------------------------------

  it('opens the receipt drawer and fetches GetSecretReceipt on row click', async () => {
    routeGet();
    wrapper = mountView(pinia);
    await flushPromises();

    await wrapper.find('[data-testid="secrets-table"] tbody tr').trigger('click');
    await flushPromises();

    expect(mockApi.get).toHaveBeenCalledWith(RECEIPT_URL, undefined);
    const content = wrapper.find('[data-testid="secret-drawer-content"]');
    expect(content.exists()).toBe(true);
    expect(wrapper.find('[data-testid="secret-field-secretId"]').text()).toContain(SECRET_ID);
    // Receipt + owner sub-sections render from details.
    expect(wrapper.find('[data-testid="receipt-field-receiptId"]').text()).toContain('r1');
    expect(wrapper.find('[data-testid="owner-field-email"]').text()).toContain('o***@e***.com');
  });

  it('renders the not-found panel in the drawer on a 404', async () => {
    mockApi.get.mockImplementation((url: string) => {
      if (url === RECEIPT_URL) {
        return Promise.reject(Object.assign(new Error('nf'), { response: { status: 404 } }));
      }
      return Promise.resolve({ data: secretsPayload() });
    });
    wrapper = mountView(pinia);
    await flushPromises();

    await wrapper.find('[data-testid="secrets-table"] tbody tr').trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-testid="secret-drawer-not-found"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="secret-drawer-content"]').exists()).toBe(false);
  });

  // ---- Guarded delete (D4) --------------------------------------------------

  describe('delete — typed-confirmation gate', () => {
    beforeEach(async () => {
      routeGet();
      wrapper = mountView(pinia);
      await flushPromises();
      await wrapper.find('[data-testid="secrets-table"] tbody tr').trigger('click');
      await flushPromises();
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

    it('DELETEs the secret, notifies, closes the drawer and refreshes the list on confirm', async () => {
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
      const listGetsBefore = mockApi.get.mock.calls.filter((c) => c[0] === LIST_URL).length;

      await wrapper.find('[data-testid="secret-delete-button"]').trigger('click');
      await dialogInput(wrapper).setValue(SHORT_ID);
      await wrapper.find('form').trigger('submit');
      await flushPromises();

      expect(mockApi.delete).toHaveBeenCalledWith(RECEIPT_URL);
      expect(showMock).toHaveBeenCalledWith('web.admin.secrets.actions.delete.success', 'success');
      // Drawer closed + list re-fetched (one more list GET than before).
      expect(wrapper.find('[data-testid="secret-drawer-content"]').exists()).toBe(false);
      const listGetsAfter = mockApi.get.mock.calls.filter((c) => c[0] === LIST_URL).length;
      expect(listGetsAfter).toBe(listGetsBefore + 1);
    });

    it('does NOT delete when submitted without a matching token', async () => {
      mockApi.delete.mockResolvedValue({ data: {} });
      await wrapper.find('[data-testid="secret-delete-button"]').trigger('click');
      await dialogInput(wrapper).setValue('wrong');
      await wrapper.find('form').trigger('submit');
      await flushPromises();

      expect(mockApi.delete).not.toHaveBeenCalled();
      expect(showMock).not.toHaveBeenCalled();
    });

    it('surfaces the backend error in the dialog and stays put on failure', async () => {
      mockApi.delete.mockRejectedValue(axiosError(422, { error: 'Secret not found' }));

      await wrapper.find('[data-testid="secret-delete-button"]').trigger('click');
      await dialogInput(wrapper).setValue(SHORT_ID);
      await wrapper.find('form').trigger('submit');
      await flushPromises();

      expect(wrapper.find('[role="alert"]').text()).toContain('Secret not found');
      expect(showMock).not.toHaveBeenCalled();
    });
  });
});
