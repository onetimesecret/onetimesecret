// src/tests/apps/admin/AdminBannedIps.spec.ts

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

// Render the HeadlessUI dialog markup synchronously (mirrors AdminSecrets.spec).
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

import AdminBannedIps from '@/apps/admin/views/AdminBannedIps.vue';
import { createTestI18n } from '@tests/setup';

const i18n = createTestI18n();

const LIST_URL = '/api/colonel/banned-ips';
const EXISTING_IP = '203.0.113.4';
const NEW_IP = '198.51.100.7';

function bannedIpsPayload(rows = [bannedIpRow()]) {
  return {
    shrimp: '',
    record: {},
    details: {
      current_ip: '203.0.113.9',
      banned_ips: rows,
      total_count: rows.length,
    },
  };
}

function bannedIpRow(overrides: Record<string, unknown> = {}) {
  return {
    id: 'bip1',
    ip_address: EXISTING_IP,
    reason: 'abuse',
    banned_by: 'objid_colonel',
    banned_at: 1700000000,
    ...overrides,
  };
}

function banAck() {
  return {
    shrimp: '',
    record: {
      id: 'bip2',
      ip_address: NEW_IP,
      reason: 'credential stuffing',
      banned_by: 'objid_colonel',
      banned_at: 1700000100,
    },
    details: { message: 'IP address banned successfully' },
  };
}

function unbanAck() {
  return {
    shrimp: '',
    record: { ip_address: EXISTING_IP, unbanned: true },
    details: { message: 'IP address unbanned successfully' },
  };
}

const mountView = (pinia: ReturnType<typeof createPinia>) =>
  mount(AdminBannedIps, { global: { plugins: [pinia, i18n] } });

const dialogInput = (w: VueWrapper) => w.find('#admin-confirm-input');
const dialogSubmit = (w: VueWrapper) => w.find('[data-testid="admin-confirm-submit"]');
const listGetCount = () => mockApi.get.mock.calls.filter((c) => c[0] === LIST_URL).length;

describe('AdminBannedIps (list + guarded ban/unban — ticket #33)', () => {
  let wrapper: VueWrapper;
  let pinia: ReturnType<typeof createPinia>;

  beforeEach(() => {
    pinia = createPinia();
    setActivePinia(pinia);
    vi.clearAllMocks();
  });
  afterEach(() => wrapper?.unmount());

  // ---- List -----------------------------------------------------------------

  it('fetches the banned-IP index on mount and renders a row per ban', async () => {
    mockApi.get.mockResolvedValue({ data: bannedIpsPayload() });
    wrapper = mountView(pinia);
    await flushPromises();

    // Bounded index read — no server pagination params (#2211).
    expect(mockApi.get).toHaveBeenCalledWith(LIST_URL, undefined);
    const table = wrapper.find('[data-testid="bannedips-table"]');
    expect(table.exists()).toBe(true);
    expect(table.text()).toContain(EXISTING_IP);
    expect(table.text()).toContain('abuse');
    // The current-IP panel reads from the same envelope.
    expect(wrapper.find('[data-testid="current-ip"]').text()).toContain('203.0.113.9');
  });

  it('shows the error banner + retry on a network failure', async () => {
    mockApi.get.mockRejectedValue(new Error('Network Error'));
    wrapper = mountView(pinia);
    await flushPromises();

    const banner = wrapper.find('[data-testid="bannedips-error"]');
    expect(banner.exists()).toBe(true);

    mockApi.get.mockResolvedValueOnce({ data: bannedIpsPayload() });
    await banner.find('button').trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-testid="bannedips-error"]').exists()).toBe(false);
  });

  // ---- Guarded ban (D4) -----------------------------------------------------

  describe('ban — typed-confirmation gate', () => {
    beforeEach(async () => {
      mockApi.get.mockResolvedValue({ data: bannedIpsPayload() });
      wrapper = mountView(pinia);
      await flushPromises();
      // Open the ban form and enter an IP + reason.
      await wrapper.find('[data-testid="toggle-ban-form"]').trigger('click');
      await wrapper.find('[data-testid="ban-ip-input"]').setValue(NEW_IP);
      await wrapper.find('[data-testid="ban-reason-input"]').setValue('credential stuffing');
    });

    it('opens a danger dialog whose confirm stays disabled until the IP is retyped', async () => {
      await wrapper.find('[data-testid="ban-submit"]').trigger('click');
      await flushPromises();

      expect(dialogInput(wrapper).exists()).toBe(true);
      expect(dialogSubmit(wrapper).attributes('disabled')).toBeDefined();

      await dialogInput(wrapper).setValue('not-the-ip');
      expect(dialogSubmit(wrapper).attributes('disabled')).toBeDefined();

      await dialogInput(wrapper).setValue(NEW_IP);
      expect(dialogSubmit(wrapper).attributes('disabled')).toBeUndefined();
    });

    it('POSTs the ban with {ip_address, reason}, notifies, closes the form and refreshes the list', async () => {
      mockApi.post.mockResolvedValue({ data: banAck() });
      const before = listGetCount();

      await wrapper.find('[data-testid="ban-submit"]').trigger('click');
      await dialogInput(wrapper).setValue(NEW_IP);
      await wrapper.find('form').trigger('submit');
      await flushPromises();

      expect(mockApi.post).toHaveBeenCalledWith(LIST_URL, {
        ip_address: NEW_IP,
        reason: 'credential stuffing',
      });
      expect(showMock).toHaveBeenCalledWith('web.admin.bannedIps.ban.success', 'success');
      // Dialog closed (input gone), the ban form collapsed, and the list re-fetched.
      expect(dialogInput(wrapper).exists()).toBe(false);
      expect(wrapper.find('[data-testid="ban-form"]').exists()).toBe(false);
      expect(listGetCount()).toBe(before + 1);
    });

    it('does NOT POST when submitted without a matching token', async () => {
      mockApi.post.mockResolvedValue({ data: banAck() });
      await wrapper.find('[data-testid="ban-submit"]').trigger('click');
      await dialogInput(wrapper).setValue('wrong');
      await wrapper.find('form').trigger('submit');
      await flushPromises();

      expect(mockApi.post).not.toHaveBeenCalled();
      expect(showMock).not.toHaveBeenCalled();
    });

    it('surfaces a 4xx in the dialog and stays open on failure', async () => {
      mockApi.post.mockRejectedValue(axiosError(422, { error: 'IP already banned' }));

      await wrapper.find('[data-testid="ban-submit"]').trigger('click');
      await dialogInput(wrapper).setValue(NEW_IP);
      await wrapper.find('form').trigger('submit');
      await flushPromises();

      expect(wrapper.find('[role="alert"]').text()).toContain('IP already banned');
      expect(showMock).not.toHaveBeenCalled();
      // Dialog stays put for retry/cancel.
      expect(dialogInput(wrapper).exists()).toBe(true);
    });
  });

  // ---- Guarded unban (D4) ---------------------------------------------------

  describe('unban — typed-confirmation gate', () => {
    beforeEach(async () => {
      mockApi.get.mockResolvedValue({ data: bannedIpsPayload() });
      wrapper = mountView(pinia);
      await flushPromises();
    });

    it('opens the dialog from the row action, gated until the IP is retyped', async () => {
      await wrapper.find(`[data-testid="unban-${EXISTING_IP}"]`).trigger('click');
      await flushPromises();

      expect(dialogInput(wrapper).exists()).toBe(true);
      expect(dialogSubmit(wrapper).attributes('disabled')).toBeDefined();

      await dialogInput(wrapper).setValue(EXISTING_IP);
      expect(dialogSubmit(wrapper).attributes('disabled')).toBeUndefined();
    });

    it('DELETEs the ban, notifies and refreshes the list on confirm', async () => {
      mockApi.delete.mockResolvedValue({ data: unbanAck() });
      const before = listGetCount();

      await wrapper.find(`[data-testid="unban-${EXISTING_IP}"]`).trigger('click');
      await dialogInput(wrapper).setValue(EXISTING_IP);
      await wrapper.find('form').trigger('submit');
      await flushPromises();

      expect(mockApi.delete).toHaveBeenCalledWith(`${LIST_URL}/${EXISTING_IP}`);
      expect(showMock).toHaveBeenCalledWith('web.admin.bannedIps.unban.success', 'success');
      expect(dialogInput(wrapper).exists()).toBe(false);
      expect(listGetCount()).toBe(before + 1);
    });

    it('surfaces a 4xx in the dialog and does not refresh on failure', async () => {
      mockApi.delete.mockRejectedValue(axiosError(422, { error: 'IP not currently banned' }));
      const before = listGetCount();

      await wrapper.find(`[data-testid="unban-${EXISTING_IP}"]`).trigger('click');
      await dialogInput(wrapper).setValue(EXISTING_IP);
      await wrapper.find('form').trigger('submit');
      await flushPromises();

      expect(wrapper.find('[role="alert"]').text()).toContain('IP not currently banned');
      expect(showMock).not.toHaveBeenCalled();
      expect(listGetCount()).toBe(before);
    });
  });
});
