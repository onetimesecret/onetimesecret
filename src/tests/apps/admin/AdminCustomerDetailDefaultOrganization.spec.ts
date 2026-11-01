// src/tests/apps/admin/AdminCustomerDetailDefaultOrganization.spec.ts

import { flushPromises, mount, VueWrapper } from '@vue/test-utils';
import { AxiosError } from 'axios';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

/**
 * Customer detail: change the customer's DEFAULT organization.
 *
 *   POST /api/colonel/users/:user_id/default-organization
 *   body { organization_id: <org extid>, reason? }, X-OTS-Confirm: <account token>
 *
 * TIER 2: a simple confirm with an optional reason, the account confirmation
 * header, and NO step-up prompt. Only organizations in the customer's own list
 * are offered (the server refuses any other), the current default is marked
 * and offers no control, and a success refetches the record.
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
// `isNavigationFailure` is reached by the shared error classifier on every
// failed mutation, so the mock must carry it for the refusal path.
vi.mock('vue-router', () => ({
  useRouter: () => ({ push: pushMock }),
  useRoute: () => ({ params: { id: 'ur_alice' } }),
  isNavigationFailure: () => false,
  NavigationFailureType: {},
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

import {
  __resetColonelElevationState,
  useColonelElevation,
} from '@/apps/admin/composables/useColonelElevation';
import AdminCustomerDetail from '@/apps/admin/views/AdminCustomerDetail.vue';
import { createTestI18n } from '@tests/setup';

const i18n = createTestI18n();

const PUBLIC_ID = 'ur_alice';
const EMAIL = 'alice@example.com';
const USER_URL = `/api/colonel/users/${PUBLIC_ID}`;
const DEFAULT_ORG_URL = `${USER_URL}/default-organization`;
const CONFIRM_HEADERS = { headers: { 'X-OTS-Confirm': encodeURIComponent(EMAIL) } };

function detailPayload() {
  return {
    shrimp: '',
    record: {
      extid: PUBLIC_ID,
      email: EMAIL,
      role: 'customer',
      verified: true,
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
      secrets: { count: 0, truncated: false, items: [] },
      receipts: { count: 0, truncated: false, items: [] },
      organizations: [
        {
          organization_id: 'o1',
          extid: 'og_own',
          display_name: 'Own',
          is_default: true,
          is_customer_default: true,
        },
        {
          organization_id: 'o2',
          extid: 'og_team',
          display_name: 'Team',
          is_default: false,
          is_customer_default: false,
        },
      ],
      stats: { secrets_created: 0, secrets_shared: 0, emails_sent: 0 },
    },
  };
}

function defaultOrgAck() {
  return {
    shrimp: '',
    record: {
      extid: PUBLIC_ID,
      default_organization: { extid: 'og_team', display_name: 'Team' },
    },
    details: {
      previous_default_organization: { extid: 'og_own', display_name: 'Own' },
    },
  };
}

const mountView = () =>
  mount(AdminCustomerDetail, {
    props: { id: PUBLIC_ID },
    global: {
      plugins: [i18n],
      // Self-contained children with their own specs and endpoints.
      stubs: { AdminCustomerSessionsSection: true, AdminAccountDiagnosticsSection: true },
    },
  });

const dialog = (w: VueWrapper) => w.find('[data-testid="admin-confirm-dialog"]');
const dialogSubmit = (w: VueWrapper) => w.find('[data-testid="admin-confirm-submit"]');
const reasonInput = (w: VueWrapper) => w.find('[data-testid="admin-confirm-reason"]');
const row = (w: VueWrapper, extid: string) => w.find(`[data-testid="organization-row-${extid}"]`);
const makeDefault = (w: VueWrapper, extid: string) =>
  w.find(`[data-testid="organization-make-default-${extid}"]`);
/** GETs of the customer record itself (mount + any refetch). */
const recordGets = () => mockApi.get.mock.calls.filter(([url]) => url === USER_URL).length;

describe('AdminCustomerDetail — change default organization', () => {
  let wrapper: VueWrapper;

  beforeEach(() => {
    vi.clearAllMocks();
    __resetColonelElevationState();
  });
  afterEach(() => wrapper?.unmount());

  async function mountLoaded(): Promise<void> {
    mockApi.get.mockResolvedValue({ data: detailPayload() });
    wrapper = mountView();
    await flushPromises();
  }

  it('marks the current default and offers the control only on the other rows', async () => {
    await mountLoaded();

    expect(row(wrapper, 'og_own').find('[data-testid="organization-default-badge"]').exists()).toBe(
      true
    );
    expect(makeDefault(wrapper, 'og_own').exists()).toBe(false);

    expect(
      row(wrapper, 'og_team').find('[data-testid="organization-default-badge"]').exists()
    ).toBe(false);
    expect(makeDefault(wrapper, 'og_team').exists()).toBe(true);
  });

  it('confirms, POSTs the org extid with the account header, notifies and refetches', async () => {
    await mountLoaded();
    mockApi.post.mockResolvedValue({ data: defaultOrgAck() });

    await makeDefault(wrapper, 'og_team').trigger('click');
    await flushPromises();

    // TIER 2: a simple confirm (no typed token), and no step-up prompt.
    expect(dialog(wrapper).exists()).toBe(true);
    expect(wrapper.find('#admin-confirm-input').exists()).toBe(false);
    expect(useColonelElevation().promptOpen.value).toBe(false);

    await reasonInput(wrapper).setValue('support ticket 77');
    await dialogSubmit(wrapper).trigger('submit');
    await flushPromises();

    expect(mockApi.post).toHaveBeenCalledWith(
      DEFAULT_ORG_URL,
      { organization_id: 'og_team', reason: 'support ticket 77' },
      CONFIRM_HEADERS
    );
    expect(showMock).toHaveBeenCalledWith(
      'web.admin.customers.defaultOrganization.success',
      'success'
    );
    expect(dialog(wrapper).exists()).toBe(false);
    // Mount, then the refetch that redraws the badge from live state.
    expect(recordGets()).toBe(2);
  });

  it('omits the reason key when none is given', async () => {
    await mountLoaded();
    mockApi.post.mockResolvedValue({ data: defaultOrgAck() });

    await makeDefault(wrapper, 'og_team').trigger('click');
    await flushPromises();
    await dialogSubmit(wrapper).trigger('submit');
    await flushPromises();

    expect(mockApi.post).toHaveBeenCalledWith(
      DEFAULT_ORG_URL,
      { organization_id: 'og_team' },
      CONFIRM_HEADERS
    );
  });

  it('keeps a server refusal in the dialog: no notice, no refetch', async () => {
    await mountLoaded();
    mockApi.post.mockRejectedValue(
      axiosError(422, { error: 'Customer is not an active member of that organization' })
    );

    await makeDefault(wrapper, 'og_team').trigger('click');
    await flushPromises();
    await dialogSubmit(wrapper).trigger('submit');
    await flushPromises();

    expect(dialog(wrapper).text()).toContain(
      'Customer is not an active member of that organization'
    );
    expect(showMock).not.toHaveBeenCalled();
    expect(recordGets()).toBe(1);
  });

  it('sends nothing when the confirm is cancelled', async () => {
    await mountLoaded();

    await makeDefault(wrapper, 'og_team').trigger('click');
    await flushPromises();
    await wrapper.find('[data-testid="admin-confirm-cancel"]').trigger('click');
    await flushPromises();

    expect(dialog(wrapper).exists()).toBe(false);
    expect(mockApi.post).not.toHaveBeenCalled();
  });
});
