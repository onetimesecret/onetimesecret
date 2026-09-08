// src/tests/apps/admin/AdminCustomers.spec.ts

import { createPinia, setActivePinia } from 'pinia';
import { flushPromises, mount, RouterLinkStub, VueWrapper } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

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

// Render the DetailDrawer's HeadlessUI dialog synchronously and IN-PLACE. The
// real Dialog teleports its panel to <body>, escaping the mounted wrapper, so
// `wrapper.find('[data-testid="customers-drawer"]')` would never see it. Mirrors
// AdminOrganizations.spec / AdminSessions.spec.
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

// jsdom has no ResizeObserver; headlessui's Dialog observes the panel when the
// detail drawer opens. Stub it so the drawer test drives the real open path.
class ResizeObserverStub {
  observe(): void {}
  unobserve(): void {}
  disconnect(): void {}
}
globalThis.ResizeObserver = ResizeObserverStub as unknown as typeof ResizeObserver;

import AdminCustomers from '@/apps/admin/views/AdminCustomers.vue';
import { FilterBar } from '@/apps/admin/components/kit';
import { createTestI18n } from '@tests/setup';

const i18n = createTestI18n();

function usersPayload(
  overrides: {
    page?: number;
    per_page?: number;
    role?: string | null;
    suspended?: boolean;
    capped?: boolean;
    /**
     * Orphaned auth-database rows for the searched address. `undefined` (the
     * default) OMITS the field, mirroring a server that predates it.
     */
    orphaned_accounts?: Array<Record<string, unknown>>;
  } = {}
) {
  return {
    shrimp: '',
    record: {},
    details: {
      ...(overrides.orphaned_accounts ? { orphaned_accounts: overrides.orphaned_accounts } : {}),
      users: [
        {
          user_id: 'ur_alice',
          extid: 'ur_alice',
          email: 'alice@example.com',
          role: 'customer',
          verified: true,
          suspended: overrides.suspended ?? false,
          created: 1700000000,
          last_login: 1700000100,
          planid: 'basic',
          secrets_count: 3,
          secrets_created: 5,
          secrets_shared: 2,
        },
      ],
      pagination: {
        page: overrides.page ?? 1,
        per_page: overrides.per_page ?? 50,
        total_count: 1,
        total_pages: 1,
        // The endpoint always emits the flag (false on the unbounded paths) —
        // see Colonel::ListUsers#success_data — so the fixture does too.
        capped: overrides.capped ?? false,
        role_filter: overrides.role ?? null,
      },
    },
  };
}

describe('AdminCustomers (list view — ticket #22)', () => {
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
      global: {
        plugins: [pinia, i18n],
        // The drawer's "Open full page" link is a router-link; the admin router
        // isn't mounted here, so use the slot-rendering official stub.
        stubs: { RouterLink: RouterLinkStub },
      },
    });

  it('fetches the first page on mount and renders a row per customer', async () => {
    mockApi.get.mockResolvedValue({ data: usersPayload() });
    wrapper = mountView();
    await flushPromises();

    expect(mockApi.get).toHaveBeenCalledWith('/api/colonel/users', {
      params: { page: 1, per_page: 50 },
    });
    const table = wrapper.find('[data-testid="customers-table"]');
    expect(table.exists()).toBe(true);
    // Emails are obscured by default (RevealEmail); the full address is not
    // rendered until the operator toggles reveal.
    expect(table.text()).not.toContain('alice@example.com');
    expect(table.text()).toContain('a•••@e•••.com');
    // Non-sortable columns: header buttons should NOT be rendered (fixed order).
    expect(table.findAll('thead th button')).toHaveLength(0);
  });

  it('forwards the role filter to the server on filter-change', async () => {
    mockApi.get.mockResolvedValue({ data: usersPayload() });
    wrapper = mountView();
    await flushPromises();

    await wrapper.find('#kit-filter-role').setValue('admin');
    await flushPromises();

    expect(mockApi.get).toHaveBeenLastCalledWith('/api/colonel/users', {
      params: { page: 1, per_page: 50, role: 'admin' },
    });
  });

  it('never fetches on typing alone — search is submit-only', async () => {
    mockApi.get.mockResolvedValue({ data: usersPayload() });
    wrapper = mountView();
    await flushPromises();
    const before = mockApi.get.mock.calls.length;

    const input = wrapper.find('[data-testid="customers-filterbar"] input[type="search"]');
    await input.setValue('a');
    await input.setValue('al');
    await input.setValue('alice');
    // Give any (incorrectly) scheduled timer a chance to fire.
    await new Promise((resolve) => setTimeout(resolve, 350));
    await flushPromises();

    expect(mockApi.get.mock.calls.length).toBe(before);
  });

  it('fetches once with the term when the search button is clicked', async () => {
    mockApi.get.mockResolvedValue({ data: usersPayload() });
    wrapper = mountView();
    await flushPromises();

    await wrapper
      .find('[data-testid="customers-filterbar"] input[type="search"]')
      .setValue('alice');
    const before = mockApi.get.mock.calls.length;

    const submitBtn = wrapper
      .findAll('[data-testid="customers-filterbar"] button')
      .find((b) => b.text().includes('searchSubmit'));
    await submitBtn!.trigger('click');
    await flushPromises();

    expect(mockApi.get.mock.calls.length).toBe(before + 1);
    expect(mockApi.get).toHaveBeenLastCalledWith('/api/colonel/users', {
      params: { page: 1, per_page: 50, search: 'alice' },
    });
  });

  it('drops a submit while a request is still in flight (no burst)', async () => {
    let release!: (value: { data: unknown }) => void;
    mockApi.get.mockResolvedValueOnce({ data: usersPayload() });
    wrapper = mountView();
    await flushPromises();

    mockApi.get.mockImplementationOnce(() => new Promise((resolve) => (release = resolve)));
    const input = wrapper.find('[data-testid="customers-filterbar"] input[type="search"]');
    await input.setValue('alice');
    await input.trigger('keydown', { key: 'Enter' });
    const before = mockApi.get.mock.calls.length;

    // Hammer Enter and the button while the first search is pending.
    await input.setValue('alice2');
    await input.trigger('keydown', { key: 'Enter' });
    await input.trigger('keydown', { key: 'Enter' });
    const submitBtn = wrapper
      .findAll('[data-testid="customers-filterbar"] button')
      .find((b) => b.text().includes('searchSubmit'));
    expect(submitBtn!.attributes('disabled')).toBeDefined();
    await submitBtn!.trigger('click');
    await flushPromises();
    expect(mockApi.get.mock.calls.length).toBe(before);

    release({ data: usersPayload() });
    await flushPromises();
    expect(submitBtn!.attributes('disabled')).toBeUndefined();
  });

  it('issues exactly one fetch when clearing filters', async () => {
    mockApi.get.mockResolvedValue({ data: usersPayload() });
    wrapper = mountView();
    await flushPromises();

    // Establish an active search so the clear affordance has something to reset.
    const input = wrapper.find('[data-testid="customers-filterbar"] input[type="search"]');
    await input.setValue('alice');
    await input.trigger('keydown', { key: 'Enter' });
    await flushPromises();

    const before = mockApi.get.mock.calls.length;

    // Clear the filter bar (emits the 'clear' event AdminCustomers handles).
    wrapper.findComponent(FilterBar).vm.$emit('clear');
    await new Promise((resolve) => setTimeout(resolve, 350));
    await flushPromises();

    // Exactly one fetch — the fetchPage(1) from onClear(). The programmatic
    // searchTerm reset must NOT trigger a second request.
    expect(mockApi.get.mock.calls.length).toBe(before + 1);
    expect(mockApi.get).toHaveBeenLastCalledWith('/api/colonel/users', {
      params: { page: 1, per_page: 50 },
    });
  });

  it('shows a SUSPENDED badge on suspended rows only', async () => {
    mockApi.get.mockResolvedValue({ data: usersPayload({ suspended: true }) });
    wrapper = mountView();
    await flushPromises();
    expect(wrapper.find('[data-testid="suspended-badge"]').exists()).toBe(true);

    wrapper.unmount();
    setActivePinia((pinia = createPinia()));
    mockApi.get.mockResolvedValue({ data: usersPayload() });
    wrapper = mountView();
    await flushPromises();
    expect(wrapper.find('[data-testid="suspended-badge"]').exists()).toBe(false);
  });

  it('shows a Rodauth Admin link in the drawer only when the server built one', async () => {
    const withLink = usersPayload() as unknown as {
      details: { users: Record<string, unknown>[] };
    };
    withLink.details.users[0].rodauth_admin_account_url =
      'http://127.0.0.1:9292/account?q=ur_alice';
    mockApi.get.mockResolvedValue({ data: withLink });
    wrapper = mountView();
    await flushPromises();
    await wrapper.find('[data-testid="customers-table"] tbody tr').trigger('click');
    await flushPromises();

    const link = wrapper.find('[data-testid="customer-rodauth-admin-link"]');
    expect(link.exists()).toBe(true);
    expect(link.attributes('href')).toBe('http://127.0.0.1:9292/account?q=ur_alice');
    expect(link.attributes('target')).toBe('_blank');
    wrapper.unmount();

    // Null (unset URL or simple mode) or absent (older backend): plain drawer.
    mockApi.get.mockResolvedValue({ data: usersPayload() });
    wrapper = mountView();
    await flushPromises();
    await wrapper.find('[data-testid="customers-table"] tbody tr').trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-testid="customer-rodauth-admin-link"]').exists()).toBe(false);
  });

  it('opens the detail drawer on row click, with a full-page escalation link', async () => {
    mockApi.get.mockResolvedValue({ data: usersPayload() });
    wrapper = mountView();
    await flushPromises();

    // Drawer-first (like organizations / sessions): no navigation, no drawer
    // until a row is clicked.
    expect(wrapper.find('[data-testid="customers-drawer"]').exists()).toBe(false);

    await wrapper.find('[data-testid="customers-table"] tbody tr').trigger('click');
    await flushPromises();

    const drawer = wrapper.find('[data-testid="customers-drawer"]');
    expect(drawer.exists()).toBe(true);
    expect(drawer.text()).toContain('alice@example.com');
    expect(drawer.text()).toContain('ur_alice');
    expect(pushMock).not.toHaveBeenCalled();

    // The deep, mutating actions stay one click away on the full page (by public id).
    const fullPage = wrapper
      .findAllComponents(RouterLinkStub)
      .find((link) => link.attributes('data-testid') === 'customer-open-full-page');
    expect(fullPage).toBeDefined();
    expect(fullPage!.props('to')).toEqual({
      name: 'AdminCustomerDetail',
      params: { id: 'ur_alice' },
    });
  });

  // --- Row-scoped affordances inside a CLICKABLE row ------------------------
  // The row's @click opens the drawer, so anything interactive rendered inside
  // a cell must contain its own click. Both of these were operator-reported.

  it('reveals an email without also opening the drawer', async () => {
    mockApi.get.mockResolvedValue({ data: usersPayload() });
    wrapper = mountView();
    await flushPromises();

    const row = wrapper.find('[data-testid="customers-table"] tbody tr');
    // Obscured by default.
    expect(row.find('[data-testid="reveal-email-value"]').text()).not.toBe('alice@example.com');

    await row.find('[data-testid="reveal-email-toggle"]').trigger('click');
    await flushPromises();

    // Revealed...
    expect(row.find('[data-testid="reveal-email-value"]').text()).toBe('alice@example.com');
    // ...and the row handler never fired.
    expect(wrapper.find('[data-testid="customers-drawer"]').exists()).toBe(false);

    // The copy affordance that appears on reveal is contained too.
    Object.assign(navigator, { clipboard: { writeText: vi.fn().mockResolvedValue(undefined) } });
    await row.find('[data-testid="reveal-email-copy"]').trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-testid="customers-drawer"]').exists()).toBe(false);
  });

  it('links each row straight to the full page without opening the drawer', async () => {
    mockApi.get.mockResolvedValue({ data: usersPayload() });
    wrapper = mountView();
    await flushPromises();

    const rowLink = wrapper
      .findAllComponents(RouterLinkStub)
      .find((link) => link.attributes('data-testid') === 'customer-detail-ur_alice');

    // A REAL router-link — middle-click / open-in-new-tab must work, so this
    // must never become a JS click handler.
    expect(rowLink).toBeDefined();
    expect(rowLink!.props('to')).toEqual({
      name: 'AdminCustomerDetail',
      params: { id: 'ur_alice' },
    });
    // Icon-only control, so it carries its own accessible name.
    expect(rowLink!.attributes('aria-label')).toBeTruthy();

    // Activating it must not also open the drawer behind it.
    await rowLink!.trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-testid="customers-drawer"]').exists()).toBe(false);
  });

  it('renders the pagination control when the server returns pagination', async () => {
    mockApi.get.mockResolvedValue({ data: usersPayload() });
    wrapper = mountView();
    await flushPromises();

    // KitPagination shows the range summary string.
    expect(wrapper.text()).toContain('web.colonel.pagination.showing');
  });

  it('renders the capped caveat when the server marks the scan as capped', async () => {
    mockApi.get.mockResolvedValue({ data: usersPayload({ capped: true }) });
    wrapper = mountView();
    await flushPromises();

    const caveat = wrapper.find('[data-testid="customers-capped-caveat"]');
    expect(caveat.exists()).toBe(true);
    expect(caveat.attributes('role')).toBe('status');
    expect(caveat.text()).toContain('web.admin.customers.list.capped');
  });

  it('does not render the capped caveat on an uncapped response', async () => {
    mockApi.get.mockResolvedValue({ data: usersPayload({ capped: false }) });
    wrapper = mountView();
    await flushPromises();

    expect(wrapper.find('[data-testid="customers-capped-caveat"]').exists()).toBe(false);
  });

  it('renders one orphaned-account row per entry when the auth database has an unmapped account', async () => {
    mockApi.get.mockResolvedValue({
      data: usersPayload({
        orphaned_accounts: [
          {
            email: 'Bob@Example.com',
            account_id: 42,
            external_id: null,
            status: 'verified',
            created_at: 1700000000,
          },
          {
            email: 'bob@example.com',
            account_id: 43,
            external_id: 'ur_bob',
            status: 'closed',
            created_at: null,
          },
        ],
      }),
    });
    wrapper = mountView();
    await flushPromises();

    const notice = wrapper.find('[data-testid="customers-orphaned-accounts"]');
    expect(notice.exists()).toBe(true);
    expect(notice.attributes('role')).toBe('status');
    expect(notice.text()).toContain('web.admin.customers.list.orphanedAccounts.title');

    const rows = notice.findAll('[data-testid="customers-orphaned-account"]');
    expect(rows).toHaveLength(2);
    // Nothing is obscured here: the operator typed this address to find it.
    expect(rows[0].text()).toContain('Bob@Example.com');
    // The status pill falls back to the raw value when the key is unknown (the
    // role cell's idiom), so under the key-echoing test i18n it reads as the value.
    expect(rows[0].find('[data-testid="customers-orphaned-account-status"]').text()).toBe(
      'verified'
    );
    expect(rows[1].find('[data-testid="customers-orphaned-account-status"]').text()).toBe('closed');
    expect(rows[0].text()).toContain('web.admin.customers.list.orphanedAccounts.accountId');

    // Each address links to the account diagnostics for that identifier: the
    // detail route, keyed by the EMAIL (the orphan has no extid to route by).
    const links = notice.findAllComponents(RouterLinkStub);
    expect(links).toHaveLength(2);
    expect(links[0].props('to')).toEqual({
      name: 'AdminCustomerDetail',
      params: { id: 'Bob@Example.com' },
    });
    expect(links[1].props('to')).toEqual({
      name: 'AdminCustomerDetail',
      params: { id: 'bob@example.com' },
    });
  });

  it('does not render the orphaned-accounts notice when the array is empty', async () => {
    mockApi.get.mockResolvedValue({ data: usersPayload({ orphaned_accounts: [] }) });
    wrapper = mountView();
    await flushPromises();

    expect(wrapper.find('[data-testid="customers-orphaned-accounts"]').exists()).toBe(false);
  });

  it('does not render the orphaned-accounts notice when the server omits the field', async () => {
    // Older servers never emit `orphaned_accounts`; the schema defaults it to []
    // so the page must still parse and render the table.
    mockApi.get.mockResolvedValue({ data: usersPayload() });
    wrapper = mountView();
    await flushPromises();

    expect(wrapper.find('[data-testid="customers-orphaned-accounts"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="customers-table"]').exists()).toBe(true);
  });

  it('shows the error banner + retry on a network failure', async () => {
    mockApi.get.mockRejectedValue(new Error('Network Error'));
    wrapper = mountView();
    await flushPromises();

    const banner = wrapper.find('[data-testid="customers-error"]');
    expect(banner.exists()).toBe(true);

    // Retry re-issues the request.
    mockApi.get.mockResolvedValueOnce({ data: usersPayload() });
    await banner.find('button').trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-testid="customers-error"]').exists()).toBe(false);
  });
});
