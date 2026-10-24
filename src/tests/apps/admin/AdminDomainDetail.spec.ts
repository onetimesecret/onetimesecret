// src/tests/apps/admin/AdminDomainDetail.spec.ts

import { flushPromises, mount, RouterLinkStub, VueWrapper } from '@vue/test-utils';
import { AxiosError } from 'axios';
import { createPinia, setActivePinia } from 'pinia';
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

const pushMock = vi.fn();
vi.mock('vue-router', () => ({
  useRouter: () => ({ push: pushMock }),
  useRoute: () => ({ params: { id: 'cd_abc123' } }),
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

// Render the HeadlessUI confirm dialog synchronously and in place.
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
import { useAdminDomains } from '@/apps/admin/stores/useAdminDomains';
import AdminDomainDetail from '@/apps/admin/views/AdminDomainDetail.vue';
import { startElevated } from '@tests/apps/admin/support/elevation';
import { createTestI18n } from '@tests/setup';

const i18n = createTestI18n();

const EXTID = 'cd_abc123';
/**
 * The hostname the server gates every applying domain verb on (#4326) — an
 * identifier the URL (an extid) does not carry. The typed-confirm dialog still
 * asks for the extid; the header is what the server checks.
 */
const CONFIRM_HEADERS = {
  headers: { 'X-OTS-Confirm': encodeURIComponent('secrets.example.com') },
};
const DETAIL_URL = `/api/colonel/domains/${EXTID}`;

function detailPayload(overrides: Record<string, unknown> = {}) {
  return {
    shrimp: '',
    record: {
      domain_id: 'cd1',
      extid: EXTID,
      display_domain: 'secrets.example.com',
      base_domain: 'example.com',
      subdomain: 'secrets',
      trd: 'secrets',
      tld: 'com',
      status: null,
      verification_state: 'pending',
      verified: false,
      resolving: false,
      ready: false,
      is_apex: false,
      txt_validation_host: '_ots.secrets',
      txt_validation_value: 'ots=abc123',
      created: 1700000000,
      updated: 1700003600,
      ...overrides,
    },
    details: { cluster: { proxy_ip: '203.0.113.5', proxy_host: 'proxy.example' } },
  };
}

function verifyAck(current_state = 'pending') {
  return {
    shrimp: '',
    record: {
      domain_id: 'cd1',
      extid: EXTID,
      display_domain: 'secrets.example.com',
      verification_state: current_state,
      verified: current_state === 'verified',
      resolving: current_state !== 'pending',
      ready: current_state === 'verified',
      updated: 1700009999,
    },
    details: {
      previous_state: 'pending',
      current_state,
      changed: true,
      dns_validated: current_state === 'verified',
      ssl_ready: current_state === 'verified',
      is_resolving: current_state !== 'pending',
      error: null,
      message: 'Domain verification completed',
    },
  };
}

function overrideAck(verified: boolean, resolving: boolean) {
  return {
    shrimp: '',
    record: {
      domain_id: 'cd1',
      extid: EXTID,
      display_domain: 'secrets.example.com',
      verification_state: verified ? 'verified' : resolving ? 'resolving' : 'pending',
      verified,
      verified_by_override: false,
      resolving,
      ready: verified && resolving,
      updated: 1700009999,
    },
    details: {
      previous_verified: verified,
      previous_resolving: !resolving,
      current_verified: verified,
      current_resolving: resolving,
      verified_changed: false,
      resolving_changed: true,
      message: 'Domain verification flags overridden',
    },
  };
}

function probeAck() {
  return {
    shrimp: '',
    record: { extid: EXTID, display_domain: 'secrets.example.com' },
    details: {
      timestamp: '2026-07-24T00:00:00Z',
      domain: 'secrets.example.com',
      url: 'https://secrets.example.com',
      http: { status_code: 200, status_message: 'OK', success: true },
      ssl: { valid: true, issuer: "Let's Encrypt", not_after: '2026-10-01', days_until_expiry: 68 },
      health: 'healthy',
    },
  };
}

function removeAck(dry_run: boolean, sender_cleanup: string | null = dry_run ? null : 'deleted') {
  return {
    shrimp: '',
    record: {
      deleted: !dry_run,
      domain_id: 'cd1',
      extid: EXTID,
      display_domain: 'secrets.example.com',
    },
    details: {
      status: dry_run ? 'planned' : 'removed',
      dry_run,
      org_id: 'org1',
      org_name: 'Acme',
      sender_cleanup,
    },
  };
}

function transferAck(dry_run: boolean) {
  return {
    shrimp: '',
    record: { domain_id: 'cd1', extid: EXTID, display_domain: 'secrets.example.com' },
    details: {
      status: dry_run ? 'planned' : 'transferred',
      dry_run,
      from_org_id: 'org1',
      from_org_name: 'Acme',
      to_org_id: 'org_new',
      to_org_name: 'Globex',
    },
  };
}

function repairAck(dry_run: boolean) {
  return {
    shrimp: '',
    record: { domain_id: 'cd1', extid: EXTID, display_domain: 'secrets.example.com' },
    details: {
      status: 'planned',
      dry_run,
      issues: ['organization is missing the domain in its relation set'],
      repairs_applied: dry_run ? [] : ['reattached domain to organization'],
    },
  };
}

const dialogInput = (w: VueWrapper) => w.find('#admin-confirm-input');
const dialogSubmit = (w: VueWrapper) => w.find('[data-testid="admin-confirm-submit"]');

describe('AdminDomainDetail', () => {
  let wrapper: VueWrapper;
  let pinia: ReturnType<typeof createPinia>;

  const mountView = () =>
    mount(AdminDomainDetail, {
      props: { id: EXTID },
      global: {
        plugins: [pinia, i18n],
        // DomainConfigsSection owns its own /configs fetch and has its own
        // spec (DomainConfigsSection.spec.ts); stub it here so this spec's
        // request-count assertions stay about the detail read.
        stubs: { RouterLink: RouterLinkStub, DomainConfigsSection: true },
      },
    });

  beforeEach(() => {
    pinia = createPinia();
    setActivePinia(pinia);
    vi.clearAllMocks();
    // A live step-up window: these examples are about the dialogs, which a
    // tier-1 opener only shows once elevated (see support/elevation.ts).
    startElevated();
    mockApi.get.mockResolvedValue({ data: detailPayload() });
  });
  afterEach(() => wrapper?.unmount());

  describe('opener lifetime and concurrency', () => {
    beforeEach(() => __resetColonelElevationState({ statusRead: true }));

    async function requestRemove(): Promise<void> {
      wrapper = mountView();
      await flushPromises();
      mockApi.delete.mockResolvedValue({ data: removeAck(true) });
      await wrapper.find('[data-testid="remove-preview"]').trigger('click');
      await flushPromises();
      await wrapper.find('[data-testid="remove-button"]').trigger('click');
      await flushPromises();
      expect(useColonelElevation().promptOpen.value).toBe(true);
      mockApi.delete.mockClear();
    }

    it.each([false, true])(
      'drops the remove opener after a resource switch (return: %s)',
      async (returnToOriginal) => {
        await requestRemove();
        await wrapper.setProps({ id: 'cd_other' });
        if (returnToOriginal) await wrapper.setProps({ id: EXTID });
        await flushPromises();
        useColonelElevation().resolvePrompt(true);
        await flushPromises();

        expect(dialogInput(wrapper).exists()).toBe(false);
        expect(mockApi.delete).not.toHaveBeenCalled();
      }
    );

    it('rejects competing actions during elevation and while the dialog is open', async () => {
      await requestRemove();
      const verify = wrapper.find('[data-testid="verify-button"]');
      expect(verify.attributes('disabled')).toBeDefined();
      verify.element.dispatchEvent(new MouseEvent('click', { bubbles: true }));
      await flushPromises();
      expect(dialogSubmit(wrapper).exists()).toBe(false);

      useColonelElevation().resolvePrompt(true);
      await flushPromises();
      await dialogInput(wrapper).setValue(EXTID);
      verify.element.dispatchEvent(new MouseEvent('click', { bubbles: true }));
      await flushPromises();
      expect(dialogInput(wrapper).exists()).toBe(true);
      expect((dialogInput(wrapper).element as HTMLInputElement).value).toBe(EXTID);
      expect(mockApi.post).not.toHaveBeenCalled();
    });

    it('rechecks the remove preview after elevation', async () => {
      await requestRemove();
      const noPlan = removeAck(true);
      noPlan.details.status = 'removed';
      mockApi.delete.mockResolvedValue({ data: noPlan });
      await wrapper.find('[data-testid="remove-preview"]').trigger('click');
      await flushPromises();
      useColonelElevation().resolvePrompt(true);
      await flushPromises();

      expect(dialogInput(wrapper).exists()).toBe(false);
    });

    it('opens a tier-2 repair without prompting', async () => {
      wrapper = mountView();
      await flushPromises();
      mockApi.post.mockResolvedValue({ data: repairAck(true) });
      await wrapper.find('[data-testid="repair-preview"]').trigger('click');
      await flushPromises();
      await wrapper.find('[data-testid="repair-apply"]').trigger('click');

      expect(useColonelElevation().promptOpen.value).toBe(false);
      expect(dialogInput(wrapper).exists()).toBe(true);
    });
  });

  describe('load states', () => {
    it('fetches the domain by public id and renders the read-out', async () => {
      wrapper = mountView();
      await flushPromises();

      expect(mockApi.get).toHaveBeenCalledWith(DETAIL_URL, undefined);
      const content = wrapper.find('[data-testid="detail-content"]');
      expect(content.exists()).toBe(true);
      expect(content.text()).toContain('secrets.example.com');
      // Identity fields + the reused DNS panel both render.
      expect(wrapper.find('[data-testid="profile-publicId"]').text()).toContain(EXTID);
      expect(wrapper.find('[data-testid="dns-details"]').exists()).toBe(true);
    });

    it('renders the not-found state for a 404', async () => {
      mockApi.get.mockRejectedValue(axiosError(404, { error: 'Domain not found' }));
      wrapper = mountView();
      await flushPromises();

      expect(wrapper.find('[data-testid="detail-not-found"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="detail-content"]').exists()).toBe(false);
    });

    it('renders the error state and retries on a network failure', async () => {
      mockApi.get.mockRejectedValue(new Error('Network Error'));
      wrapper = mountView();
      await flushPromises();

      const banner = wrapper.find('[data-testid="detail-error"]');
      expect(banner.exists()).toBe(true);

      mockApi.get.mockResolvedValue({ data: detailPayload() });
      await banner.find('button').trigger('click');
      await flushPromises();
      expect(wrapper.find('[data-testid="detail-content"]').exists()).toBe(true);
    });
  });

  describe('owning organization', () => {
    function organizationLink(w: VueWrapper) {
      return w
        .findAllComponents(RouterLinkStub)
        .find((link) => link.attributes('data-testid') === 'organization-link');
    }

    it('links to the organization by its public id when the list row is cached', async () => {
      const store = useAdminDomains();
      // The store's row cache carries the owner over from the list the
      // operator navigated from.
      store.rowIndex[EXTID] = {
        extid: EXTID,
        org_id: 'org_internal_1',
        org_extid: 'on_acme',
        org_name: 'Acme',
      } as never;

      wrapper = mountView();
      await flushPromises();

      const link = organizationLink(wrapper);
      expect(link).toBeDefined();
      expect(link!.props('to')).toEqual({
        name: 'AdminOrganizationDetail',
        params: { id: 'on_acme' },
      });
      const section = wrapper.find('[data-testid="organization-section"]').text();
      expect(section).toContain('Acme');
      expect(section).toContain('on_acme');
      // The internal org id is neither linked nor shown.
      expect(section).not.toContain('org_internal_1');
      expect(wrapper.find('[data-testid="organization-unknown"]').exists()).toBe(false);
    });

    it('links to the organization on a cold deep link from the detail record', async () => {
      mockApi.get.mockResolvedValue({
        data: detailPayload({
          org_id: 'org_internal_2',
          org_extid: 'on_globex',
          org_name: 'Globex',
        }),
      });

      wrapper = mountView();
      await flushPromises();

      expect(organizationLink(wrapper)!.props('to')).toEqual({
        name: 'AdminOrganizationDetail',
        params: { id: 'on_globex' },
      });
    });

    it('does not link by the internal org id when no public id is known', async () => {
      const store = useAdminDomains();
      store.rowIndex[EXTID] = { extid: EXTID, org_id: 'org_internal_3', org_name: 'Acme' } as never;

      wrapper = mountView();
      await flushPromises();

      expect(organizationLink(wrapper)).toBeUndefined();
      expect(wrapper.find('[data-testid="organization-unknown"]').exists()).toBe(true);
    });

    it('says so honestly when the owner is unknown', async () => {
      wrapper = mountView();
      await flushPromises();

      expect(wrapper.find('[data-testid="organization-unknown"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="organization-link"]').exists()).toBe(false);
    });
  });

  describe('verify', () => {
    it('confirms in one click, reports the honest state, and refreshes', async () => {
      mockApi.post.mockResolvedValue({ data: verifyAck('pending') });
      wrapper = mountView();
      await flushPromises();
      expect(mockApi.get).toHaveBeenCalledTimes(1);

      await wrapper.find('[data-testid="verify-button"]').trigger('click');
      await flushPromises();

      // Reversible verb: no typed token, so confirm is enabled immediately.
      expect(dialogSubmit(wrapper).attributes('disabled')).toBeUndefined();
      await wrapper.find('form').trigger('submit');
      await flushPromises();

      expect(mockApi.post).toHaveBeenCalledWith(`${DETAIL_URL}/verify`);
      // A pending result is surfaced as info, never faked as success.
      expect(showMock).toHaveBeenCalledTimes(1);
      expect(showMock.mock.calls[0][1]).toBe('info');
      expect(mockApi.get).toHaveBeenCalledTimes(2);
    });

    it('keeps a 4xx failure inside the dialog and does not toast', async () => {
      mockApi.post.mockRejectedValue(axiosError(422, { error: 'DNS lookup failed' }));
      wrapper = mountView();
      await flushPromises();

      await wrapper.find('[data-testid="verify-button"]').trigger('click');
      await flushPromises();
      await wrapper.find('form').trigger('submit');
      await flushPromises();

      expect(wrapper.find('[data-testid="admin-confirm-dialog"]').text()).toContain(
        'DNS lookup failed'
      );
      expect(showMock).not.toHaveBeenCalled();
    });
  });

  describe('override verification', () => {
    it('omits verified when changing only resolving on an already-verified domain', async () => {
      mockApi.get.mockResolvedValue({
        data: detailPayload({
          verification_state: 'verified',
          verified: true,
          verified_by_override: false,
          resolving: false,
        }),
      });
      mockApi.post.mockResolvedValue({ data: overrideAck(true, true) });
      wrapper = mountView();
      await flushPromises();

      await wrapper.find('[data-testid="override-button"]').trigger('click');
      const checkboxes = wrapper
        .find('[data-testid="override-form"]')
        .findAll('input[type="checkbox"]');
      expect((checkboxes[0].element as HTMLInputElement).checked).toBe(true);
      await checkboxes[1].setValue(true);
      await wrapper.find('[data-testid="override-apply"]').trigger('click');
      await flushPromises();

      expect(mockApi.post).toHaveBeenCalledWith(
        `${DETAIL_URL}/override`,
        { resolving: true },
        CONFIRM_HEADERS
      );
    });

    it('does not submit an unchanged verified domain', async () => {
      mockApi.get.mockResolvedValue({
        data: detailPayload({
          verification_state: 'verified',
          verified: true,
          verified_by_override: false,
          resolving: true,
        }),
      });
      wrapper = mountView();
      await flushPromises();

      await wrapper.find('[data-testid="override-button"]').trigger('click');
      await wrapper.find('[data-testid="override-apply"]').trigger('click');
      await flushPromises();

      expect(mockApi.post).not.toHaveBeenCalled();
    });
  });

  describe('probe', () => {
    it('runs a read-only probe and renders the health classification', async () => {
      mockApi.get.mockImplementation((url: string) =>
        Promise.resolve({
          data: url.endsWith('/probe') ? probeAck() : detailPayload(),
        })
      );
      wrapper = mountView();
      await flushPromises();

      await wrapper.find('[data-testid="probe-button"]').trigger('click');
      await flushPromises();

      expect(mockApi.get).toHaveBeenCalledWith(`${DETAIL_URL}/probe`, undefined);
      expect(wrapper.find('[data-testid="probe-health"]').text()).toBe('healthy');
      // No confirmation and no toast: a probe mutates nothing.
      expect(showMock).not.toHaveBeenCalled();
    });
  });

  describe('remove (typed-confirm)', () => {
    it('previews with dry_run=true before anything destructive is offered', async () => {
      mockApi.delete.mockResolvedValue({ data: removeAck(true) });
      wrapper = mountView();
      await flushPromises();

      await wrapper.find('[data-testid="remove-preview"]').trigger('click');
      await flushPromises();

      // A preview is EXEMPT server-side, so it sends no confirmation header.
      expect(mockApi.delete).toHaveBeenCalledWith(`${DETAIL_URL}?dry_run=true`, undefined);
      const plan = wrapper.find('[data-testid="remove-plan"]');
      expect(plan.exists()).toBe(true);
      expect(plan.text()).toContain('Acme');
    });

    // The apply must not be reachable cold: the typed-confirm dialog would ask
    // for the extid without ever naming the org that loses the domain.
    it('offers no apply button until a preview says planned', async () => {
      wrapper = mountView();
      await flushPromises();

      expect(wrapper.find('[data-testid="remove-button"]').exists()).toBe(false);
      expect(mockApi.delete).not.toHaveBeenCalled();
    });

    // A dry run always answers `planned`; `removed` here means the ack drifted
    // from the request, which is not a licence to offer the apply.
    it('keeps the apply button hidden when the preview is not planned', async () => {
      const drifted = removeAck(true);
      drifted.details.status = 'removed';
      mockApi.delete.mockResolvedValue({ data: drifted });
      wrapper = mountView();
      await flushPromises();

      await wrapper.find('[data-testid="remove-preview"]').trigger('click');
      await flushPromises();

      expect(wrapper.find('[data-testid="remove-plan"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="remove-button"]').exists()).toBe(false);
    });

    it('gates the apply on the retyped public id, then deletes and returns to the list', async () => {
      mockApi.delete.mockImplementation((url: string) =>
        Promise.resolve({ data: removeAck(url.includes('dry_run=true')) })
      );
      wrapper = mountView();
      await flushPromises();

      // Preview first — the apply button only exists behind a `planned` plan.
      await wrapper.find('[data-testid="remove-preview"]').trigger('click');
      await flushPromises();

      await wrapper.find('[data-testid="remove-button"]').trigger('click');
      await flushPromises();

      expect(dialogSubmit(wrapper).attributes('disabled')).toBeDefined();
      await dialogInput(wrapper).setValue(EXTID);
      expect(dialogSubmit(wrapper).attributes('disabled')).toBeUndefined();

      await wrapper.find('form').trigger('submit');
      await flushPromises();

      // The apply MUST say dry_run=false — the endpoint defaults it to true.
      expect(mockApi.delete).toHaveBeenCalledWith(`${DETAIL_URL}?dry_run=false`, CONFIRM_HEADERS);
      expect(showMock).toHaveBeenCalledWith('web.admin.domains.actions.remove.success', 'success');
      expect(pushMock).toHaveBeenCalledWith({ name: 'AdminDomains' });
    });

    // The record is gone, so the view still returns to the list, but it must
    // not toast a clean removal while the provider sender identity may remain.
    it('warns instead of reporting success when the sender cleanup failed', async () => {
      mockApi.delete.mockImplementation((url: string) => {
        const dryRun = url.includes('dry_run=true');
        return Promise.resolve({ data: removeAck(dryRun, dryRun ? null : 'failed') });
      });
      wrapper = mountView();
      await flushPromises();

      await wrapper.find('[data-testid="remove-preview"]').trigger('click');
      await flushPromises();
      await wrapper.find('[data-testid="remove-button"]').trigger('click');
      await flushPromises();
      await dialogInput(wrapper).setValue(EXTID);
      await wrapper.find('form').trigger('submit');
      await flushPromises();

      expect(showMock).toHaveBeenCalledWith(
        'web.admin.domains.actions.remove.senderCleanupFailed',
        'warning'
      );
      expect(showMock).not.toHaveBeenCalledWith(
        'web.admin.domains.actions.remove.success',
        'success'
      );
      expect(pushMock).toHaveBeenCalledWith({ name: 'AdminDomains' });
    });
  });

  describe('transfer (preview then typed-confirm)', () => {
    it('previews with dry_run=true and applies with dry_run=false', async () => {
      mockApi.post.mockImplementation((_url: string, body: { dry_run: boolean }) =>
        Promise.resolve({ data: transferAck(body.dry_run) })
      );
      wrapper = mountView();
      await flushPromises();

      await wrapper.find('[data-testid="transfer-toorg-input"]').setValue('org_new');
      await wrapper.find('[data-testid="transfer-preview"]').trigger('click');
      await flushPromises();

      expect(mockApi.post).toHaveBeenCalledWith(
        `${DETAIL_URL}/transfer`,
        { dry_run: true, to_org: 'org_new' },
        undefined
      );
      expect(wrapper.find('[data-testid="transfer-plan"]').text()).toContain('Globex');

      await wrapper.find('[data-testid="transfer-apply"]').trigger('click');
      await flushPromises();
      await dialogInput(wrapper).setValue(EXTID);
      await wrapper.find('form').trigger('submit');
      await flushPromises();

      expect(mockApi.post).toHaveBeenCalledWith(
        `${DETAIL_URL}/transfer`,
        { dry_run: false, to_org: 'org_new' },
        CONFIRM_HEADERS
      );
      expect(showMock).toHaveBeenCalledWith(
        'web.admin.domains.actions.transfer.success',
        'success'
      );
    });
  });

  describe('repair (preview then typed-confirm)', () => {
    it('previews the plan and only offers the apply when repairs are planned', async () => {
      mockApi.post.mockImplementation((_url: string, body: { dry_run: boolean }) =>
        Promise.resolve({ data: repairAck(body.dry_run) })
      );
      wrapper = mountView();
      await flushPromises();

      expect(wrapper.find('[data-testid="repair-apply"]').exists()).toBe(false);

      await wrapper.find('[data-testid="repair-preview"]').trigger('click');
      await flushPromises();

      expect(mockApi.post).toHaveBeenCalledWith(
        `${DETAIL_URL}/repair`,
        { dry_run: true },
        undefined
      );
      expect(wrapper.find('[data-testid="repair-status"]').text()).toBe('planned');

      await wrapper.find('[data-testid="repair-apply"]').trigger('click');
      await flushPromises();
      await dialogInput(wrapper).setValue(EXTID);
      await wrapper.find('form').trigger('submit');
      await flushPromises();

      expect(mockApi.post).toHaveBeenCalledWith(
        `${DETAIL_URL}/repair`,
        { dry_run: false },
        CONFIRM_HEADERS
      );
      expect(showMock).toHaveBeenCalledWith('web.admin.domains.actions.repair.success', 'success');
    });

    it('passes the org id only when the operator supplied one', async () => {
      mockApi.post.mockResolvedValue({ data: repairAck(true) });
      wrapper = mountView();
      await flushPromises();

      await wrapper.find('[data-testid="repair-orgid-input"]').setValue('org_rescue');
      await wrapper.find('[data-testid="repair-preview"]').trigger('click');
      await flushPromises();

      expect(mockApi.post).toHaveBeenCalledWith(
        `${DETAIL_URL}/repair`,
        { dry_run: true, org_id: 'org_rescue' },
        undefined
      );
    });
  });
});
