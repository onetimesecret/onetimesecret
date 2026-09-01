// src/tests/apps/admin/AdminSessions.spec.ts

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

// Render the HeadlessUI dialog markup synchronously.
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

import AdminSessions from '@/apps/admin/views/AdminSessions.vue';
import type { ColonelSession } from '@/schemas/api/internal/responses/colonel-sessions';
import { createTestI18n } from '@tests/setup';

const i18n = createTestI18n();

const LIST_URL = '/api/colonel/sessions';
/**
 * A 32-hex opaque handle (#4330). The console never receives the raw session id
 * — that value is the user's `onetime.session` cookie — so every route, testid
 * and confirmation below is keyed on this instead. RAW_SID exists only to be
 * asserted ABSENT from the DOM.
 */
const HANDLE = '0123456789abcdef0123456789abcdef';
const RAW_SID = 'a'.repeat(64);
const OWNER = 'ext_1';
const OWNER_EMAIL = 'alice@example.com';
const DETAIL_URL = `${LIST_URL}/${HANDLE}?user_id=${OWNER}`;

/** Pass-through i18n (ADR-014): keys render verbatim, so assert on the key. */
const COUNTRY_HEADER = 'web.admin.sessions.columns.country';
const UNKNOWN = 'web.admin.sessions.detail.unknown';

function sessionsPayload(
  rows: ColonelSession[] = [sessionRow()],
  currentSessionHandle: string | null = null
) {
  return {
    shrimp: '',
    record: {},
    details: {
      sessions: rows,
      pagination: { page: 1, per_page: 50, total_count: rows.length, total_pages: 1 },
      scan: { scanned: rows.length, anonymous_count: 0, scan_capped: false },
      // The acting colonel's OWN row (#4328) — null when the server cannot
      // identify the request session.
      current_session_handle: currentSessionHandle,
    },
  };
}

function sessionRow(overrides: Partial<ColonelSession> = {}): ColonelSession {
  return {
    session_handle: HANDLE,
    authenticated: true,
    email: OWNER_EMAIL,
    external_id: OWNER,
    role: 'customer',
    ip_address: '203.0.113.7',
    user_agent: 'Mozilla/5.0',
    created_at: 1700000000,
    geo_country: 'DE',
    ...overrides,
  };
}

/**
 * A row from a backend that predates the geo join: the key is ABSENT, not null.
 * `{ geo_country: undefined }` would not exercise the same thing — the property
 * would still exist — so it is deleted outright. `geo_country` is declared
 * `.optional()` on the schema (see colonelSessionSchema), so deleting it still
 * yields a valid ColonelSession — no cast needed.
 */
function sessionRowWithoutCountry(overrides: Partial<ColonelSession> = {}): ColonelSession {
  const row = sessionRow(overrides);
  delete row.geo_country;
  return row;
}

function detailPayload() {
  return {
    shrimp: '',
    record: {
      session_handle: HANDLE,
      ttl: 3600,
      authenticated: true,
      email: 'alice@example.com',
      external_id: 'ext_1',
      account_id: 42,
      role: 'customer',
      locale: 'en',
      ip_address: '203.0.113.7',
      user_agent: 'Mozilla/5.0',
      org_context: '019f4ac1-b8d6-7ca9-858d-ba3d7e1e0210',
      authenticated_at: 1700000000,
      authenticated_by: ['password'],
      active_session_id: 'as_1',
    },
    details: {
      data: { authenticated: true, email: 'alice@example.com' },
      scan_capped: false,
    },
  };
}

function revokeAck() {
  return {
    shrimp: '',
    record: { session_handle: HANDLE, deleted: true },
    details: { message: 'Session revoked successfully' },
  };
}

const mountView = (pinia: ReturnType<typeof createPinia>) =>
  mount(AdminSessions, { global: { plugins: [pinia, i18n] } });

const dialogInput = (w: VueWrapper) => w.find('#admin-confirm-input');
const dialogSubmit = (w: VueWrapper) => w.find('[data-testid="admin-confirm-submit"]');
const listGetCount = () => mockApi.get.mock.calls.filter((c) => c[0] === LIST_URL).length;

/**
 * Text of the country cell for one body row. DataTable emits cells positionally
 * (one `<td>` per column, same order), so the column is located by its header
 * rather than a hard-coded index — the assertion survives a column reshuffle.
 */
function countryCell(w: VueWrapper, rowIndex: number): string {
  const table = w.find('[data-testid="sessions-table"]');
  const columnIndex = table.findAll('thead th').findIndex((th) => th.text() === COUNTRY_HEADER);
  expect(columnIndex).toBeGreaterThanOrEqual(0);
  return table.findAll('tbody tr')[rowIndex].findAll('td')[columnIndex].text();
}

describe('AdminSessions (list + search + inspect + guarded revoke — ticket #40)', () => {
  let wrapper: VueWrapper;
  let pinia: ReturnType<typeof createPinia>;

  beforeEach(() => {
    pinia = createPinia();
    setActivePinia(pinia);
    vi.clearAllMocks();
    vi.useFakeTimers();
  });
  afterEach(() => {
    vi.runOnlyPendingTimers();
    vi.useRealTimers();
    wrapper?.unmount();
  });

  // ---- List -----------------------------------------------------------------

  it('fetches the sessions page on mount and renders a row per session', async () => {
    mockApi.get.mockResolvedValue({ data: sessionsPayload() });
    wrapper = mountView(pinia);
    await flushPromises();

    // First (list) fetch carries page/per_page but no search param.
    expect(mockApi.get).toHaveBeenCalledWith(LIST_URL, {
      params: { page: 1, per_page: 50 },
    });
    const table = wrapper.find('[data-testid="sessions-table"]');
    expect(table.exists()).toBe(true);
    // Truncated handle in the cell, full value in the title attribute.
    expect(table.text()).toContain(HANDLE.slice(0, 12));
    // Email is obscured by default (RevealEmail); full address hidden until reveal.
    expect(table.text()).not.toContain('alice@example.com');
    expect(table.text()).toContain('a•••@e•••.com');
  });

  it('never renders a raw session id, even when the backend leaks one', async () => {
    // The schema strips unknown keys, so a leaked sid cannot reach the row —
    // this is the belt-and-braces DOM assertion for #4330: no 64-hex string
    // (the raw sid shape) anywhere in the console, list or drawer.
    const leaky = { ...sessionRow(), session_id: RAW_SID, key: `session:${RAW_SID}` };
    mockApi.get.mockResolvedValueOnce({
      data: sessionsPayload([leaky as unknown as ColonelSession]),
    });
    wrapper = mountView(pinia);
    await flushPromises();

    mockApi.get.mockResolvedValueOnce({ data: detailPayload() });
    await wrapper.find('[data-testid="sessions-table"] tbody tr').trigger('click');
    await flushPromises();

    expect(wrapper.html()).not.toMatch(/[0-9a-f]{64}/i);
    expect(wrapper.html()).not.toContain(RAW_SID);
  });

  it('debounces the search box into a single filtered fetch', async () => {
    mockApi.get.mockResolvedValue({ data: sessionsPayload() });
    wrapper = mountView(pinia);
    await flushPromises();
    const before = listGetCount();

    await wrapper.find('[data-testid="sessions-filterbar"] input').setValue('alice');
    // Debounced — no request yet.
    expect(listGetCount()).toBe(before);

    vi.advanceTimersByTime(300);
    await flushPromises();

    expect(listGetCount()).toBe(before + 1);
    expect(mockApi.get).toHaveBeenLastCalledWith(LIST_URL, {
      params: { page: 1, per_page: 50, search: 'alice' },
    });
  });

  it('fetches immediately when the search button is clicked (debounce cancelled)', async () => {
    mockApi.get.mockResolvedValue({ data: sessionsPayload() });
    wrapper = mountView(pinia);
    await flushPromises();

    await wrapper.find('[data-testid="sessions-filterbar"] input').setValue('alice');
    const before = listGetCount();

    const submitBtn = wrapper
      .findAll('[data-testid="sessions-filterbar"] button')
      .find((b) => b.text().includes('searchSubmit'));
    await submitBtn!.trigger('click');
    await flushPromises();

    // Immediate fetch with the term…
    expect(listGetCount()).toBe(before + 1);
    expect(mockApi.get).toHaveBeenLastCalledWith(LIST_URL, {
      params: { page: 1, per_page: 50, search: 'alice' },
    });

    // …and the pending debounce was cancelled — no second, late request.
    vi.advanceTimersByTime(300);
    await flushPromises();
    expect(listGetCount()).toBe(before + 1);
  });

  it('shows the error banner + retry on a network failure', async () => {
    mockApi.get.mockRejectedValue(new Error('Network Error'));
    wrapper = mountView(pinia);
    await flushPromises();

    const banner = wrapper.find('[data-testid="sessions-error"]');
    expect(banner.exists()).toBe(true);

    mockApi.get.mockResolvedValueOnce({ data: sessionsPayload() });
    await banner.find('button').trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-testid="sessions-error"]').exists()).toBe(false);
  });

  // ---- Country column -------------------------------------------------------

  describe('country column', () => {
    it('renders a resolved country code verbatim', async () => {
      mockApi.get.mockResolvedValue({
        data: sessionsPayload([sessionRow({ geo_country: 'DE' })]),
      });
      wrapper = mountView(pinia);
      await flushPromises();

      expect(countryCell(wrapper, 0)).toBe('DE');
    });

    it('renders a null and an absent geo_country as Unknown', async () => {
      mockApi.get.mockResolvedValue({
        data: sessionsPayload([
          sessionRow({ session_handle: 'b'.repeat(32), geo_country: null }),
          sessionRowWithoutCountry({ session_handle: 'c'.repeat(32) }),
        ]),
      });
      wrapper = mountView(pinia);
      await flushPromises();

      expect(countryCell(wrapper, 0)).toBe(UNKNOWN);
      expect(countryCell(wrapper, 1)).toBe(UNKNOWN);
    });

    it('never leaks an IP into the country cell — only a 2-letter code or Unknown', async () => {
      const rows = [
        sessionRow({
          session_handle: 'd'.repeat(32),
          ip_address: '203.0.113.7',
          geo_country: 'DE',
        }),
        sessionRow({ session_handle: 'e'.repeat(32), ip_address: '192.0.2.44', geo_country: null }),
        sessionRowWithoutCountry({ session_handle: 'f'.repeat(32), ip_address: '2001:db8::1' }),
      ];
      mockApi.get.mockResolvedValue({ data: sessionsPayload(rows) });
      wrapper = mountView(pinia);
      await flushPromises();

      rows.forEach((row, index) => {
        const text = countryCell(wrapper, index);
        // Country is a country: an ISO-3166-1 alpha-2 code, or the Unknown label.
        expect(text === UNKNOWN || /^[A-Z]{2}$/.test(text)).toBe(true);
        expect(text).not.toContain(row.ip_address as string);
      });
    });
  });

  // ---- Inspect drawer -------------------------------------------------------

  it('opens the detail drawer on row click and loads the session detail', async () => {
    mockApi.get.mockResolvedValueOnce({ data: sessionsPayload() });
    wrapper = mountView(pinia);
    await flushPromises();

    mockApi.get.mockResolvedValueOnce({ data: detailPayload() });
    await wrapper.find('[data-testid="sessions-table"] tbody tr').trigger('click');
    await flushPromises();

    // The handle routes, and the row's owner rides along as the resolution hint.
    expect(mockApi.get).toHaveBeenCalledWith(DETAIL_URL, undefined);
    const content = wrapper.find('[data-testid="session-drawer-content"]');
    expect(content.exists()).toBe(true);
    expect(content.text()).toContain('as_1'); // active_session_id field
  });

  // ---- Guarded revoke (D4) --------------------------------------------------

  describe('revoke — typed-confirmation gate', () => {
    beforeEach(async () => {
      mockApi.get.mockResolvedValue({ data: sessionsPayload() });
      wrapper = mountView(pinia);
      await flushPromises();
    });

    it('opens a danger dialog gated on the session OWNER, not on the handle', async () => {
      await wrapper.find(`[data-testid="revoke-${HANDLE}"]`).trigger('click');
      await flushPromises();

      expect(dialogInput(wrapper).exists()).toBe(true);
      expect(dialogSubmit(wrapper).attributes('disabled')).toBeDefined();

      // The handle is what routes the request, so retyping it must NOT unlock
      // the gate — the token is a second, independent identifier (#4330/#4326).
      await dialogInput(wrapper).setValue(HANDLE);
      expect(dialogSubmit(wrapper).attributes('disabled')).toBeDefined();

      await dialogInput(wrapper).setValue(OWNER_EMAIL);
      expect(dialogSubmit(wrapper).attributes('disabled')).toBeUndefined();
    });

    it('falls back to the external id as the confirmation token when the row has no email', async () => {
      wrapper.unmount();
      mockApi.get.mockResolvedValue({ data: sessionsPayload([sessionRow({ email: null })]) });
      wrapper = mountView(pinia);
      await flushPromises();

      await wrapper.find(`[data-testid="revoke-${HANDLE}"]`).trigger('click');
      await dialogInput(wrapper).setValue(OWNER);
      expect(dialogSubmit(wrapper).attributes('disabled')).toBeUndefined();
    });

    it('DELETEs the session, notifies and refreshes the list on confirm', async () => {
      mockApi.delete.mockResolvedValue({ data: revokeAck() });
      const before = listGetCount();

      await wrapper.find(`[data-testid="revoke-${HANDLE}"]`).trigger('click');
      await dialogInput(wrapper).setValue(OWNER_EMAIL);
      await wrapper.find('form').trigger('submit');
      await flushPromises();

      // The session owner's email rides X-OTS-Confirm (#4326) — a HEADER, so it
      // never lands in an access log or the operator's history. `?user_id=` is
      // only the owner hint for the handle lookup.
      expect(mockApi.delete).toHaveBeenCalledWith(DETAIL_URL, {
        headers: { 'X-OTS-Confirm': encodeURIComponent(OWNER_EMAIL) },
      });
      expect(DETAIL_URL).not.toContain(encodeURIComponent(OWNER_EMAIL));
      expect(showMock).toHaveBeenCalledWith('web.admin.sessions.revoke.success', 'success');
      expect(dialogInput(wrapper).exists()).toBe(false);
      expect(listGetCount()).toBe(before + 1);
    });

    it('does NOT DELETE when submitted without a matching token', async () => {
      mockApi.delete.mockResolvedValue({ data: revokeAck() });
      await wrapper.find(`[data-testid="revoke-${HANDLE}"]`).trigger('click');
      await dialogInput(wrapper).setValue('wrong');
      await wrapper.find('form').trigger('submit');
      await flushPromises();

      expect(mockApi.delete).not.toHaveBeenCalled();
      expect(showMock).not.toHaveBeenCalled();
    });

    it('surfaces a 4xx in the dialog and stays open on failure', async () => {
      mockApi.delete.mockRejectedValue(axiosError(404, { error: 'Session not found' }));
      const before = listGetCount();

      await wrapper.find(`[data-testid="revoke-${HANDLE}"]`).trigger('click');
      await dialogInput(wrapper).setValue(OWNER_EMAIL);
      await wrapper.find('form').trigger('submit');
      await flushPromises();

      expect(wrapper.find('[role="alert"]').text()).toContain('Session not found');
      expect(showMock).not.toHaveBeenCalled();
      expect(dialogInput(wrapper).exists()).toBe(true);
      expect(listGetCount()).toBe(before);
    });
  });

  // ---- Self-revoke interlock (#4328) ----------------------------------------
  //
  // The server refuses a self-revoke with a 422 regardless; disabling here is
  // defence in depth (mirroring the per-customer panel's badge) so the operator
  // is not asked to retype a confirmation token for an action that cannot work.
  describe('own session', () => {
    const OTHER_HANDLE = 'fedcba9876543210fedcba9876543210';

    async function mountWithCurrent(current: string | null) {
      mockApi.get.mockResolvedValue({
        data: sessionsPayload(
          [sessionRow(), sessionRow({ session_handle: OTHER_HANDLE, email: 'bob@example.com' })],
          current
        ),
      });
      wrapper = mountView(pinia);
      await flushPromises();
    }

    it('disables the revoke button on the row matching current_session_handle', async () => {
      await mountWithCurrent(HANDLE);

      expect(
        wrapper.find(`[data-testid="revoke-${HANDLE}"]`).attributes('disabled')
      ).toBeDefined();
      expect(wrapper.find(`[data-testid="revoke-${HANDLE}"]`).attributes('title')).toBe(
        'web.admin.sessions.revoke.ownSession'
      );
    });

    it('leaves every other row revocable', async () => {
      await mountWithCurrent(HANDLE);

      expect(
        wrapper.find(`[data-testid="revoke-${OTHER_HANDLE}"]`).attributes('disabled')
      ).toBeUndefined();
    });

    it('opens no confirm dialog and issues no DELETE for the own row', async () => {
      await mountWithCurrent(HANDLE);
      await wrapper.find(`[data-testid="revoke-${HANDLE}"]`).trigger('click');
      await flushPromises();

      expect(dialogInput(wrapper).exists()).toBe(false);
      expect(mockApi.delete).not.toHaveBeenCalled();
    });

    it('disables nothing when the server sends no current handle', async () => {
      await mountWithCurrent(null);

      expect(
        wrapper.find(`[data-testid="revoke-${HANDLE}"]`).attributes('disabled')
      ).toBeUndefined();
    });
  });
});
