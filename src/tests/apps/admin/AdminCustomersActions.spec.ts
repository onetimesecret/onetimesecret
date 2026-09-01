// src/tests/apps/admin/AdminCustomersActions.spec.ts

import { AxiosError } from 'axios';
import { createPinia, setActivePinia } from 'pinia';
import { flushPromises, mount, RouterLinkStub, VueWrapper } from '@vue/test-utils';
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
  useRoute: () => ({ params: {} }),
}));

const showMock = vi.fn();
vi.mock('@/shared/stores/notificationsStore', () => ({
  useNotificationsStore: () => ({ show: showMock }),
}));

// Deterministic, bootstrap-free date rendering.
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

// Render the drawer + confirm dialog markup synchronously and IN-PLACE (the real
// headlessui Dialog teleports to <body>, escaping the mounted wrapper).
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

class ResizeObserverStub {
  observe(): void {}
  unobserve(): void {}
  disconnect(): void {}
}
globalThis.ResizeObserver = ResizeObserverStub as unknown as typeof ResizeObserver;

import AdminCustomers from '@/apps/admin/views/AdminCustomers.vue';
import { useAdminCustomers } from '@/apps/admin/stores/useAdminCustomers';
import { createTestI18n } from '@tests/setup';

const i18n = createTestI18n();

const PUBLIC_ID = 'ur_alice';
const EMAIL = 'alice@example.com';

/** Wire-shape users page (numbers for dates) so the REAL schema runs unchanged. */
function usersPayload(overrides: { verified?: boolean } = {}) {
  return {
    shrimp: '',
    record: {},
    details: {
      users: [
        {
          user_id: PUBLIC_ID,
          extid: PUBLIC_ID,
          email: EMAIL,
          role: 'customer',
          verified: overrides.verified ?? false,
          suspended: false,
          created: 1700000000,
          last_login: 1700000100,
          planid: 'basic',
          secrets_count: 3,
          secrets_created: 5,
          secrets_shared: 2,
        },
      ],
      pagination: { page: 1, per_page: 50, total_count: 1, total_pages: 1, role_filter: null },
    },
  };
}

/** Empty page — what the list returns after the only row is purged. */
function emptyPayload() {
  return {
    shrimp: '',
    record: {},
    details: {
      users: [],
      pagination: { page: 1, per_page: 50, total_count: 0, total_pages: 0, role_filter: null },
    },
  };
}

function mutationAck() {
  return {
    shrimp: '',
    record: { user_id: 'objid', extid: PUBLIC_ID },
    details: { message: 'ok' },
  };
}

const dialogInput = (w: VueWrapper) => w.find('#admin-confirm-input');
const dialogSubmit = (w: VueWrapper) => w.find('[data-testid="admin-confirm-submit"]');
const dialogReason = (w: VueWrapper) => w.find('[data-testid="admin-confirm-reason"]');
const drawer = (w: VueWrapper) => w.find('[data-testid="customers-drawer"]');

describe('AdminCustomers — drawer operator actions', () => {
  let wrapper: VueWrapper;
  let pinia: ReturnType<typeof createPinia>;

  beforeEach(() => {
    pinia = createPinia();
    setActivePinia(pinia);
    vi.clearAllMocks();
  });
  afterEach(() => wrapper?.unmount());

  const mountView = () =>
    mount(AdminCustomers, {
      global: { plugins: [pinia, i18n], stubs: { RouterLink: RouterLinkStub } },
    });

  /** Mount, load one row, and open its drawer. */
  async function openDrawer(overrides: { verified?: boolean } = {}): Promise<void> {
    mockApi.get.mockResolvedValue({ data: usersPayload(overrides) });
    wrapper = mountView();
    await flushPromises();
    await wrapper.find('[data-testid="customers-table"] tbody tr').trigger('click');
    await flushPromises();
  }

  describe('verification state + verb selection', () => {
    it('shows the unverified pill and offers ONLY verify', async () => {
      await openDrawer({ verified: false });

      expect(drawer(wrapper).find('[data-testid="customer-drawer-verification"]').text()).toContain(
        'web.admin.customers.verification.unverified'
      );
      expect(wrapper.find('[data-testid="drawer-verify-button"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="drawer-unverify-button"]').exists()).toBe(false);
    });

    it('shows the verified pill and offers ONLY unverify', async () => {
      await openDrawer({ verified: true });

      expect(drawer(wrapper).find('[data-testid="customer-drawer-verification"]').text()).toContain(
        'web.admin.customers.verification.verified'
      );
      expect(wrapper.find('[data-testid="drawer-unverify-button"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="drawer-verify-button"]').exists()).toBe(false);
    });
  });

  describe('verify / unverify — simple confirm', () => {
    it('POSTs verify, toasts, and flips the drawer + row without re-reading the list', async () => {
      await openDrawer({ verified: false });
      mockApi.post.mockResolvedValue({ data: mutationAck() });
      const getCallsBefore = mockApi.get.mock.calls.length;

      // Reversible action: one-click confirm, no typed-confirmation input.
      await wrapper.find('[data-testid="drawer-verify-button"]').trigger('click');
      await flushPromises();
      expect(dialogInput(wrapper).exists()).toBe(false);

      await wrapper.find('form').trigger('submit');
      await flushPromises();

      expect(mockApi.post).toHaveBeenCalledWith(`/api/colonel/users/${PUBLIC_ID}/verify`, {});
      expect(showMock).toHaveBeenCalledWith(
        'web.admin.customers.actions.verify.success',
        'success'
      );

      // Displayed state updates from the ack — no reload, no extra GET.
      expect(mockApi.get.mock.calls.length).toBe(getCallsBefore);
      expect(drawer(wrapper).find('[data-testid="customer-drawer-verification"]').text()).toContain(
        'web.admin.customers.verification.verified'
      );
      // …and the action offered flips to the opposite verb.
      expect(wrapper.find('[data-testid="drawer-unverify-button"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="drawer-verify-button"]').exists()).toBe(false);
      // The underlying row is patched too, so the table cell agrees.
      expect(useAdminCustomers().customers[0].verified).toBe(true);
    });

    it('POSTs unverify for a verified account and flips the pill back', async () => {
      await openDrawer({ verified: true });
      mockApi.post.mockResolvedValue({ data: mutationAck() });

      await wrapper.find('[data-testid="drawer-unverify-button"]').trigger('click');
      await wrapper.find('form').trigger('submit');
      await flushPromises();

      expect(mockApi.post).toHaveBeenCalledWith(`/api/colonel/users/${PUBLIC_ID}/unverify`, {});
      expect(drawer(wrapper).find('[data-testid="customer-drawer-verification"]').text()).toContain(
        'web.admin.customers.verification.unverified'
      );
    });

    it('keeps the failure in the dialog and does not toast or change state', async () => {
      await openDrawer({ verified: false });
      mockApi.post.mockRejectedValue(axiosError(422, { error: 'Account has no auth record' }));

      await wrapper.find('[data-testid="drawer-verify-button"]').trigger('click');
      await wrapper.find('form').trigger('submit');
      await flushPromises();

      expect(wrapper.find('[data-testid="admin-confirm-dialog"]').text()).toContain(
        'Account has no auth record'
      );
      expect(showMock).not.toHaveBeenCalled();
      expect(drawer(wrapper).find('[data-testid="customer-drawer-verification"]').text()).toContain(
        'web.admin.customers.verification.unverified'
      );
    });
  });

  describe('purge — typed-confirmation on the email', () => {
    it('stays disabled until the EXACT email is retyped (the public id does not unlock it)', async () => {
      await openDrawer();

      await wrapper.find('[data-testid="drawer-purge-button"]').trigger('click');
      await flushPromises();

      expect(dialogInput(wrapper).exists()).toBe(true);
      expect(dialogSubmit(wrapper).attributes('disabled')).toBeDefined();

      // The public id is NOT the token for a purge.
      await dialogInput(wrapper).setValue(PUBLIC_ID);
      expect(dialogSubmit(wrapper).attributes('disabled')).toBeDefined();

      // Case matters — the gate is an exact, untrimmed match.
      await dialogInput(wrapper).setValue(EMAIL.toUpperCase());
      expect(dialogSubmit(wrapper).attributes('disabled')).toBeDefined();

      await dialogInput(wrapper).setValue(EMAIL);
      expect(dialogSubmit(wrapper).attributes('disabled')).toBeUndefined();
    });

    it('DELETEs, toasts, closes the drawer and refreshes the list', async () => {
      await openDrawer();
      mockApi.delete.mockResolvedValue({ data: mutationAck() });
      mockApi.get.mockResolvedValue({ data: emptyPayload() });
      const getCallsBefore = mockApi.get.mock.calls.length;

      await wrapper.find('[data-testid="drawer-purge-button"]').trigger('click');
      await dialogInput(wrapper).setValue(EMAIL);
      await wrapper.find('form').trigger('submit');
      await flushPromises();

      expect(mockApi.delete).toHaveBeenCalledWith(`/api/colonel/users/${PUBLIC_ID}`);
      expect(showMock).toHaveBeenCalledWith('web.admin.customers.actions.purge.success', 'success');
      expect(drawer(wrapper).exists()).toBe(false);
      // The list is re-read (totals/pagination move server-side).
      expect(mockApi.get.mock.calls.length).toBe(getCallsBefore + 1);
      expect(mockApi.get).toHaveBeenLastCalledWith('/api/colonel/users', {
        params: { page: 1, per_page: 50 },
      });
      // Stays on the list — the drawer never navigated anywhere.
      expect(pushMock).not.toHaveBeenCalled();
    });

    // #4338 — the adapter-level half: what the operator types in the dialog has
    // to reach the endpoint, or the trail still cannot say why. This is a DELETE,
    // so the reason rides the QUERY STRING (DELETE bodies are not reliably
    // parsed across this stack).
    it('sends the operator reason on the query string when one is given', async () => {
      await openDrawer();
      mockApi.delete.mockResolvedValue({ data: mutationAck() });
      mockApi.get.mockResolvedValue({ data: emptyPayload() });

      await wrapper.find('[data-testid="drawer-purge-button"]').trigger('click');
      expect(dialogReason(wrapper).exists()).toBe(true);
      await dialogReason(wrapper).setValue('  GDPR erasure request #123  ');
      await dialogInput(wrapper).setValue(EMAIL);
      await wrapper.find('form').trigger('submit');
      await flushPromises();

      expect(mockApi.delete).toHaveBeenCalledWith(`/api/colonel/users/${PUBLIC_ID}`, {
        params: { reason: 'GDPR erasure request #123' },
      });
    });

    // The OPTIONAL half: no reason must leave the request BYTE-IDENTICAL to the
    // pre-#4338 one — not `reason=''`, not even an empty axios config — so the
    // audit detail keeps its old shape. (The "DELETEs, toasts…" case above
    // asserts the same single-argument call.)
    it('adds nothing to the request when the reason is left blank', async () => {
      await openDrawer();
      mockApi.delete.mockResolvedValue({ data: mutationAck() });
      mockApi.get.mockResolvedValue({ data: emptyPayload() });

      await wrapper.find('[data-testid="drawer-purge-button"]').trigger('click');
      await dialogReason(wrapper).setValue('   ');
      await dialogInput(wrapper).setValue(EMAIL);
      await wrapper.find('form').trigger('submit');
      await flushPromises();

      expect(mockApi.delete).toHaveBeenCalledWith(`/api/colonel/users/${PUBLIC_ID}`);
    });

    // Reversible bookkeeping asks for no explanation — only the destructive
    // verb on this screen does.
    it('does NOT show the reason field for verify/unverify', async () => {
      await openDrawer();
      await wrapper.find('[data-testid="drawer-verify-button"]').trigger('click');
      await flushPromises();
      expect(dialogReason(wrapper).exists()).toBe(false);
    });

    it('does NOT delete when submitted without a matching token', async () => {
      await openDrawer();
      mockApi.delete.mockResolvedValue({ data: mutationAck() });

      await wrapper.find('[data-testid="drawer-purge-button"]').trigger('click');
      await dialogInput(wrapper).setValue('wrong');
      await wrapper.find('form').trigger('submit');
      await flushPromises();

      expect(mockApi.delete).not.toHaveBeenCalled();
      expect(drawer(wrapper).exists()).toBe(true);
    });

    it('surfaces the backend error in the dialog and keeps the row', async () => {
      await openDrawer();
      mockApi.delete.mockRejectedValue(axiosError(422, { error: 'Cannot purge yourself' }));

      await wrapper.find('[data-testid="drawer-purge-button"]').trigger('click');
      await dialogInput(wrapper).setValue(EMAIL);
      await wrapper.find('form').trigger('submit');
      await flushPromises();

      expect(wrapper.find('[data-testid="admin-confirm-dialog"]').text()).toContain(
        'Cannot purge yourself'
      );
      expect(showMock).not.toHaveBeenCalled();
      expect(drawer(wrapper).exists()).toBe(true);
      expect(useAdminCustomers().customers).toHaveLength(1);
    });
  });
});

describe('useAdminCustomers — operator mutations', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
  });

  async function seeded(overrides: { verified?: boolean } = {}) {
    mockApi.get.mockResolvedValue({ data: usersPayload(overrides) });
    const store = useAdminCustomers();
    await store.fetchPage(1);
    return store;
  }

  it('setVerification posts the matching verb and returns the patched row', async () => {
    const store = await seeded({ verified: false });
    mockApi.post.mockResolvedValue({ data: mutationAck() });

    const updated = await store.setVerification(PUBLIC_ID, true);

    expect(mockApi.post).toHaveBeenCalledWith(`/api/colonel/users/${PUBLIC_ID}/verify`, {});
    expect(updated?.verified).toBe(true);
    expect(store.customers[0].verified).toBe(true);
  });

  it('setVerification leaves the row untouched when the request fails', async () => {
    const store = await seeded({ verified: false });
    mockApi.post.mockRejectedValue(axiosError(500, {}));

    await expect(store.setVerification(PUBLIC_ID, true)).rejects.toBeTruthy();
    expect(store.customers[0].verified).toBe(false);
  });

  it('purge drops the row only after a 2xx', async () => {
    const store = await seeded();
    mockApi.delete.mockResolvedValue({ data: mutationAck() });

    await store.purge(PUBLIC_ID);

    expect(mockApi.delete).toHaveBeenCalledWith(`/api/colonel/users/${PUBLIC_ID}`);
    expect(store.customers).toHaveLength(0);
  });

  it('purge keeps the row when the request fails', async () => {
    const store = await seeded();
    mockApi.delete.mockRejectedValue(axiosError(422, { error: 'nope' }));

    await expect(store.purge(PUBLIC_ID)).rejects.toBeTruthy();
    expect(store.customers).toHaveLength(1);
  });

  it('encodes the id in the mutation paths', async () => {
    const store = await seeded();
    mockApi.delete.mockResolvedValue({ data: mutationAck() });

    await store.purge('ur alice/../colonel');

    expect(mockApi.delete).toHaveBeenCalledWith(
      '/api/colonel/users/ur%20alice%2F..%2Fcolonel'
    );
  });
});
