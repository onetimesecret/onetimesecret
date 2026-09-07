// src/tests/apps/admin/AdminOrganizationAddMember.spec.ts

import { flushPromises, mount, VueWrapper } from '@vue/test-utils';
import { createPinia, setActivePinia } from 'pinia';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

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

const pushMock = vi.fn();
// `isNavigationFailure` is reached by the shared error classifier on every
// failed mutation — the mock must provide it or the classifier throws.
vi.mock('vue-router', () => ({
  useRouter: () => ({ push: pushMock }),
  isNavigationFailure: () => false,
  NavigationFailureType: { aborted: 4, cancelled: 8, duplicated: 16 },
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

// CopyButton (used by RevealEmail) touches navigator.clipboard; stub it.
vi.mock('@/shared/components/ui/CopyButton.vue', () => ({
  default: {
    name: 'CopyButton',
    template: '<button class="copy-button" />',
    props: ['text', 'tooltip', 'testid'],
  },
}));

// Render the headlessui modal synchronously and IN-PLACE (the real Dialog
// teleports its panel to <body>, escaping the mounted wrapper).
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

import AdminOrganizationDetail from '@/apps/admin/views/AdminOrganizationDetail.vue';
import { createTestI18n } from '@tests/setup';

const i18n = createTestI18n();

const ORG_EXTID = 'on_abc123';
const ORG_URL = `/api/colonel/organizations/${ORG_EXTID}`;
const MEMBERS_URL = `${ORG_URL}/members`;
const USERS_URL = '/api/colonel/users';

/** Existing owner already on the roster. */
const OWNER_EXTID = 'ur_owner1';
/** The account the operator is trying to add. */
const CANDIDATE_EXTID = 'ur_cand99';

function detailPayload() {
  return {
    shrimp: '',
    record: {
      org_id: 'org1',
      extid: ORG_EXTID,
      display_name: 'Acme',
      description: 'Acme workspace',
      is_default: false,
      archived: false,
      archived_at: null,
      archived_comment: null,
      contact_email: 'owner@acme.test',
      owner_id: 'cust1',
      owner_email: 'owner@acme.test',
      billing_email: null,
      member_count: 1,
      domain_count: 0,
      created: 1700000000,
      updated: null,
      planid: 'identity_plus_v1',
      stripe_customer_id: null,
      stripe_subscription_id: null,
      subscription_status: null,
      subscription_period_end: null,
      billing_email_present: false,
      sync_status: 'synced',
      sync_status_reason: null,
    },
    details: {
      entitlements: {
        plan: ['create_secrets'],
        grants: [],
        revokes: [],
        materialized: ['create_secrets'],
        expected: ['create_secrets'],
        materialized_flag: true,
        materialized_at: 1700000000,
        plan_stale: false,
        drift: { extra: [], missing: [], in_sync: true },
      },
      members: [
        {
          extid: OWNER_EXTID,
          email: 'owner@acme.test',
          role: 'owner',
          status: 'active',
          is_owner: true,
          joined_at: 1700000000,
          created: 1700000000,
        },
      ],
      domains: [],
    },
  };
}

function usersPayload(users: Array<Record<string, unknown>>) {
  return {
    shrimp: '',
    record: {},
    details: {
      users,
      pagination: { page: 1, per_page: 25, total_count: users.length, total_pages: 1 },
    },
  };
}

function userRow(overrides: Record<string, unknown> = {}) {
  return {
    user_id: CANDIDATE_EXTID,
    extid: CANDIDATE_EXTID,
    email: 'newperson@acme.test',
    role: 'customer',
    verified: true,
    suspended: false,
    created: 1700000000,
    last_login: 1700003600,
    planid: 'identity_plus_v1',
    secrets_count: 0,
    secrets_created: 0,
    secrets_shared: 0,
    ...overrides,
  };
}

function userDetailPayload(organizations: Array<Record<string, unknown>> = []) {
  return {
    shrimp: '',
    record: {
      extid: CANDIDATE_EXTID,
      email: 'newperson@acme.test',
      role: 'customer',
      verified: true,
      suspended: false,
      created: 1700000000,
      updated: null,
      last_login: 1700003600,
      planid: 'identity_plus_v1',
      locale: 'en',
    },
    details: {
      secrets: { count: 0, items: [] },
      receipts: { count: 0, items: [] },
      organizations,
      billing: {
        enabled: false,
        plan_id: null,
        organization: null,
        stripe: {
          available: false,
          reason: 'billing disabled',
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

function addAck(status: 'success' | 'no_change', role = 'member') {
  return {
    shrimp: '',
    record: { org_id: ORG_EXTID, member_id: CANDIDATE_EXTID, status, role },
  };
}

/** Build an error whose shape matches what the classifier probes (`response`). */
function httpError(status: number, data: unknown): Error & { response: unknown } {
  const err = new Error('Request failed') as Error & { response: unknown };
  err.response = { status, data, statusText: '', headers: {}, config: {} };
  return err;
}

/**
 * Route GETs by url so the org detail and the account lookups can be mocked
 * independently (the view issues both against the same axios stub).
 */
function routeGets(
  options: {
    users?: unknown;
    userDetail?: unknown;
    usersRejects?: Error;
  } = {}
) {
  mockApi.get.mockImplementation((url: string) => {
    if (url === ORG_URL) return Promise.resolve({ data: detailPayload() });
    if (url === USERS_URL) {
      if (options.usersRejects) return Promise.reject(options.usersRejects);
      return Promise.resolve({ data: options.users ?? usersPayload([userRow()]) });
    }
    if (url === `${USERS_URL}/${CANDIDATE_EXTID}`) {
      return Promise.resolve({ data: options.userDetail ?? userDetailPayload() });
    }
    return Promise.reject(new Error(`unexpected GET ${url}`));
  });
}

describe('AdminOrganizationDetail — add an existing account to the organization', () => {
  let wrapper: VueWrapper;
  let pinia: ReturnType<typeof createPinia>;

  beforeEach(() => {
    pinia = createPinia();
    setActivePinia(pinia);
    vi.clearAllMocks();
    vi.useFakeTimers({ shouldAdvanceTime: true });
  });
  afterEach(() => {
    vi.useRealTimers();
    wrapper?.unmount();
  });

  const mountView = () =>
    mount(AdminOrganizationDetail, {
      props: { id: ORG_EXTID },
      global: { plugins: [pinia, i18n] },
    });

  /** Open the modal, search for `term`, and let the debounce + request settle. */
  async function search(w: VueWrapper, term: string): Promise<void> {
    await w.find('[data-testid="org-add-member-button"]').trigger('click');
    await w.find('[data-testid="add-member-search"]').setValue(term);
    vi.advanceTimersByTime(300);
    await flushPromises();
  }

  it('searches existing accounts by email through the customers search endpoint', async () => {
    routeGets();
    wrapper = mountView();
    await flushPromises();

    // The modal is inert until opened: only the mount-time GETs have fired
    // (org detail + the available-plans catalog for the plan selector).
    expect(mockApi.get).toHaveBeenCalledTimes(2);

    await search(wrapper, 'newperson@acme.test');

    expect(mockApi.get).toHaveBeenCalledWith(USERS_URL, {
      params: { page: 1, per_page: 25, search: 'newperson@acme.test' },
    });

    const results = wrapper.find('[data-testid="add-member-results"]');
    expect(results.exists()).toBe(true);
    // Address is obscured by default (RevealEmail), extid shown as key material.
    expect(results.text()).not.toContain('newperson@acme.test');
    expect(results.text()).toContain('n•••@a•••.test');
    expect(results.text()).toContain(CANDIDATE_EXTID);
  });

  it('debounces the search so it issues one request per pause, not per keystroke', async () => {
    routeGets();
    wrapper = mountView();
    await flushPromises();

    await wrapper.find('[data-testid="org-add-member-button"]').trigger('click');
    const input = wrapper.find('[data-testid="add-member-search"]');
    await input.setValue('new');
    await input.setValue('newper');
    await input.setValue('newperson@acme.test');
    vi.advanceTimersByTime(300);
    await flushPromises();

    const userSearches = mockApi.get.mock.calls.filter(([url]) => url === USERS_URL);
    expect(userSearches).toHaveLength(1);
  });

  it('shows an explicit not-found state when no account matches', async () => {
    routeGets({ users: usersPayload([]) });
    wrapper = mountView();
    await flushPromises();

    await search(wrapper, 'ghost@acme.test');

    expect(wrapper.find('[data-testid="add-member-no-results"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="add-member-results"]').exists()).toBe(false);
    // Submit stays disabled with nothing selected.
    expect(wrapper.find('[data-testid="add-member-submit"]').attributes('disabled')).toBeDefined();
  });

  it('pins the selected account with identifying detail and its current organizations', async () => {
    routeGets({
      userDetail: userDetailPayload([
        { organization_id: 'org9', extid: 'on_other', display_name: 'Other Co', is_default: true },
      ]),
    });
    wrapper = mountView();
    await flushPromises();

    await search(wrapper, 'newperson@acme.test');
    await wrapper.find(`[data-testid="add-member-select-${CANDIDATE_EXTID}"]`).trigger('click');
    await flushPromises();

    // The account detail GET is what exposes current memberships.
    expect(mockApi.get).toHaveBeenCalledWith(`${USERS_URL}/${CANDIDATE_EXTID}`, undefined);

    const panel = wrapper.find('[data-testid="add-member-selected"]');
    expect(panel.exists()).toBe(true);
    expect(panel.text()).toContain(CANDIDATE_EXTID);
    expect(wrapper.find('[data-testid="add-member-field-created"]').text()).toContain('DT:');
    expect(wrapper.find('[data-testid="add-member-organizations"]').text()).toContain('Other Co');
    // Not already in THIS org, so the add is allowed.
    expect(wrapper.find('[data-testid="add-member-already-member"]').exists()).toBe(false);
    expect(
      wrapper.find('[data-testid="add-member-submit"]').attributes('disabled')
    ).toBeUndefined();
  });

  it('posts the extid plus the chosen role, toasts, closes, and refreshes the roster', async () => {
    routeGets();
    mockApi.post.mockResolvedValue({ data: addAck('success', 'admin') });
    wrapper = mountView();
    await flushPromises();

    await search(wrapper, 'newperson@acme.test');
    await wrapper.find(`[data-testid="add-member-select-${CANDIDATE_EXTID}"]`).trigger('click');
    await flushPromises();

    await wrapper.find('[data-testid="add-member-role"]').setValue('admin');
    await wrapper.find('[data-testid="add-member-submit"]').trigger('click');
    await flushPromises();

    // Never an email address: the colonel adapter resolves the public id.
    expect(mockApi.post).toHaveBeenCalledWith(MEMBERS_URL, {
      customer: CANDIDATE_EXTID,
      role: 'admin',
    });
    expect(showMock).toHaveBeenCalledTimes(1);
    expect(showMock.mock.calls[0][0]).toBe('web.admin.organizations.addMember.success');
    expect(showMock.mock.calls[0][1]).toBe('success');

    // Modal closed and the roster re-read from the server (2 org detail GETs).
    expect(wrapper.find('[data-testid="add-member-selected"]').exists()).toBe(false);
    const orgGets = mockApi.get.mock.calls.filter(([url]) => url === ORG_URL);
    expect(orgGets).toHaveLength(2);
  });

  it('offers only the roles the backend accepts', async () => {
    routeGets();
    wrapper = mountView();
    await flushPromises();

    await search(wrapper, 'newperson@acme.test');
    await wrapper.find(`[data-testid="add-member-select-${CANDIDATE_EXTID}"]`).trigger('click');
    await flushPromises();

    const values = wrapper
      .find('[data-testid="add-member-role"]')
      .findAll('option')
      .map((option) => option.attributes('value'));
    expect(values).toEqual(['member', 'admin', 'owner']);
  });

  it('blocks the add and explains when the account is already on the roster', async () => {
    routeGets({ users: usersPayload([userRow({ extid: OWNER_EXTID, user_id: OWNER_EXTID })]) });
    mockApi.get.mockImplementation((url: string) => {
      if (url === ORG_URL) return Promise.resolve({ data: detailPayload() });
      if (url === USERS_URL) {
        return Promise.resolve({
          data: usersPayload([userRow({ extid: OWNER_EXTID, user_id: OWNER_EXTID })]),
        });
      }
      return Promise.resolve({ data: userDetailPayload() });
    });
    wrapper = mountView();
    await flushPromises();

    await search(wrapper, 'owner@acme.test');

    // Flagged in the result list before the operator even picks.
    expect(wrapper.find(`[data-testid="add-member-existing-${OWNER_EXTID}"]`).exists()).toBe(true);

    await wrapper.find(`[data-testid="add-member-select-${OWNER_EXTID}"]`).trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-testid="add-member-already-member"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="add-member-submit"]').attributes('disabled')).toBeDefined();
    expect(mockApi.post).not.toHaveBeenCalled();
  });

  it('treats an idempotent no_change 200 as a failure, not a false success', async () => {
    routeGets();
    mockApi.post.mockResolvedValue({ data: addAck('no_change', 'admin') });
    wrapper = mountView();
    await flushPromises();

    await search(wrapper, 'newperson@acme.test');
    await wrapper.find(`[data-testid="add-member-select-${CANDIDATE_EXTID}"]`).trigger('click');
    await flushPromises();

    await wrapper.find('[data-testid="add-member-submit"]').trigger('click');
    await flushPromises();

    // No toast, modal stays open, message names the already-member case.
    expect(showMock).not.toHaveBeenCalled();
    expect(wrapper.find('[data-testid="add-member-selected"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="add-member-error"]').text()).toContain(
      'web.admin.organizations.addMember.errors.alreadyMember'
    );
    // The roster was NOT refreshed — nothing changed server-side.
    const orgGets = mockApi.get.mock.calls.filter(([url]) => url === ORG_URL);
    expect(orgGets).toHaveLength(1);
  });

  it('keeps a 404 inside the modal with the backend message', async () => {
    routeGets();
    mockApi.post.mockRejectedValue(httpError(404, { error: 'Customer not found' }));
    wrapper = mountView();
    await flushPromises();

    await search(wrapper, 'newperson@acme.test');
    await wrapper.find(`[data-testid="add-member-select-${CANDIDATE_EXTID}"]`).trigger('click');
    await flushPromises();

    await wrapper.find('[data-testid="add-member-submit"]').trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-testid="add-member-error"]').text()).toContain('Customer not found');
    expect(showMock).not.toHaveBeenCalled();
    expect(wrapper.find('[data-testid="add-member-selected"]').exists()).toBe(true);
  });

  it('falls back to a localized message when a 404 carries no backend error text', async () => {
    routeGets();
    mockApi.post.mockRejectedValue(httpError(404, {}));
    wrapper = mountView();
    await flushPromises();

    await search(wrapper, 'newperson@acme.test');
    await wrapper.find(`[data-testid="add-member-select-${CANDIDATE_EXTID}"]`).trigger('click');
    await flushPromises();

    await wrapper.find('[data-testid="add-member-submit"]').trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-testid="add-member-error"]').text()).toContain(
      'web.admin.organizations.addMember.errors.notFound'
    );
  });

  it('surfaces a rejected role from the form error the backend returns', async () => {
    routeGets();
    mockApi.post.mockRejectedValue(
      httpError(422, { error: "Invalid role 'auditor'. Must be one of: owner, admin, member" })
    );
    wrapper = mountView();
    await flushPromises();

    await search(wrapper, 'newperson@acme.test');
    await wrapper.find(`[data-testid="add-member-select-${CANDIDATE_EXTID}"]`).trigger('click');
    await flushPromises();

    await wrapper.find('[data-testid="add-member-submit"]').trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-testid="add-member-error"]').text()).toContain(
      'Must be one of: owner, admin, member'
    );
  });

  it('degrades to the roster guard when the account lookup fails', async () => {
    mockApi.get.mockImplementation((url: string) => {
      if (url === ORG_URL) return Promise.resolve({ data: detailPayload() });
      if (url === USERS_URL) return Promise.resolve({ data: usersPayload([userRow()]) });
      return Promise.reject(httpError(500, {}));
    });
    mockApi.post.mockResolvedValue({ data: addAck('success') });
    wrapper = mountView();
    await flushPromises();

    await search(wrapper, 'newperson@acme.test');
    await wrapper.find(`[data-testid="add-member-select-${CANDIDATE_EXTID}"]`).trigger('click');
    await flushPromises();

    // The memberships read-out says so, but the add is still allowed.
    expect(wrapper.find('[data-testid="add-member-organizations-error"]').exists()).toBe(true);
    expect(
      wrapper.find('[data-testid="add-member-submit"]').attributes('disabled')
    ).toBeUndefined();

    await wrapper.find('[data-testid="add-member-submit"]').trigger('click');
    await flushPromises();
    expect(mockApi.post).toHaveBeenCalledWith(MEMBERS_URL, {
      customer: CANDIDATE_EXTID,
      role: 'member',
    });
  });

  it('renders a retryable banner when the account search itself fails', async () => {
    routeGets({ usersRejects: httpError(500, {}) });
    wrapper = mountView();
    await flushPromises();

    await search(wrapper, 'newperson@acme.test');

    expect(wrapper.find('[data-testid="add-member-search-error"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="add-member-results"]').exists()).toBe(false);
  });
});
