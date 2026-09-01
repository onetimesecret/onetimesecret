// src/tests/apps/admin/AdminCustomerDetailPurge.spec.ts

import { AxiosError } from 'axios';
import { flushPromises, mount, VueWrapper } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

/**
 * Detail-page purge gate: the typed-confirmation token is the account's EMAIL.
 *
 * Split out of AdminCustomerDetail.spec.ts (which still asserts the previous
 * public-id token in its `purge — typed-confirmation gate` block; those three
 * assertions need the email instead). Suspend is covered here too, as the
 * regression guard that ONLY purge moved to the email token.
 */

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
import {
  __resetColonelElevationState,
  useColonelElevation,
} from '@/apps/admin/composables/useColonelElevation';
import { createTestI18n } from '@tests/setup';

const i18n = createTestI18n();

const PUBLIC_ID = 'ur_alice';
const EMAIL = 'alice@example.com';

function detailPayload(overrides: { verified?: boolean } = {}) {
  return {
    shrimp: '',
    record: {
      extid: PUBLIC_ID,
      email: EMAIL,
      role: 'customer',
      verified: overrides.verified ?? false,
      suspended: false,
      suspended_at: null,
      suspended_by: null,
      suspended_reason: null,
      created: 1700000000,
      updated: 1700000100,
      last_login: 1700000200,
      planid: 'basic',
      locale: 'en',
    },
    details: {
      secrets: { count: 0, items: [] },
      receipts: { count: 0, items: [] },
      organizations: [],
      billing: {
        enabled: false,
        plan_id: 'basic',
        organization: null,
        stripe: {
          available: false,
          reason: 'Billing is not configured',
          customer_id: null,
          dashboard_url: null,
          subscription: null,
          latest_invoice: null,
        },
      },
      stats: { secrets_created: 0, secrets_shared: 0, emails_sent: 0 },
    },
  };
}

function mutationAck() {
  return { shrimp: '', record: { user_id: 'objid', extid: PUBLIC_ID }, details: { message: 'ok' } };
}

const mountView = () =>
  mount(AdminCustomerDetail, {
    props: { id: PUBLIC_ID },
    global: { plugins: [i18n], stubs: { AdminCustomerSessionsSection: true } },
  });

const dialogInput = (w: VueWrapper) => w.find('#admin-confirm-input');
const dialogSubmit = (w: VueWrapper) => w.find('[data-testid="admin-confirm-submit"]');

describe('AdminCustomerDetail — purge gate (typed email) + verification state', () => {
  let wrapper: VueWrapper;

  beforeEach(() => {
    vi.clearAllMocks();
    // The step-up window is module-level singleton state (#4327); reset it so
    // one example's elevation cannot satisfy the next one's gate.
    __resetColonelElevationState();
  });
  afterEach(() => wrapper?.unmount());

  async function mountLoaded(overrides: { verified?: boolean } = {}): Promise<void> {
    mockApi.get.mockResolvedValue({ data: detailPayload(overrides) });
    wrapper = mountView();
    await flushPromises();
  }

  it('gates purge behind the EXACT email — the public id does not unlock it', async () => {
    await mountLoaded();

    await wrapper.find('[data-testid="purge-button"]').trigger('click');
    await flushPromises();

    expect(dialogInput(wrapper).exists()).toBe(true);
    expect(dialogSubmit(wrapper).attributes('disabled')).toBeDefined();

    await dialogInput(wrapper).setValue(PUBLIC_ID);
    expect(dialogSubmit(wrapper).attributes('disabled')).toBeDefined();

    await dialogInput(wrapper).setValue(EMAIL.toUpperCase());
    expect(dialogSubmit(wrapper).attributes('disabled')).toBeDefined();

    await dialogInput(wrapper).setValue(EMAIL);
    expect(dialogSubmit(wrapper).attributes('disabled')).toBeUndefined();
  });

  it('DELETEs, toasts and routes back to the list on confirm', async () => {
    await mountLoaded();
    mockApi.delete.mockResolvedValue({ data: mutationAck() });

    await wrapper.find('[data-testid="purge-button"]').trigger('click');
    await dialogInput(wrapper).setValue(EMAIL);
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    // The typed email is also what the server is gated on (#4326) — sent as a
    // HEADER, so the address never enters the URL, a log, or browser history.
    expect(mockApi.delete).toHaveBeenCalledWith(`/api/colonel/users/${PUBLIC_ID}`, {
      headers: { 'X-OTS-Confirm': encodeURIComponent(EMAIL) },
    });
    expect(showMock).toHaveBeenCalledWith('web.admin.customers.actions.purge.success', 'success');
    expect(pushMock).toHaveBeenCalledWith({ name: 'AdminCustomers' });
  });

  it('keeps a failed purge in the dialog: no navigation, no toast', async () => {
    await mountLoaded();
    mockApi.delete.mockRejectedValue(axiosError(422, { error: 'Cannot purge anonymous user' }));

    await wrapper.find('[data-testid="purge-button"]').trigger('click');
    await dialogInput(wrapper).setValue(EMAIL);
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(wrapper.find('[data-testid="admin-confirm-dialog"]').text()).toContain(
      'Cannot purge anonymous user'
    );
    expect(pushMock).not.toHaveBeenCalled();
    expect(showMock).not.toHaveBeenCalled();
  });

  // #4326 moved SUSPEND onto the same email token: the server gates all four
  // danger verbs on the account identifier, and a dialog that asked for the
  // public id while sending the email would be two gates disagreeing.
  it('puts SUSPEND on the email token too, not the public id', async () => {
    await mountLoaded();
    mockApi.post.mockResolvedValue({ data: mutationAck() });

    await wrapper.find('[data-testid="suspend-button"]').trigger('click');
    await flushPromises();

    await dialogInput(wrapper).setValue(PUBLIC_ID);
    expect(dialogSubmit(wrapper).attributes('disabled')).toBeDefined();

    await dialogInput(wrapper).setValue(EMAIL);
    expect(dialogSubmit(wrapper).attributes('disabled')).toBeUndefined();

    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(mockApi.post).toHaveBeenCalledWith(
      `/api/colonel/users/${PUBLIC_ID}/suspend`,
      {},
      { headers: { 'X-OTS-Confirm': encodeURIComponent(EMAIL) } }
    );
  });

  it('states the verification badge both ways and offers only the matching verb', async () => {
    await mountLoaded({ verified: false });
    expect(wrapper.find('[data-testid="unverified-badge"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="verified-badge"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="verify-button"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="unverify-button"]').exists()).toBe(false);

    wrapper.unmount();

    await mountLoaded({ verified: true });
    expect(wrapper.find('[data-testid="verified-badge"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="unverified-badge"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="unverify-button"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="verify-button"]').exists()).toBe(false);
  });

  it('refreshes the record after verify instead of navigating away', async () => {
    await mountLoaded({ verified: false });
    mockApi.post.mockResolvedValue({ data: mutationAck() });
    // The refreshed read reports the new state — the badge must follow it.
    mockApi.get.mockResolvedValue({ data: detailPayload({ verified: true }) });

    await wrapper.find('[data-testid="verify-button"]').trigger('click');
    await flushPromises();
    // Reversible action: one-click confirm, no typed gate.
    expect(dialogInput(wrapper).exists()).toBe(false);

    await wrapper.find('form').trigger('submit');
    await flushPromises();

    // Verify is the restorative arm: un-gated, so no confirmation header.
    expect(mockApi.post).toHaveBeenCalledWith(
      `/api/colonel/users/${PUBLIC_ID}/verify`,
      {},
      undefined
    );
    expect(pushMock).not.toHaveBeenCalled();
    expect(wrapper.find('[data-testid="verified-badge"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="unverify-button"]').exists()).toBe(true);
  });

  // ---- Step-up (sudo) window (#4327) ---------------------------------------
  //
  // The loop is: attempt -> 403 elevation_required -> prompt -> the operator
  // acts -> retry ONCE. The retry must never fire without that gesture; an
  // automatic elevate-and-retry would put a colonel session alone back in
  // charge of a destructive verb, which is what this issue exists to stop.
  describe('a 403 elevation_required opens the sudo prompt', () => {
    async function submitPurge(): Promise<void> {
      await wrapper.find('[data-testid="purge-button"]').trigger('click');
      await dialogInput(wrapper).setValue(EMAIL);
      await wrapper.find('form').trigger('submit');
      await flushPromises();
    }

    it('opens the prompt and does NOT retry until the operator acts', async () => {
      await mountLoaded();
      mockApi.delete.mockRejectedValue(
        axiosError(403, { error: 'Step-up authentication required', error_code: 'elevation_required' })
      );

      await submitPurge();

      const elevation = useColonelElevation();
      expect(elevation.promptOpen.value).toBe(true);
      // One attempt so far. The retry is still waiting on the operator.
      expect(mockApi.delete).toHaveBeenCalledTimes(1);
      expect(pushMock).not.toHaveBeenCalled();

      // The operator elevates; the prompt resolves and the verb is retried once.
      mockApi.delete.mockResolvedValue({ data: mutationAck() });
      elevation.resolvePrompt(true);
      await flushPromises();

      expect(mockApi.delete).toHaveBeenCalledTimes(2);
      expect(showMock).toHaveBeenCalledWith('web.admin.customers.actions.purge.success', 'success');
    });

    it('surfaces the original error and retries nothing when the operator cancels', async () => {
      await mountLoaded();
      mockApi.delete.mockRejectedValue(
        axiosError(403, { error: 'Step-up authentication required', error_code: 'elevation_required' })
      );

      await submitPurge();

      const elevation = useColonelElevation();
      elevation.resolvePrompt(false);
      await flushPromises();

      expect(mockApi.delete).toHaveBeenCalledTimes(1);
      expect(wrapper.find('[data-testid="admin-confirm-dialog"]').text()).toContain(
        'Step-up authentication required'
      );
      expect(pushMock).not.toHaveBeenCalled();
      expect(showMock).not.toHaveBeenCalled();
    });

    it('leaves a confirmation_required failure alone — no sudo prompt for that', async () => {
      await mountLoaded();
      mockApi.delete.mockRejectedValue(
        axiosError(403, { error: 'Confirmation required', error_code: 'confirmation_required' })
      );

      await submitPurge();

      expect(useColonelElevation().promptOpen.value).toBe(false);
      expect(mockApi.delete).toHaveBeenCalledTimes(1);
    });
  });
});
