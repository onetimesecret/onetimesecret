// src/tests/apps/admin/AdminCustomerDetailSetRole.spec.ts

import { AxiosError } from 'axios';
import { flushPromises, mount, VueWrapper } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

/**
 * Detail-page ROLE CHANGE gate (#4326).
 *
 * `setRole` was a plain one-click confirm: promoting an account to colonel —
 * the most privilege-granting action the console offers — took two clicks and
 * no typing. It is now a DANGER action, gated client-side on retyping the
 * account email and server-side on the same token in X-OTS-Confirm.
 *
 * Split out of AdminCustomerDetail.spec.ts per the convention this tree already
 * follows for AdminCustomerDetailPurge.spec.ts: that file owns the happy path,
 * this one owns the gate.
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
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
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

type BootstrapCust = ReturnType<typeof useBootstrapStore>['cust'];

/**
 * Who the console thinks is logged in. Only `extid` is read by the #4328
 * self-target guards, so the rest of the customer shape is irrelevant here.
 */
function actAs(extid: string | null): void {
  const bootstrap = useBootstrapStore();
  bootstrap.cust = extid ? ({ extid } as unknown as NonNullable<BootstrapCust>) : null;
}

describe('AdminCustomerDetail — role change gate (#4326)', () => {
  let wrapper: VueWrapper;

  beforeEach(() => vi.clearAllMocks());
  afterEach(() => wrapper?.unmount());

  async function mountLoaded(record: Record<string, unknown> = {}): Promise<void> {
    const payload = detailPayload();
    Object.assign(payload.record, record);
    mockApi.get.mockResolvedValue({ data: payload });
    wrapper = mountView();
    await flushPromises();
  }

  /** Pick a new role and open the confirm dialog. */
  async function requestRole(role: string): Promise<void> {
    await wrapper.find('[data-testid="role-select"]').setValue(role);
    await wrapper.find('[data-testid="role-apply"]').trigger('click');
    await flushPromises();
  }

  it('renders a typed-confirmation input, not a one-click confirm', async () => {
    await mountLoaded();
    await requestRole('colonel');

    expect(dialogInput(wrapper).exists()).toBe(true);
    expect(dialogSubmit(wrapper).attributes('disabled')).toBeDefined();
  });

  it('unlocks only on the EXACT account email — the public id does not', async () => {
    await mountLoaded();
    await requestRole('colonel');

    await dialogInput(wrapper).setValue(PUBLIC_ID);
    expect(dialogSubmit(wrapper).attributes('disabled')).toBeDefined();

    await dialogInput(wrapper).setValue(EMAIL.toUpperCase());
    expect(dialogSubmit(wrapper).attributes('disabled')).toBeDefined();

    await dialogInput(wrapper).setValue(EMAIL);
    expect(dialogSubmit(wrapper).attributes('disabled')).toBeUndefined();
  });

  it('POSTs the role with the token in X-OTS-Confirm, and keeps it out of the URL', async () => {
    await mountLoaded();
    mockApi.post.mockResolvedValue({ data: mutationAck() });

    await requestRole('colonel');
    await dialogInput(wrapper).setValue(EMAIL);
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(mockApi.post).toHaveBeenCalledWith(
      `/api/colonel/users/${PUBLIC_ID}/role`,
      { role: 'colonel' },
      { headers: { 'X-OTS-Confirm': encodeURIComponent(EMAIL) } }
    );
    const [url] = mockApi.post.mock.calls[0];
    expect(url).not.toContain(encodeURIComponent(EMAIL));
    expect(showMock).toHaveBeenCalledWith('web.admin.customers.actions.role.success', 'success');
  });

  it('does NOT post when the token does not match', async () => {
    await mountLoaded();
    mockApi.post.mockResolvedValue({ data: mutationAck() });

    await requestRole('colonel');
    await dialogInput(wrapper).setValue('not-the-email');
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(mockApi.post).not.toHaveBeenCalled();
  });

  // FAIL CLOSED: AdminConfirmDialog treats a blank token as simple-confirm
  // mode, so an account with no email must not open the dialog at all rather
  // than silently degrading a privilege grant to one click.
  it('refuses to open the dialog for an account with no email or public id', async () => {
    await mountLoaded({ email: '', extid: '' });

    await requestRole('colonel');

    expect(dialogInput(wrapper).exists()).toBe(false);
    expect(mockApi.post).not.toHaveBeenCalled();
  });

  // The dialog stays shut for a no-op, so the operator never confirms nothing.
  it('ignores an apply that would not change the role', async () => {
    await mountLoaded({ role: 'customer' });

    await wrapper.find('[data-testid="role-apply"]').trigger('click');
    await flushPromises();

    expect(dialogInput(wrapper).exists()).toBe(false);
  });

  it('surfaces a server refusal in the dialog and stays put', async () => {
    await mountLoaded();
    mockApi.post.mockRejectedValue(
      axiosError(403, {
        error: 'Confirmation required: re-send this request with the X-OTS-Confirm header set to the target account\'s email address.',
        error_type: 'ConfirmationRequired',
        error_code: 'confirmation_required',
      })
    );

    await requestRole('colonel');
    await dialogInput(wrapper).setValue(EMAIL);
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(wrapper.find('[data-testid="admin-confirm-dialog"]').text()).toContain(
      'Confirmation required'
    );
    expect(showMock).not.toHaveBeenCalled();
  });

  // ---- Self-target interlocks (#4328) ---------------------------------------
  //
  // The server refuses these with a 422 whatever the browser does; blocking
  // here is defence in depth (the `purgeBlocked` pattern), so the operator is
  // never asked to retype a token for an action that cannot succeed.
  describe('your own account', () => {
    afterEach(() => actAs(null));

    it('disables the role apply button for a self-DEMOTION and states why', async () => {
      actAs(PUBLIC_ID);
      await mountLoaded({ role: 'colonel' });
      await wrapper.find('[data-testid="role-select"]').setValue('customer');
      await flushPromises();

      expect(wrapper.find('[data-testid="role-apply"]').attributes('disabled')).toBeDefined();
      expect(wrapper.find('[data-testid="self-demote-reason"]').text()).toBe(
        'web.admin.customers.actions.role.selfDemote'
      );
    });

    it('opens no dialog and POSTs nothing for a self-demotion', async () => {
      actAs(PUBLIC_ID);
      await mountLoaded({ role: 'colonel' });
      await requestRole('customer');

      expect(dialogInput(wrapper).exists()).toBe(false);
      expect(mockApi.post).not.toHaveBeenCalled();
    });

    it('still allows RAISING your own role (only demotion is a lockout risk)', async () => {
      actAs(PUBLIC_ID);
      await mountLoaded({ role: 'admin' });
      await wrapper.find('[data-testid="role-select"]').setValue('colonel');
      await flushPromises();

      expect(wrapper.find('[data-testid="role-apply"]').attributes('disabled')).toBeUndefined();
      expect(wrapper.find('[data-testid="self-demote-reason"]').exists()).toBe(false);
    });

    it('disables unverify on your own account and states why', async () => {
      actAs(PUBLIC_ID);
      await mountLoaded({ role: 'colonel', verified: true });

      expect(wrapper.find('[data-testid="unverify-button"]').attributes('disabled')).toBeDefined();
      expect(wrapper.find('[data-testid="self-unverify-reason"]').text()).toBe(
        'web.admin.customers.actions.unverify.selfUnverify'
      );
      await wrapper.find('[data-testid="unverify-button"]').trigger('click');
      await flushPromises();
      expect(dialogInput(wrapper).exists()).toBe(false);
    });

    it('leaves SOMEONE ELSE\'S account fully actionable, with a last-colonel warning', async () => {
      actAs('ur_someone_else');
      await mountLoaded({ role: 'colonel', verified: true });
      await wrapper.find('[data-testid="role-select"]').setValue('customer');
      await flushPromises();

      expect(wrapper.find('[data-testid="role-apply"]').attributes('disabled')).toBeUndefined();
      expect(wrapper.find('[data-testid="unverify-button"]').attributes('disabled')).toBeUndefined();
      // Advisory, not a gate: the console cannot know the roster (exposing it
      // would be the oracle #4328 closes), so it warns rather than blocks.
      expect(wrapper.find('[data-testid="last-colonel-warning"]').text()).toBe(
        'web.admin.customers.actions.role.lastColonel'
      );
      expect(wrapper.find('[data-testid="unverify-last-colonel-warning"]').text()).toBe(
        'web.admin.customers.actions.unverify.lastColonel'
      );
    });
  });
});
