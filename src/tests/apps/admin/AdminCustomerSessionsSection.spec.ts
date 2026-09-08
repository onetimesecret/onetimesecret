// src/tests/apps/admin/AdminCustomerSessionsSection.spec.ts

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

import AdminCustomerSessionsSection from '@/apps/admin/components/AdminCustomerSessionsSection.vue';
import SessionAuthorityNotice from '@/apps/admin/components/SessionAuthorityNotice.vue';
import {
  colonelCustomerSessionsResponseSchema,
  type AdminCustomerSession,
} from '@/schemas/api/internal/responses/colonel-customer-sessions';
import { createTestI18n } from '@tests/setup';

const i18n = createTestI18n();

const USER_ID = 'ur_abc123';

/**
 * #4326 made `confirmToken` a REQUIRED prop (the account email, extid fallback):
 * the detail view is the only surface holding the record, so the section is
 * handed the token rather than deriving one. Every mount here needs it or
 * `type-check:tests` fails — Vue only warns at runtime, so vitest alone does
 * not catch a missing required prop.
 */
const CONFIRM_TOKEN = 'colonel-target@example.com';

/** Pass-through i18n (ADR-014): keys render verbatim, so assert on the key. */
const COUNTRY_HEADER = 'web.admin.customers.detail.sessions.columns.country';
const UNKNOWN = 'web.admin.customers.detail.sessions.unknown';

function sessionRow(overrides: Partial<AdminCustomerSession> = {}): AdminCustomerSession {
  return {
    session_handle: 'a15e5510000000000000000000000001',
    user_id: USER_ID,
    org_id: null,
    created_at: 1700000000,
    last_activity_at: 1700003600,
    ip_address: '203.0.113.7',
    user_agent: 'Mozilla/5.0',
    auth_method: 'password',
    mfa_used: null,
    geo_country: 'DE',
    ...overrides,
  };
}

/**
 * A row from a backend that predates the geo join: the key is ABSENT, not null.
 * `{ geo_country: undefined }` would not exercise the same thing — the property
 * would still exist — so it is deleted outright. `geo_country` is declared
 * `.optional()` on the schema (see adminCustomerSessionSchema), so deleting it
 * still yields a valid AdminCustomerSession — no cast needed.
 */
function sessionRowWithoutCountry(
  overrides: Partial<AdminCustomerSession> = {}
): AdminCustomerSession {
  const row = sessionRow(overrides);
  delete row.geo_country;
  return row;
}

function sessionsPayload(
  rows: AdminCustomerSession[] = [
    sessionRow(),
    sessionRow({ session_handle: 'a15e5510000000000000000000000002' }),
  ],
  currentSessionHandle: string | null = null
) {
  return {
    shrimp: '',
    record: {},
    details: { sessions: rows, count: rows.length, current_session_handle: currentSessionHandle },
  };
}

const mountSection = (extraProps: Record<string, unknown> = {}) =>
  mount(AdminCustomerSessionsSection, {
    props: { userId: USER_ID, confirmToken: CONFIRM_TOKEN, ...extraProps },
    global: {
      plugins: [i18n],
      // The confirm dialogs (HeadlessUI) have their own spec; the badge/revoke
      // rendering under test lives in the table's actions cell.
      stubs: { AdminConfirmDialog: true },
    },
  });

const badge = (w: VueWrapper, sid: string) => w.find(`[data-testid="session-current-${sid}"]`);
const revoke = (w: VueWrapper, sid: string) => w.find(`[data-testid="session-revoke-${sid}"]`);

/**
 * Text of the country cell for one body row. DataTable emits cells positionally
 * (one `<td>` per column, same order), so the column is located by its header
 * rather than a hard-coded index — the assertion survives a column reshuffle.
 */
function countryCell(w: VueWrapper, rowIndex: number): string {
  const table = w.find('[data-testid="sessions-section-table"]');
  const columnIndex = table.findAll('thead th').findIndex((th) => th.text() === COUNTRY_HEADER);
  expect(columnIndex).toBeGreaterThanOrEqual(0);
  return table.findAll('tbody tr')[rowIndex].findAll('td')[columnIndex].text();
}

describe('AdminCustomerSessionsSection — current-session badge', () => {
  let wrapper: VueWrapper;

  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
  });

  afterEach(() => wrapper?.unmount());

  it('badges the matching row and withholds its revoke button', async () => {
    mockApi.get.mockResolvedValue({
      data: sessionsPayload(undefined, 'a15e5510000000000000000000000001'),
    });
    wrapper = mountSection();
    await flushPromises();

    // The colonel's own row: badge in, per-row revoke out (v-if/v-else).
    expect(badge(wrapper, 'a15e5510000000000000000000000001').exists()).toBe(true);
    expect(revoke(wrapper, 'a15e5510000000000000000000000001').exists()).toBe(false);
    expect(badge(wrapper, 'a15e5510000000000000000000000001').text()).toContain(
      'web.admin.customers.detail.sessions.current.badge'
    );
    expect(badge(wrapper, 'a15e5510000000000000000000000001').attributes('title')).toBe(
      'web.admin.customers.detail.sessions.current.tooltip'
    );
  });

  it('renders the revoke button (and no badge) on non-matching rows', async () => {
    mockApi.get.mockResolvedValue({
      data: sessionsPayload(undefined, 'a15e5510000000000000000000000001'),
    });
    wrapper = mountSection();
    await flushPromises();

    expect(revoke(wrapper, 'a15e5510000000000000000000000002').exists()).toBe(true);
    expect(badge(wrapper, 'a15e5510000000000000000000000002').exists()).toBe(false);
  });

  it('shows no badge and all revoke buttons when currentSessionHandle is null', async () => {
    mockApi.get.mockResolvedValue({ data: sessionsPayload(undefined, null) });
    wrapper = mountSection();
    await flushPromises();

    // null must not accidentally match any row (the guard in isCurrentSession).
    expect(wrapper.find('[data-testid^="session-current-"]').exists()).toBe(false);
    expect(revoke(wrapper, 'a15e5510000000000000000000000001').exists()).toBe(true);
    expect(revoke(wrapper, 'a15e5510000000000000000000000002').exists()).toBe(true);
  });

  // #4328: revoke-all against your OWN account is deliberately NOT refused —
  // it is the first containment step for a leaked colonel cookie — but the
  // server keeps the session you are working in, so the copy has to say so
  // rather than promising a full logout.
  describe('revoke-all confirm copy', () => {
    /** The revoke-all dialog is the LAST AdminConfirmDialog in the template. */
    function revokeAllDescription(w: VueWrapper): unknown {
      const dialogs = w.findAllComponents({ name: 'AdminConfirmDialog' });
      return dialogs[dialogs.length - 1].props('description');
    }

    it('promises a full logout for another account', async () => {
      mockApi.get.mockResolvedValue({ data: sessionsPayload(undefined, null) });
      wrapper = mountSection();
      await flushPromises();

      expect(revokeAllDescription(wrapper)).toBe(
        'web.admin.customers.detail.sessions.revokeAll.confirmDescription'
      );
    });

    it('says the current session is kept on your own account', async () => {
      mockApi.get.mockResolvedValue({ data: sessionsPayload(undefined, null) });
      wrapper = mountSection({ isSelf: true });
      await flushPromises();

      expect(revokeAllDescription(wrapper)).toBe(
        'web.admin.customers.detail.sessions.revokeAll.selfDescription'
      );
    });
  });
});

describe('adminCustomerSessionSchema — geo_country', () => {
  it('parses a resolved code and a null — the only shapes the API emits', () => {
    // Otto's '**' unknown sentinel is normalized to null server-side and never
    // crosses the API.
    const result = colonelCustomerSessionsResponseSchema.safeParse(
      sessionsPayload([
        sessionRow({ session_handle: 'a15e551000000000000000000000c0de', geo_country: 'DE' }),
        sessionRow({ session_handle: 'a15e55100000000000000000000000aa', geo_country: null }),
      ])
    );
    expect(result.success).toBe(true);
    if (!result.success) return;
    const rows = result.data.details?.sessions ?? [];
    expect(rows[0].geo_country).toBe('DE');
    expect(rows[1].geo_country).toBeNull();
  });

  it('parses rows that OMIT geo_country entirely — deploy skew must not fail the whole list', () => {
    const payload = sessionsPayload([
      sessionRowWithoutCountry({ session_handle: 'a15e551000000000000000000000000d' }),
      sessionRow({ session_handle: 'a15e551000000000000000000000000e', geo_country: 'FR' }),
    ]);
    const result = colonelCustomerSessionsResponseSchema.safeParse(payload);
    expect(result.success).toBe(true);
    if (!result.success) return;
    const rows = result.data.details?.sessions ?? [];
    // The pre-join row survives (key simply absent) alongside the joined one.
    expect(rows).toHaveLength(2);
    expect(rows[0].geo_country).toBeUndefined();
    expect(rows[1].geo_country).toBe('FR');
  });
});

describe('AdminCustomerSessionsSection — session authority notice', () => {
  let wrapper: VueWrapper;

  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
  });
  afterEach(() => wrapper?.unmount());

  it('shows nothing in simple mode or when the block is absent', async () => {
    mockApi.get.mockResolvedValue({ data: sessionsPayload() });
    wrapper = mountSection();
    await flushPromises();
    expect(wrapper.find('[data-testid="session-authority-notice"]').exists()).toBe(false);
  });

  it('says the sidecar is non-authoritative in full mode and links to Rodauth Admin', async () => {
    const payload = sessionsPayload() as unknown as { details: Record<string, unknown> };
    payload.details.session_authority = {
      mode: 'full',
      authoritative: false,
      rodauth_admin_url: 'http://127.0.0.1:9292',
    };
    mockApi.get.mockResolvedValue({ data: payload });
    wrapper = mountSection();
    await flushPromises();

    expect(wrapper.find('[data-testid="session-authority-notice"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="session-authority-link"]').attributes('href')).toBe(
      'http://127.0.0.1:9292'
    );
    // The table still renders beneath the notice — the rows are real, just not the whole truth.
    expect(wrapper.find('[data-testid="sessions-section-table"]').exists()).toBe(true);
  });

  it('uses the revoke-all-aware copy: revoke-all DOES end the Rodauth sessions', async () => {
    // Regression for PR #4390 review: the shared notice's "revoking a session
    // here does not end a Rodauth session" is true for per-row revoke but false
    // for the Revoke all button on this panel, which purges the account's
    // account_active_session_keys. The customer surface must say so.
    const payload = sessionsPayload() as unknown as { details: Record<string, unknown> };
    payload.details.session_authority = {
      mode: 'full',
      authoritative: false,
      rodauth_admin_url: 'http://127.0.0.1:9292',
    };
    mockApi.get.mockResolvedValue({ data: payload });
    wrapper = mountSection();
    await flushPromises();

    // The test i18n echoes keys, so assert on the key the customer surface
    // selects: the revoke-all-aware variant, not the plain per-row description.
    const notice = wrapper.find('[data-testid="session-authority-notice"]');
    expect(notice.text()).toContain('web.admin.sessions.authority.descriptionRevokeAll');
  });
});

describe('SessionAuthorityNotice — surface-aware copy', () => {
  const authority = {
    mode: 'full' as const,
    authoritative: false,
    rodauth_admin_url: null,
  };

  const mountNotice = (props: Record<string, unknown>) =>
    mount(SessionAuthorityNotice, { props, global: { plugins: [i18n] } });

  it('uses the plain per-row description on the default (console) surface', () => {
    // The global console only offers single-revoke (self-expiring row), so the
    // default context must NOT claim revoke-all semantics.
    const wrapper = mountNotice({ authority });
    const text = wrapper.find('[data-testid="session-authority-notice"]').text();
    expect(text).toContain('web.admin.sessions.authority.description');
    expect(text).not.toContain('descriptionRevokeAll');
  });

  it('uses the revoke-all-aware description on the customer surface', () => {
    const wrapper = mountNotice({ authority, context: 'customer' });
    expect(wrapper.find('[data-testid="session-authority-notice"]').text()).toContain(
      'web.admin.sessions.authority.descriptionRevokeAll'
    );
  });
});

describe('AdminCustomerSessionsSection — country column', () => {
  let wrapper: VueWrapper;

  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
  });

  afterEach(() => wrapper?.unmount());

  it('renders a resolved country code verbatim', async () => {
    mockApi.get.mockResolvedValue({
      data: sessionsPayload([sessionRow({ geo_country: 'DE' })]),
    });
    wrapper = mountSection();
    await flushPromises();

    expect(countryCell(wrapper, 0)).toBe('DE');
  });

  it('renders a null and an absent geo_country as Unknown', async () => {
    mockApi.get.mockResolvedValue({
      data: sessionsPayload([
        sessionRow({ session_handle: 'a15e55100000000000000000000000aa', geo_country: null }),
        sessionRowWithoutCountry({ session_handle: 'a15e55100000000000000000000000ab' }),
      ]),
    });
    wrapper = mountSection();
    await flushPromises();

    expect(countryCell(wrapper, 0)).toBe(UNKNOWN);
    expect(countryCell(wrapper, 1)).toBe(UNKNOWN);
  });

  it('never leaks an IP into the country cell — only a 2-letter code or Unknown', async () => {
    const rows = [
      sessionRow({
        session_handle: 'a15e551000000000000000000000c0de',
        ip_address: '203.0.113.7',
        geo_country: 'DE',
      }),
      sessionRow({
        session_handle: 'a15e55100000000000000000000000aa',
        ip_address: '192.0.2.44',
        geo_country: null,
      }),
      sessionRowWithoutCountry({
        session_handle: 'a15e55100000000000000000000000ab',
        ip_address: '2001:db8::1',
      }),
    ];
    mockApi.get.mockResolvedValue({ data: sessionsPayload(rows) });
    wrapper = mountSection();
    await flushPromises();

    rows.forEach((row, index) => {
      const text = countryCell(wrapper, index);
      // Country is a country: an ISO-3166-1 alpha-2 code, or the Unknown label.
      expect(text === UNKNOWN || /^[A-Z]{2}$/.test(text)).toBe(true);
      expect(text).not.toContain(row.ip_address as string);
    });
  });
});
