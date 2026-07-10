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

// Render the HeadlessUI dialog markup synchronously (mirrors AdminBannedIps.spec).
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
import { createTestI18n } from '@tests/setup';

const i18n = createTestI18n();

const LIST_URL = '/api/colonel/sessions';
const SID = 'sid_auth_1';

function sessionsPayload(rows = [sessionRow()]) {
  return {
    shrimp: '',
    record: {},
    details: {
      sessions: rows,
      pagination: { page: 1, per_page: 50, total_count: rows.length, total_pages: 1 },
    },
  };
}

function sessionRow(overrides: Record<string, unknown> = {}) {
  return {
    session_id: SID,
    key: `session:${SID}`,
    authenticated: true,
    email: 'alice@example.com',
    external_id: 'ext_1',
    role: 'customer',
    ip_address: '203.0.113.7',
    created_at: 1700000000,
    ...overrides,
  };
}

function detailPayload() {
  return {
    shrimp: '',
    record: {
      session_id: SID,
      key: `session:${SID}`,
      ttl: 3600,
      authenticated: true,
      email: 'alice@example.com',
      external_id: 'ext_1',
      account_id: 42,
      role: 'customer',
      locale: 'en',
      ip_address: '203.0.113.7',
      authenticated_at: 1700000000,
      authenticated_by: 'password',
      active_session_id: 'as_1',
    },
    details: { data: { authenticated: true, email: 'alice@example.com' } },
  };
}

function revokeAck() {
  return {
    shrimp: '',
    record: { session_id: SID, deleted: true },
    details: { message: 'Session revoked successfully' },
  };
}

const mountView = (pinia: ReturnType<typeof createPinia>) =>
  mount(AdminSessions, { global: { plugins: [pinia, i18n] } });

const dialogInput = (w: VueWrapper) => w.find('#admin-confirm-input');
const dialogSubmit = (w: VueWrapper) => w.find('[data-testid="admin-confirm-submit"]');
const listGetCount = () => mockApi.get.mock.calls.filter((c) => c[0] === LIST_URL).length;

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
    expect(table.text()).toContain(SID);
    // Email is obscured by default (RevealEmail); full address hidden until reveal.
    expect(table.text()).not.toContain('alice@example.com');
    expect(table.text()).toContain('a•••@e•••.com');
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

  // ---- Inspect drawer -------------------------------------------------------

  it('opens the detail drawer on row click and loads the session detail', async () => {
    mockApi.get.mockResolvedValueOnce({ data: sessionsPayload() });
    wrapper = mountView(pinia);
    await flushPromises();

    mockApi.get.mockResolvedValueOnce({ data: detailPayload() });
    await wrapper.find('[data-testid="sessions-table"] tbody tr').trigger('click');
    await flushPromises();

    expect(mockApi.get).toHaveBeenCalledWith(`${LIST_URL}/${SID}`, undefined);
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

    it('opens a danger dialog from the row action, gated until the id is retyped', async () => {
      await wrapper.find(`[data-testid="revoke-${SID}"]`).trigger('click');
      await flushPromises();

      expect(dialogInput(wrapper).exists()).toBe(true);
      expect(dialogSubmit(wrapper).attributes('disabled')).toBeDefined();

      await dialogInput(wrapper).setValue('not-the-id');
      expect(dialogSubmit(wrapper).attributes('disabled')).toBeDefined();

      await dialogInput(wrapper).setValue(SID);
      expect(dialogSubmit(wrapper).attributes('disabled')).toBeUndefined();
    });

    it('DELETEs the session, notifies and refreshes the list on confirm', async () => {
      mockApi.delete.mockResolvedValue({ data: revokeAck() });
      const before = listGetCount();

      await wrapper.find(`[data-testid="revoke-${SID}"]`).trigger('click');
      await dialogInput(wrapper).setValue(SID);
      await wrapper.find('form').trigger('submit');
      await flushPromises();

      expect(mockApi.delete).toHaveBeenCalledWith(`${LIST_URL}/${SID}`);
      expect(showMock).toHaveBeenCalledWith('web.admin.sessions.revoke.success', 'success');
      expect(dialogInput(wrapper).exists()).toBe(false);
      expect(listGetCount()).toBe(before + 1);
    });

    it('does NOT DELETE when submitted without a matching token', async () => {
      mockApi.delete.mockResolvedValue({ data: revokeAck() });
      await wrapper.find(`[data-testid="revoke-${SID}"]`).trigger('click');
      await dialogInput(wrapper).setValue('wrong');
      await wrapper.find('form').trigger('submit');
      await flushPromises();

      expect(mockApi.delete).not.toHaveBeenCalled();
      expect(showMock).not.toHaveBeenCalled();
    });

    it('surfaces a 4xx in the dialog and stays open on failure', async () => {
      mockApi.delete.mockRejectedValue(axiosError(404, { error: 'Session not found' }));
      const before = listGetCount();

      await wrapper.find(`[data-testid="revoke-${SID}"]`).trigger('click');
      await dialogInput(wrapper).setValue(SID);
      await wrapper.find('form').trigger('submit');
      await flushPromises();

      expect(wrapper.find('[role="alert"]').text()).toContain('Session not found');
      expect(showMock).not.toHaveBeenCalled();
      expect(dialogInput(wrapper).exists()).toBe(true);
      expect(listGetCount()).toBe(before);
    });
  });
});
