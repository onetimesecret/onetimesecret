// src/tests/apps/admin/AdminDomainToolbox.spec.ts

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
  formatDisplayDateTime: (d: Date) => `DT:${d.toISOString?.() ?? d}`,
}));

vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="o-icon" :data-name="name" />',
    props: ['collection', 'name', 'class', 'size', 'aria-label'],
  },
}));

// Render the HeadlessUI dialog markup synchronously (mirrors AdminSessions.spec).
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

import AdminDomainToolbox from '@/apps/admin/views/AdminDomainToolbox.vue';
import { createTestI18n } from '@tests/setup';

const i18n = createTestI18n();

const ORPHAN_URL = '/api/colonel/domains/orphaned';
const EXTID = 'cd_ext_1';

function orphanedPayload(rows = [orphanRow()]) {
  return {
    shrimp: '',
    record: {},
    details: {
      domains: rows,
      pagination: { page: 1, per_page: 50, total_count: rows.length, total_pages: 1 },
    },
  };
}

function orphanRow(overrides: Record<string, unknown> = {}) {
  return {
    domain_id: 'cd_1',
    extid: EXTID,
    display_domain: 'orphan.example.com',
    verification_state: 'pending',
    verified: false,
    created: 1700000000,
    ...overrides,
  };
}

function probePayload() {
  return {
    shrimp: '',
    record: { extid: EXTID, display_domain: 'orphan.example.com' },
    details: {
      timestamp: '2026-07-07T00:00:00Z',
      domain: 'orphan.example.com',
      url: 'https://orphan.example.com',
      http: { status_code: 200, status_message: 'OK', success: true },
      ssl: { valid: true, days_until_expiry: 90, expired: false },
      health: 'healthy',
    },
  };
}

function repairPlanPayload(status = 'planned', issues = ['not in collection']) {
  return {
    shrimp: '',
    record: { domain_id: 'cd_1', extid: EXTID, display_domain: 'orphan.example.com' },
    details: { status, dry_run: status === 'planned', issues, repairs_applied: [] },
  };
}

function transferPlanPayload(status = 'planned') {
  return {
    shrimp: '',
    record: { domain_id: 'cd_1', extid: EXTID, display_domain: 'orphan.example.com' },
    details: {
      status,
      dry_run: status === 'planned',
      from_org_id: 'on_src',
      from_org_name: 'Source Org',
      to_org_id: 'on_dest',
      to_org_name: 'Dest Org',
    },
  };
}

const mountView = (pinia: ReturnType<typeof createPinia>) =>
  mount(AdminDomainToolbox, { global: { plugins: [pinia, i18n] } });

const dialogInput = (w: VueWrapper) => w.find('#admin-confirm-input');
const dialogSubmit = (w: VueWrapper) => w.find('[data-testid="admin-confirm-submit"]');

describe('AdminDomainToolbox (orphaned + probe + repair + transfer — ticket #43)', () => {
  let wrapper: VueWrapper;
  let pinia: ReturnType<typeof createPinia>;

  beforeEach(() => {
    pinia = createPinia();
    setActivePinia(pinia);
    vi.clearAllMocks();
    // Default: the orphaned-scan GET on mount succeeds.
    mockApi.get.mockImplementation((url: string) =>
      url === ORPHAN_URL
        ? Promise.resolve({ data: orphanedPayload() })
        : Promise.resolve({ data: probePayload() })
    );
  });
  afterEach(() => {
    wrapper?.unmount();
  });

  // ---- Orphaned scan --------------------------------------------------------

  it('fetches the orphaned scan on mount and renders a row', async () => {
    wrapper = mountView(pinia);
    await flushPromises();

    expect(mockApi.get).toHaveBeenCalledWith(ORPHAN_URL, {
      params: { page: 1, per_page: 50 },
    });
    const table = wrapper.find('[data-testid="orphaned-table"]');
    expect(table.exists()).toBe(true);
    expect(table.text()).toContain('orphan.example.com');
  });

  it('shows the orphaned error banner + retry on a network failure', async () => {
    mockApi.get.mockRejectedValueOnce(new Error('Network Error'));
    wrapper = mountView(pinia);
    await flushPromises();
    expect(wrapper.find('[data-testid="orphaned-error"]').exists()).toBe(true);
  });

  // ---- Probe (read-only) ----------------------------------------------------

  it('probes a domain and renders the health badge', async () => {
    wrapper = mountView(pinia);
    await flushPromises();

    await wrapper.find('[data-testid="probe-extid-input"]').setValue(EXTID);
    await wrapper.find('[data-testid="probe-run"]').trigger('click');
    await flushPromises();

    expect(mockApi.get).toHaveBeenCalledWith(`/api/colonel/domains/${EXTID}/probe`);
    expect(wrapper.find('[data-testid="probe-health"]').text()).toBe('healthy');
  });

  it('seeds the probe + repair extid from an orphaned row action', async () => {
    wrapper = mountView(pinia);
    await flushPromises();

    await wrapper.find(`[data-testid="orphaned-repair-${EXTID}"]`).trigger('click');
    expect(
      (wrapper.find('[data-testid="repair-extid-input"]').element as HTMLInputElement).value
    ).toBe(EXTID);
  });

  // ---- Repair (guarded: dry-run preview → typed-confirm apply) --------------

  describe('repair', () => {
    it('previews a repair plan (dry_run) and lists the issues', async () => {
      wrapper = mountView(pinia);
      await flushPromises();

      mockApi.post.mockResolvedValueOnce({ data: repairPlanPayload() });
      await wrapper.find('[data-testid="repair-extid-input"]').setValue(EXTID);
      await wrapper.find('[data-testid="repair-preview"]').trigger('click');
      await flushPromises();

      expect(mockApi.post).toHaveBeenCalledWith(`/api/colonel/domains/${EXTID}/repair`, {
        dry_run: true,
      });
      expect(wrapper.find('[data-testid="repair-status"]').text()).toBe('planned');
      expect(wrapper.find('[data-testid="repair-plan"]').text()).toContain('not in collection');
    });

    it('applies the repair behind a typed-confirmation gate', async () => {
      wrapper = mountView(pinia);
      await flushPromises();

      mockApi.post.mockResolvedValueOnce({ data: repairPlanPayload() });
      await wrapper.find('[data-testid="repair-extid-input"]').setValue(EXTID);
      await wrapper.find('[data-testid="repair-preview"]').trigger('click');
      await flushPromises();

      // Open the confirm dialog; submit is gated until the extid is retyped.
      await wrapper.find('[data-testid="repair-apply"]').trigger('click');
      expect(dialogSubmit(wrapper).attributes('disabled')).toBeDefined();
      await dialogInput(wrapper).setValue('wrong');
      expect(dialogSubmit(wrapper).attributes('disabled')).toBeDefined();
      await dialogInput(wrapper).setValue(EXTID);
      expect(dialogSubmit(wrapper).attributes('disabled')).toBeUndefined();

      mockApi.post.mockResolvedValueOnce({ data: repairPlanPayload('repaired', []) });
      await wrapper.find('form').trigger('submit');
      await flushPromises();

      // Apply POST carries dry_run:false.
      expect(mockApi.post).toHaveBeenLastCalledWith(`/api/colonel/domains/${EXTID}/repair`, {
        dry_run: false,
      });
      expect(showMock).toHaveBeenCalledWith('web.admin.domaintoolbox.repair.success', 'success');
    });

    it('surfaces a 4xx in the repair dialog and stays open', async () => {
      wrapper = mountView(pinia);
      await flushPromises();

      mockApi.post.mockResolvedValueOnce({ data: repairPlanPayload() });
      await wrapper.find('[data-testid="repair-extid-input"]').setValue(EXTID);
      await wrapper.find('[data-testid="repair-preview"]').trigger('click');
      await flushPromises();

      await wrapper.find('[data-testid="repair-apply"]').trigger('click');
      await dialogInput(wrapper).setValue(EXTID);
      mockApi.post.mockRejectedValueOnce(axiosError(404, { error: 'Domain not found' }));
      await wrapper.find('form').trigger('submit');
      await flushPromises();

      expect(wrapper.find('[role="alert"]').text()).toContain('Domain not found');
      expect(showMock).not.toHaveBeenCalled();
    });
  });

  // ---- Transfer (guarded) ---------------------------------------------------

  describe('transfer', () => {
    async function preview(w: VueWrapper) {
      mockApi.post.mockResolvedValueOnce({ data: transferPlanPayload() });
      await w.find('[data-testid="transfer-extid-input"]').setValue(EXTID);
      await w.find('[data-testid="transfer-toorg-input"]').setValue('on_dest');
      await w.find('[data-testid="transfer-preview"]').trigger('click');
      await flushPromises();
    }

    it('previews a transfer plan (dry_run) with from/to orgs', async () => {
      wrapper = mountView(pinia);
      await flushPromises();
      await preview(wrapper);

      expect(mockApi.post).toHaveBeenCalledWith(`/api/colonel/domains/${EXTID}/transfer`, {
        dry_run: true,
        to_org: 'on_dest',
      });
      const plan = wrapper.find('[data-testid="transfer-plan"]');
      expect(plan.text()).toContain('Dest Org');
      expect(plan.text()).toContain('Source Org');
    });

    it('applies the transfer behind a typed-confirmation gate', async () => {
      wrapper = mountView(pinia);
      await flushPromises();
      await preview(wrapper);

      await wrapper.find('[data-testid="transfer-apply"]').trigger('click');
      expect(dialogSubmit(wrapper).attributes('disabled')).toBeDefined();
      await dialogInput(wrapper).setValue(EXTID);
      expect(dialogSubmit(wrapper).attributes('disabled')).toBeUndefined();

      mockApi.post.mockResolvedValueOnce({ data: transferPlanPayload('transferred') });
      await wrapper.find('form').trigger('submit');
      await flushPromises();

      expect(mockApi.post).toHaveBeenLastCalledWith(`/api/colonel/domains/${EXTID}/transfer`, {
        dry_run: false,
        to_org: 'on_dest',
      });
      expect(showMock).toHaveBeenCalledWith('web.admin.domaintoolbox.transfer.success', 'success');
    });
  });
});
