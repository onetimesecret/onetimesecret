// src/tests/apps/admin/AdminCustomerDetailImpersonate.spec.ts

import { AxiosError } from 'axios';
import { flushPromises, mount, VueWrapper } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

/**
 * The impersonate action on the customer detail page.
 *
 * Three things are load-bearing and pinned here: the reason is REQUIRED (it is
 * what the audit entry carries), the eligibility gate matches the operation's
 * own guards (colonel / anonymous / suspended), and success leaves the SPA by
 * HARD navigation — `router.push` would resolve against the admin route table
 * and land on a console path that 403s while a marker is active.
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

const hardNavigateMock = vi.fn();
vi.mock('@/utils/navigation', () => ({
  hardNavigate: (...args: unknown[]) => hardNavigateMock(...args),
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
import { createTestI18n } from '@tests/setup';

const i18n = createTestI18n();

const PUBLIC_ID = 'ur_alice';
const EMAIL = 'alice@example.com';
const REASON = 'Ticket #4321: cannot see their own secret';

interface RecordOverrides {
  role?: string;
  suspended?: boolean;
  email?: string;
  extid?: string;
}

function detailPayload(overrides: RecordOverrides = {}) {
  return {
    shrimp: '',
    record: {
      extid: overrides.extid ?? PUBLIC_ID,
      email: overrides.email ?? EMAIL,
      role: overrides.role ?? 'customer',
      verified: true,
      suspended: overrides.suspended ?? false,
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

/** The impersonate ack: the new marker plus where the console must go. */
function impersonateAck(redirect: unknown = '/') {
  return {
    shrimp: '',
    record: {
      impersonation_id: 'imp_abc123',
      target_extid: PUBLIC_ID,
      target_email: EMAIL,
      expires_at: 1756701800,
      redirect,
    },
    details: {},
  };
}

const mountView = () =>
  mount(AdminCustomerDetail, {
    props: { id: PUBLIC_ID },
    global: { plugins: [i18n], stubs: { AdminCustomerSessionsSection: true } },
  });

const reasonInput = (w: VueWrapper) => w.find('[data-testid="impersonate-reason"]');
const impersonateButton = (w: VueWrapper) => w.find('[data-testid="impersonate-button"]');
const blockedReason = (w: VueWrapper) => w.find('[data-testid="impersonate-blocked-reason"]');
const dialogInput = (w: VueWrapper) => w.find('#admin-confirm-input');
const dialogSubmit = (w: VueWrapper) => w.find('[data-testid="admin-confirm-submit"]');

describe('AdminCustomerDetail — impersonate', () => {
  let wrapper: VueWrapper;

  beforeEach(() => vi.clearAllMocks());
  afterEach(() => wrapper?.unmount());

  async function mountLoaded(overrides: RecordOverrides = {}): Promise<void> {
    mockApi.get.mockResolvedValue({ data: detailPayload(overrides) });
    wrapper = mountView();
    await flushPromises();
  }

  /** Fill the reason, open the confirm, and retype the public-id token. */
  async function confirmImpersonate(reason = REASON): Promise<void> {
    await reasonInput(wrapper).setValue(reason);
    await impersonateButton(wrapper).trigger('click');
    await flushPromises();
    await dialogInput(wrapper).setValue(PUBLIC_ID);
    await wrapper.find('form').trigger('submit');
    await flushPromises();
  }

  describe('required reason', () => {
    it('disables the button until a reason is typed', async () => {
      await mountLoaded();

      expect(impersonateButton(wrapper).attributes('disabled')).toBeDefined();

      await reasonInput(wrapper).setValue(REASON);
      expect(impersonateButton(wrapper).attributes('disabled')).toBeUndefined();

      // Whitespace is not a reason.
      await reasonInput(wrapper).setValue('   ');
      expect(impersonateButton(wrapper).attributes('disabled')).toBeDefined();
    });

    it('marks the input required and caps it at the API limit', async () => {
      await mountLoaded();
      expect(reasonInput(wrapper).attributes('required')).toBeDefined();
      expect(reasonInput(wrapper).attributes('aria-required')).toBe('true');
      expect(reasonInput(wrapper).attributes('maxlength')).toBe('500');
    });

    it('does not open the dialog with a blank reason', async () => {
      await mountLoaded();

      await impersonateButton(wrapper).trigger('click');
      await flushPromises();

      expect(wrapper.find('[data-testid="admin-confirm-dialog"]').exists()).toBe(false);
      expect(mockApi.post).not.toHaveBeenCalled();
    });
  });

  describe('eligibility gate (mirrors the operation guards)', () => {
    it.each([
      ['colonel target', { role: 'colonel' } as RecordOverrides],
      ['suspended target', { suspended: true } as RecordOverrides],
      ['anonymous target', { extid: 'anon', email: 'anon' } as RecordOverrides],
      ['record with no email', { email: '' } as RecordOverrides],
    ])('disables impersonation for a %s and states why', async (_label, overrides) => {
      await mountLoaded(overrides);

      expect(impersonateButton(wrapper).attributes('disabled')).toBeDefined();
      expect(reasonInput(wrapper).attributes('disabled')).toBeDefined();
      expect(blockedReason(wrapper).exists()).toBe(true);
      // The reason is written as t(key, defaultMessage) — the purge precedent —
      // so the pass-through test i18n renders the DEFAULT, not the key.
      expect(blockedReason(wrapper).text()).toContain('Impersonation is unavailable');
      // The disabled button is explained to assistive tech, not just greyed out.
      expect(impersonateButton(wrapper).attributes('aria-describedby')).toBe(
        'impersonate-blocked-reason'
      );
    });

    it('offers impersonation for an ordinary active customer', async () => {
      await mountLoaded();
      expect(blockedReason(wrapper).exists()).toBe(false);
      expect(reasonInput(wrapper).attributes('disabled')).toBeUndefined();
    });
  });

  describe('typed confirmation', () => {
    it('gates confirm behind the public id and never POSTs before it matches', async () => {
      await mountLoaded();
      await reasonInput(wrapper).setValue(REASON);

      await impersonateButton(wrapper).trigger('click');
      await flushPromises();

      expect(dialogInput(wrapper).exists()).toBe(true);
      expect(dialogSubmit(wrapper).attributes('disabled')).toBeDefined();

      await dialogInput(wrapper).setValue(EMAIL);
      expect(dialogSubmit(wrapper).attributes('disabled')).toBeDefined();

      await dialogInput(wrapper).setValue(PUBLIC_ID);
      expect(dialogSubmit(wrapper).attributes('disabled')).toBeUndefined();
      expect(mockApi.post).not.toHaveBeenCalled();
    });
  });

  describe('on confirm', () => {
    it('POSTs the trimmed reason, toasts, and HARD-navigates to the ack redirect', async () => {
      await mountLoaded();
      mockApi.post.mockResolvedValue({ data: impersonateAck('/') });

      await confirmImpersonate(`  ${REASON}  `);

      expect(mockApi.post).toHaveBeenCalledWith(`/api/colonel/users/${PUBLIC_ID}/impersonate`, {
        reason: REASON,
      });
      expect(showMock).toHaveBeenCalledWith(
        'web.admin.customers.actions.impersonate.success',
        'success'
      );
      // Hard navigation, NOT an in-SPA push: the console 403s once the marker
      // is live and the identity in the document is now the target's.
      expect(hardNavigateMock).toHaveBeenCalledWith('/', '/');
      expect(pushMock).not.toHaveBeenCalled();
    });

    it('falls back to the app root when the ack is unreadable (2xx still started it)', async () => {
      await mountLoaded();
      mockApi.post.mockResolvedValue({ data: { shrimp: '', record: { nonsense: true } } });

      await confirmImpersonate();

      // The marker exists server-side, so we still leave — hardNavigate's own
      // fallback decides the destination.
      expect(hardNavigateMock).toHaveBeenCalledWith(null, '/');
    });

    it('keeps a rejected impersonation in the dialog: no navigation, no toast', async () => {
      await mountLoaded();
      mockApi.post.mockRejectedValue(
        axiosError(422, { error: 'Cannot impersonate a privileged account' })
      );

      await confirmImpersonate();

      expect(wrapper.find('[data-testid="admin-confirm-dialog"]').text()).toContain(
        'Cannot impersonate a privileged account'
      );
      expect(hardNavigateMock).not.toHaveBeenCalled();
      expect(showMock).not.toHaveBeenCalled();
    });
  });

  it('leaves the other guarded actions untouched (suspend still uses its own reason)', async () => {
    await mountLoaded();
    await reasonInput(wrapper).setValue(REASON);
    mockApi.post.mockResolvedValue({
      shrimp: '',
      data: { shrimp: '', record: { user_id: 'objid', extid: PUBLIC_ID }, details: {} },
    });

    await wrapper.find('[data-testid="suspend-button"]').trigger('click');
    await dialogInput(wrapper).setValue(PUBLIC_ID);
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(mockApi.post).toHaveBeenCalledWith(`/api/colonel/users/${PUBLIC_ID}/suspend`, {});
    expect(hardNavigateMock).not.toHaveBeenCalled();
  });
});
