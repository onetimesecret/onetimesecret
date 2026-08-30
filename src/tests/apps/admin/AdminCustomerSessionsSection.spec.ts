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
import {
  colonelCustomerSessionsResponseSchema,
  type AdminCustomerSession,
} from '@/schemas/api/internal/responses/colonel-customer-sessions';
import { createTestI18n } from '@tests/setup';

const i18n = createTestI18n();

const USER_ID = 'ur_abc123';

/** Pass-through i18n (ADR-014): keys render verbatim, so assert on the key. */
const COUNTRY_HEADER = 'web.admin.customers.detail.sessions.columns.country';
const UNKNOWN = 'web.admin.customers.detail.sessions.unknown';

function sessionRow(overrides: Partial<AdminCustomerSession> = {}): AdminCustomerSession {
  return {
    session_id: 'sid_1',
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
  rows: AdminCustomerSession[] = [sessionRow(), sessionRow({ session_id: 'sid_2' })],
  currentSessionId: string | null = null
) {
  return {
    shrimp: '',
    record: {},
    details: { sessions: rows, count: rows.length, current_session_id: currentSessionId },
  };
}

const mountSection = () =>
  mount(AdminCustomerSessionsSection, {
    props: { userId: USER_ID },
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
    mockApi.get.mockResolvedValue({ data: sessionsPayload(undefined, 'sid_1') });
    wrapper = mountSection();
    await flushPromises();

    // The colonel's own row: badge in, per-row revoke out (v-if/v-else).
    expect(badge(wrapper, 'sid_1').exists()).toBe(true);
    expect(revoke(wrapper, 'sid_1').exists()).toBe(false);
    expect(badge(wrapper, 'sid_1').text()).toContain(
      'web.admin.customers.detail.sessions.current.badge'
    );
    expect(badge(wrapper, 'sid_1').attributes('title')).toBe(
      'web.admin.customers.detail.sessions.current.tooltip'
    );
  });

  it('renders the revoke button (and no badge) on non-matching rows', async () => {
    mockApi.get.mockResolvedValue({ data: sessionsPayload(undefined, 'sid_1') });
    wrapper = mountSection();
    await flushPromises();

    expect(revoke(wrapper, 'sid_2').exists()).toBe(true);
    expect(badge(wrapper, 'sid_2').exists()).toBe(false);
  });

  it('shows no badge and all revoke buttons when currentSessionId is null', async () => {
    mockApi.get.mockResolvedValue({ data: sessionsPayload(undefined, null) });
    wrapper = mountSection();
    await flushPromises();

    // null must not accidentally match any row (the guard in isCurrentSession).
    expect(wrapper.find('[data-testid^="session-current-"]').exists()).toBe(false);
    expect(revoke(wrapper, 'sid_1').exists()).toBe(true);
    expect(revoke(wrapper, 'sid_2').exists()).toBe(true);
  });
});

describe('adminCustomerSessionSchema — geo_country', () => {
  it('parses a resolved code and a null — the only shapes the API emits', () => {
    // Otto's '**' unknown sentinel is normalized to null server-side and never
    // crosses the API.
    const result = colonelCustomerSessionsResponseSchema.safeParse(
      sessionsPayload([
        sessionRow({ session_id: 'sid_code', geo_country: 'DE' }),
        sessionRow({ session_id: 'sid_null', geo_country: null }),
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
      sessionRowWithoutCountry({ session_id: 'sid_old' }),
      sessionRow({ session_id: 'sid_new', geo_country: 'FR' }),
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
        sessionRow({ session_id: 'sid_null', geo_country: null }),
        sessionRowWithoutCountry({ session_id: 'sid_absent' }),
      ]),
    });
    wrapper = mountSection();
    await flushPromises();

    expect(countryCell(wrapper, 0)).toBe(UNKNOWN);
    expect(countryCell(wrapper, 1)).toBe(UNKNOWN);
  });

  it('never leaks an IP into the country cell — only a 2-letter code or Unknown', async () => {
    const rows = [
      sessionRow({ session_id: 'sid_code', ip_address: '203.0.113.7', geo_country: 'DE' }),
      sessionRow({ session_id: 'sid_null', ip_address: '192.0.2.44', geo_country: null }),
      sessionRowWithoutCountry({ session_id: 'sid_absent', ip_address: '2001:db8::1' }),
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
