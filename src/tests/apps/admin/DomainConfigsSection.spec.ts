// src/tests/apps/admin/DomainConfigsSection.spec.ts

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
  put: vi.fn(),
  delete: vi.fn(),
};
vi.mock('@/shared/composables/useApi', () => ({ useApi: () => mockApi }));

const showMock = vi.fn();
vi.mock('@/shared/stores/notificationsStore', () => ({
  useNotificationsStore: () => ({ show: showMock }),
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

// Render the confirm dialog synchronously in jsdom (same shim the kit test uses).
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

import DomainConfigsSection from '@/apps/admin/components/domains/DomainConfigsSection.vue';
import { useAdminDomains } from '@/apps/admin/stores/useAdminDomains';
import { createTestI18n } from '@tests/setup';

const i18n = createTestI18n();

const EXTID = 'cd_abc123';
const CONFIGS_URL = `/api/colonel/domains/${EXTID}/configs`;
const ALL_KINDS = ['signin', 'signup', 'homepage', 'api', 'incoming', 'sso', 'mailer'] as const;

function envelopeRecord() {
  return { domain_id: 'cd1', extid: EXTID, display_domain: 'secrets.example.com' };
}

function signinConfig(overrides: Record<string, unknown> = {}) {
  return {
    domain_id: 'cd1',
    enabled: true,
    signin_enabled: true,
    email_auth_enabled: false,
    sso_enabled: false,
    restrict_to: null,
    created: 1700000000,
    updated: 1700003600,
    ...overrides,
  };
}

function homepageConfig() {
  return {
    domain_id: 'cd1',
    enabled: false,
    secrets_mode: 'create',
    disabled_homepage_variant: null,
    created: 1700000000,
    updated: null,
  };
}

function incomingConfig() {
  return {
    domain_id: 'cd1',
    enabled: true,
    ready: false,
    recipients: [{ email: 'security-team@example.com', name: 'Sec' }],
    created: 1700000000,
    updated: null,
  };
}

function ssoConfig() {
  return {
    domain_id: 'cd1',
    enabled: true,
    provider_type: 'oidc',
    display_name: 'Corp SSO',
    issuer: 'https://id.example.com',
    tenant_id: null,
    has_client_id: true,
    has_client_secret: true,
    allowed_domains: ['example.com'],
    enforce_sso_only: false,
    grant_org_scope: false,
    created: 1700000000,
    updated: null,
  };
}

/**
 * Default fixture: signin/homepage/incoming/sso exist (in enabled, disabled,
 * enabled-not-ready and view-only flavors), signup/api/mailer are MISSING —
 * so the ensure button shows and both badge families render.
 */
function configsPayload() {
  return {
    shrimp: '',
    record: envelopeRecord(),
    details: {
      configs: {
        signin: { exists: true, config: signinConfig() },
        signup: { exists: false, config: null },
        homepage: { exists: true, config: homepageConfig() },
        api: { exists: false, config: null },
        incoming: { exists: true, config: incomingConfig() },
        sso: { exists: true, config: ssoConfig() },
        mailer: { exists: false, config: null },
      },
    },
  };
}

/** Every materializable kind present — the ensure button must not render. */
function completePayload() {
  const payload = configsPayload();
  payload.details.configs.signup = {
    exists: true,
    config: {
      domain_id: 'cd1',
      enabled: false,
      signup_enabled: false,
      autoverify: false,
      validation_strategy: 'passthrough',
      allowed_signup_domains: [],
      created: 1700000000,
      updated: null,
    },
  } as never;
  payload.details.configs.api = {
    exists: true,
    config: { domain_id: 'cd1', enabled: false, created: 1700000000, updated: null },
  } as never;
  return payload;
}

function ensureAck(dry_run: boolean) {
  return {
    shrimp: '',
    record: envelopeRecord(),
    details: {
      dry_run,
      created: ['signup', 'api'],
      existing: ['signin', 'homepage', 'incoming'],
      skipped: [
        { kind: 'sso', reason: 'requires_credentials' },
        { kind: 'mailer', reason: 'requires_credentials' },
      ],
    },
  };
}

function upsertAck(kind = 'signin', outcome = 'updated') {
  return {
    shrimp: '',
    record: envelopeRecord(),
    details: { kind, outcome, config: signinConfig() },
  };
}

function deleteAck(kind = 'sso') {
  return {
    shrimp: '',
    record: envelopeRecord(),
    details: { kind, deleted: true },
  };
}

const dialogInput = (w: VueWrapper) => w.find('#admin-confirm-input');
const dialogSubmit = (w: VueWrapper) => w.find('[data-testid="admin-confirm-submit"]');

describe('DomainConfigsSection', () => {
  let wrapper: VueWrapper;
  let pinia: ReturnType<typeof createPinia>;

  const mountSection = () =>
    mount(DomainConfigsSection, {
      props: { extid: EXTID, displayDomain: 'secrets.example.com' },
      global: { plugins: [pinia, i18n] },
    });

  beforeEach(() => {
    pinia = createPinia();
    setActivePinia(pinia);
    vi.clearAllMocks();
    mockApi.get.mockResolvedValue({ data: configsPayload() });
  });
  afterEach(() => wrapper?.unmount());

  describe('load + rows', () => {
    it('fetches the configs subresource and renders all seven rows in order', async () => {
      wrapper = mountSection();
      await flushPromises();

      expect(mockApi.get).toHaveBeenCalledWith(CONFIGS_URL);
      const rowIds = wrapper
        .findAll('[data-testid^="config-row-"]')
        .map((row) => row.attributes('data-testid'));
      expect(rowIds).toEqual(ALL_KINDS.map((kind) => `config-row-${kind}`));
    });

    it('badges each row by its honest state, including enabled-not-ready', async () => {
      wrapper = mountSection();
      await flushPromises();

      expect(wrapper.find('[data-testid="config-status-signin"]').text()).toBe(
        'web.admin.domains.configs.status.enabled'
      );
      expect(wrapper.find('[data-testid="config-status-homepage"]').text()).toBe(
        'web.admin.domains.configs.status.disabled'
      );
      // incoming is enabled but has no ready recipients configuration.
      expect(wrapper.find('[data-testid="config-status-incoming"]').text()).toBe(
        'web.admin.domains.configs.status.enabledNotReady'
      );
    });

    it('shows the missing badge + absent-record note on missing rows', async () => {
      wrapper = mountSection();
      await flushPromises();

      for (const kind of ['signup', 'api', 'mailer'] as const) {
        expect(wrapper.find(`[data-testid="config-status-${kind}"]`).text()).toBe(
          'web.admin.domains.configs.status.missing'
        );
        expect(wrapper.find(`[data-testid="config-missing-note-${kind}"]`).text()).toBe(
          `web.admin.domains.configs.missingNotes.${kind}`
        );
        // Nothing to delete or expand on a missing record.
        expect(wrapper.find(`[data-testid="config-delete-${kind}"]`).exists()).toBe(false);
        expect(wrapper.find(`[data-testid="config-toggle-${kind}"]`).exists()).toBe(false);
      }
      // The upsert creates the record, so the button reads "Create".
      expect(wrapper.find('[data-testid="config-edit-signup"]').text()).toBe(
        'web.admin.domains.configs.edit.createButton'
      );
    });

    it('expands an existing row into the field grid', async () => {
      wrapper = mountSection();
      await flushPromises();

      expect(wrapper.find('[data-testid="config-fields-signin"]').exists()).toBe(false);
      await wrapper.find('[data-testid="config-toggle-signin"]').trigger('click');

      const grid = wrapper.find('[data-testid="config-fields-signin"]');
      expect(grid.exists()).toBe(true);
      expect(
        wrapper.find('[data-testid="config-field-signin-signin_enabled"]').text()
      ).toContain('web.admin.domains.detail.yes');
      expect(wrapper.find('[data-testid="config-field-signin-restrict_to"]').text()).toContain(
        'web.admin.domains.detail.none'
      );
    });

    it('renders the error state and retries on a network failure', async () => {
      mockApi.get.mockRejectedValue(new Error('Network Error'));
      wrapper = mountSection();
      await flushPromises();

      expect(wrapper.find('[data-testid="configs-error"]').exists()).toBe(true);

      mockApi.get.mockResolvedValue({ data: configsPayload() });
      await wrapper.find('[data-testid="configs-retry"]').trigger('click');
      await flushPromises();
      expect(wrapper.find('[data-testid="config-row-signin"]').exists()).toBe(true);
    });

    it('degrades honestly when the 2xx payload fails the contract', async () => {
      mockApi.get.mockResolvedValue({ data: { shrimp: '', record: {}, details: {} } });
      wrapper = mountSection();
      await flushPromises();

      expect(wrapper.find('[data-testid="configs-degraded"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="configs-error"]').exists()).toBe(false);
    });
  });

  describe('sso/mailer are view/delete only', () => {
    it('offers no edit button and shows the workspace-managed note', async () => {
      wrapper = mountSection();
      await flushPromises();

      expect(wrapper.find('[data-testid="config-edit-sso"]').exists()).toBe(false);
      expect(wrapper.find('[data-testid="config-edit-mailer"]').exists()).toBe(false);
      expect(wrapper.find('[data-testid="config-not-editable-sso"]').text()).toBe(
        'web.admin.domains.configs.notEditable'
      );
      // The existing sso record IS deletable.
      expect(wrapper.find('[data-testid="config-delete-sso"]').exists()).toBe(true);
    });
  });

  describe('ensure (dry-run preview → plain confirm apply)', () => {
    it('previews with dry_run=true, applies with dry_run=false, and refetches', async () => {
      mockApi.post.mockImplementation((_url: string, body: { dry_run: boolean }) =>
        Promise.resolve({ data: ensureAck(body.dry_run) })
      );
      wrapper = mountSection();
      await flushPromises();
      expect(mockApi.get).toHaveBeenCalledTimes(1);

      await wrapper.find('[data-testid="config-ensure"]').trigger('click');
      await flushPromises();

      expect(mockApi.post).toHaveBeenCalledWith(`${CONFIGS_URL}/ensure`, { dry_run: true });
      // Default variant: no typed token, confirm is enabled immediately.
      expect(dialogSubmit(wrapper).attributes('disabled')).toBeUndefined();
      expect(dialogInput(wrapper).exists()).toBe(false);

      await wrapper.find('form').trigger('submit');
      await flushPromises();

      expect(mockApi.post).toHaveBeenCalledWith(`${CONFIGS_URL}/ensure`, { dry_run: false });
      expect(showMock).toHaveBeenCalledWith(
        'web.admin.domains.configs.ensure.success',
        'success'
      );
      expect(mockApi.get).toHaveBeenCalledTimes(2);
    });

    it('hides the ensure button when nothing is missing', async () => {
      mockApi.get.mockResolvedValue({ data: completePayload() });
      wrapper = mountSection();
      await flushPromises();

      expect(wrapper.find('[data-testid="config-ensure"]').exists()).toBe(false);
    });

    it('treats exists:true with a null config as missing for rows AND the button', async () => {
      // The one recordPresent() predicate drives both surfaces, so an entry
      // the server flags as existing but whose config failed to hydrate still
      // reads as missing everywhere.
      const payload = completePayload();
      payload.details.configs.signup = { exists: true, config: null } as never;
      mockApi.get.mockResolvedValue({ data: payload });
      wrapper = mountSection();
      await flushPromises();

      expect(wrapper.find('[data-testid="config-status-signup"]').text()).toBe(
        'web.admin.domains.configs.status.missing'
      );
      expect(wrapper.find('[data-testid="config-ensure"]').exists()).toBe(true);
    });

    it('counts a kind whose KEY is absent from a populated map as missing', async () => {
      // The map schema requires all seven keys today, so this state can only
      // arise from contract drift (e.g. the KINDS constant gains an entry
      // before the server ships it). Bypass the HTTP layer and stub the store
      // verb to hand the component a populated map with `signup` deleted
      // outright — the row must read MISSING and the ensure entry point must
      // stay reachable, not be silently skipped (or crash the section).
      const store = useAdminDomains();
      const payload = completePayload();
      const configs = payload.details.configs as Record<string, unknown>;
      delete configs.signup;
      vi.spyOn(store, 'fetchConfigs').mockResolvedValue({ configs } as never);
      wrapper = mountSection();
      await flushPromises();

      expect(wrapper.find('[data-testid="config-status-signup"]').text()).toBe(
        'web.admin.domains.configs.status.missing'
      );
      expect(wrapper.find('[data-testid="config-ensure"]').exists()).toBe(true);
    });

    it('fails the apply inside the dialog when the ack fails the contract', async () => {
      // The apply ack is load-bearing: it is the only proof dry_run was
      // actually applied. A null ack (2xx that failed Zod) must land as an
      // error IN the dialog — never a success toast for an unverified run.
      mockApi.post.mockImplementation((_url: string, body: { dry_run: boolean }) =>
        body.dry_run
          ? Promise.resolve({ data: ensureAck(true) })
          : Promise.resolve({
              data: { shrimp: '', record: envelopeRecord(), details: { bogus: true } },
            })
      );
      wrapper = mountSection();
      await flushPromises();

      await wrapper.find('[data-testid="config-ensure"]').trigger('click');
      await flushPromises();
      await wrapper.find('form').trigger('submit');
      await flushPromises();

      expect(wrapper.find('[data-testid="admin-confirm-dialog"]').text()).toContain(
        'web.admin.domains.configs.degraded'
      );
      expect(showMock).not.toHaveBeenCalled();
      expect(mockApi.get).toHaveBeenCalledTimes(1);
    });

    it('surfaces a degraded preview under the button instead of a dead dialog', async () => {
      // 2xx whose payload fails the Zod contract → the store resolves null;
      // the preview must throw into the button-level error, not silently no-op.
      mockApi.post.mockResolvedValue({ data: { shrimp: '', record: {}, details: {} } });
      wrapper = mountSection();
      await flushPromises();

      await wrapper.find('[data-testid="config-ensure"]').trigger('click');
      await flushPromises();

      expect(wrapper.find('[data-testid="config-ensure-error"]').text()).toBe(
        'web.admin.domains.configs.degraded'
      );
      expect(wrapper.find('[data-testid="admin-confirm-dialog"]').exists()).toBe(false);
      expect(showMock).not.toHaveBeenCalled();
    });

    it('skips the dialog and resyncs when the preview finds nothing missing', async () => {
      // Race: another operator materialized the records between our load and
      // the preview. No confirm dialog — info toast + refetch instead.
      const ack = ensureAck(true);
      ack.details.created = [];
      ack.details.existing = ['signin', 'signup', 'homepage', 'api', 'incoming'];
      mockApi.post.mockResolvedValue({ data: ack });
      wrapper = mountSection();
      await flushPromises();
      expect(mockApi.get).toHaveBeenCalledTimes(1);

      await wrapper.find('[data-testid="config-ensure"]').trigger('click');
      await flushPromises();

      expect(wrapper.find('[data-testid="admin-confirm-dialog"]').exists()).toBe(false);
      expect(showMock).toHaveBeenCalledWith(
        'web.admin.domains.configs.ensure.nothingMissing',
        'info'
      );
      expect(mockApi.get).toHaveBeenCalledTimes(2);
      // Only the dry-run preview ran — never an apply.
      expect(mockApi.post).toHaveBeenCalledTimes(1);
      expect(mockApi.post).toHaveBeenCalledWith(`${CONFIGS_URL}/ensure`, { dry_run: true });
    });

    it('keeps an apply failure inside the dialog and does not toast', async () => {
      mockApi.post.mockImplementation((_url: string, body: { dry_run: boolean }) =>
        body.dry_run
          ? Promise.resolve({ data: ensureAck(true) })
          : Promise.reject(axiosError(422, { error: 'Domain not found' }))
      );
      wrapper = mountSection();
      await flushPromises();

      await wrapper.find('[data-testid="config-ensure"]').trigger('click');
      await flushPromises();
      await wrapper.find('form').trigger('submit');
      await flushPromises();

      expect(wrapper.find('[data-testid="admin-confirm-dialog"]').text()).toContain(
        'Domain not found'
      );
      expect(showMock).not.toHaveBeenCalled();
      expect(mockApi.get).toHaveBeenCalledTimes(1);
    });
  });

  describe('edit modal (parent-owned upsert)', () => {
    it('prefills from the record and PUTs ONLY the changed fields on edit', async () => {
      mockApi.put.mockResolvedValue({ data: upsertAck() });
      wrapper = mountSection();
      await flushPromises();

      await wrapper.find('[data-testid="config-edit-signin"]').trigger('click');
      await flushPromises();

      const modal = wrapper.find('[data-testid="config-edit-modal"]');
      expect(modal.exists()).toBe(true);
      // Prefilled from the current serialized config.
      expect(
        (wrapper.find('[data-testid="config-field-enabled"]').element as HTMLInputElement).checked
      ).toBe(true);
      expect(
        (wrapper.find('[data-testid="config-field-email_auth_enabled"]').element as HTMLInputElement)
          .checked
      ).toBe(false);

      await wrapper.find('[data-testid="config-field-email_auth_enabled"]').setValue(true);
      await wrapper.find('[data-testid="config-edit-submit"]').trigger('click');
      await flushPromises();

      // Audit fidelity: only the diff ships, so the server's `changed:[...]`
      // audit detail lists real changes.
      expect(mockApi.put).toHaveBeenCalledWith(`${CONFIGS_URL}/signin`, {
        email_auth_enabled: true,
      });
      expect(showMock).toHaveBeenCalledWith('web.admin.domains.configs.edit.success', 'success');
      expect(mockApi.get).toHaveBeenCalledTimes(2);
      expect(wrapper.find('[data-testid="config-edit-modal"]').exists()).toBe(false);
    });

    it('disables submit while nothing has changed on an existing record', async () => {
      wrapper = mountSection();
      await flushPromises();

      await wrapper.find('[data-testid="config-edit-signin"]').trigger('click');
      await flushPromises();

      const submit = wrapper.find('[data-testid="config-edit-submit"]');
      expect(submit.attributes('disabled')).toBeDefined();

      await wrapper.find('[data-testid="config-field-email_auth_enabled"]').setValue(true);
      expect(submit.attributes('disabled')).toBeUndefined();

      // Reverting the change re-disables — the payload would be empty again.
      await wrapper.find('[data-testid="config-field-email_auth_enabled"]').setValue(false);
      expect(submit.attributes('disabled')).toBeDefined();
      expect(mockApi.put).not.toHaveBeenCalled();
    });

    it('PUTs the full writable set when creating a missing record', async () => {
      mockApi.put.mockResolvedValue({ data: upsertAck('signup', 'created') });
      wrapper = mountSection();
      await flushPromises();

      // signup is MISSING in the default fixture — the button reads "Create".
      await wrapper.find('[data-testid="config-edit-signup"]').trigger('click');
      await flushPromises();
      await wrapper.find('[data-testid="config-edit-submit"]').trigger('click');
      await flushPromises();

      expect(mockApi.put).toHaveBeenCalledWith(`${CONFIGS_URL}/signup`, {
        enabled: false,
        signup_enabled: false,
        autoverify: false,
        validation_strategy: 'passthrough',
        allowed_signup_domains: [],
      });
    });

    it('falls back to passthrough when a legacy record hydrates a null strategy', async () => {
      // Nil-tolerant repair path: the nullable schema lets the record through,
      // the prefill shows a valid choice, and submitting counts the repair as
      // a change (null -> 'passthrough').
      const payload = completePayload();
      (payload.details.configs.signup.config as unknown as Record<string, unknown>).validation_strategy =
        null;
      mockApi.get.mockResolvedValue({ data: payload });
      mockApi.put.mockResolvedValue({ data: upsertAck('signup', 'updated') });
      wrapper = mountSection();
      await flushPromises();

      // The row rendered (no panel-wide degrade) and is editable.
      expect(wrapper.find('[data-testid="configs-degraded"]').exists()).toBe(false);
      await wrapper.find('[data-testid="config-edit-signup"]').trigger('click');
      await flushPromises();

      const select = wrapper.find('[data-testid="config-field-validation_strategy"]');
      expect((select.element as HTMLSelectElement).value).toBe('passthrough');

      await wrapper.find('[data-testid="config-edit-submit"]').trigger('click');
      await flushPromises();
      expect(mockApi.put).toHaveBeenCalledWith(`${CONFIGS_URL}/signup`, {
        validation_strategy: 'passthrough',
      });
    });

    it('still succeeds on an upsert ack that fails the contract, but warns', async () => {
      // Same policy as delete: the PUT landed (a failure would reject), so
      // the modal closes and toasts — with a devtools warning for the Zod
      // regression on the echoed state.
      const warnSpy = vi.spyOn(console, 'warn').mockImplementation(() => {});
      mockApi.put.mockResolvedValue({
        data: { shrimp: '', record: envelopeRecord(), details: { bogus: true } },
      });
      wrapper = mountSection();
      await flushPromises();

      await wrapper.find('[data-testid="config-edit-signin"]').trigger('click');
      await flushPromises();
      await wrapper.find('[data-testid="config-field-email_auth_enabled"]').setValue(true);
      await wrapper.find('[data-testid="config-edit-submit"]').trigger('click');
      await flushPromises();

      expect(showMock).toHaveBeenCalledWith('web.admin.domains.configs.edit.success', 'success');
      expect(warnSpy).toHaveBeenCalledWith(
        expect.stringContaining('upsert ack failed schema validation')
      );
      expect(wrapper.find('[data-testid="config-edit-modal"]').exists()).toBe(false);
      warnSpy.mockRestore();
    });

    it('keeps a 4xx failure inside the modal and does not toast or refetch', async () => {
      mockApi.put.mockRejectedValue(
        axiosError(422, { error: 'not one of the allowed values' })
      );
      wrapper = mountSection();
      await flushPromises();

      await wrapper.find('[data-testid="config-edit-signin"]').trigger('click');
      await flushPromises();
      await wrapper.find('[data-testid="config-field-email_auth_enabled"]').setValue(true);
      await wrapper.find('[data-testid="config-edit-submit"]').trigger('click');
      await flushPromises();

      const modal = wrapper.find('[data-testid="config-edit-modal"]');
      expect(modal.exists()).toBe(true);
      expect(modal.text()).toContain('not one of the allowed values');
      expect(showMock).not.toHaveBeenCalled();
      expect(mockApi.get).toHaveBeenCalledTimes(1);
    });
  });

  describe('delete (typed-confirm, token = the kind slug)', () => {
    it('gates the delete on the retyped kind, then DELETEs and refetches', async () => {
      mockApi.delete.mockResolvedValue({ data: deleteAck('sso') });
      wrapper = mountSection();
      await flushPromises();

      await wrapper.find('[data-testid="config-delete-sso"]').trigger('click');
      await flushPromises();

      expect(dialogSubmit(wrapper).attributes('disabled')).toBeDefined();
      await dialogInput(wrapper).setValue('sso');
      expect(dialogSubmit(wrapper).attributes('disabled')).toBeUndefined();

      await wrapper.find('form').trigger('submit');
      await flushPromises();

      expect(mockApi.delete).toHaveBeenCalledWith(`${CONFIGS_URL}/sso`);
      expect(showMock).toHaveBeenCalledWith(
        'web.admin.domains.configs.delete.success',
        'success'
      );
      expect(mockApi.get).toHaveBeenCalledTimes(2);
    });

    it('still succeeds on a delete ack that fails the contract, but warns', async () => {
      // Unlike ensure-apply, the DELETE outcome is not ambiguous on a null
      // ack (a failed delete rejects), so the flow completes — but the Zod
      // regression must surface in devtools instead of passing silently.
      const warnSpy = vi.spyOn(console, 'warn').mockImplementation(() => {});
      mockApi.delete.mockResolvedValue({
        data: { shrimp: '', record: envelopeRecord(), details: { bogus: true } },
      });
      wrapper = mountSection();
      await flushPromises();

      await wrapper.find('[data-testid="config-delete-sso"]').trigger('click');
      await flushPromises();
      await dialogInput(wrapper).setValue('sso');
      await wrapper.find('form').trigger('submit');
      await flushPromises();

      expect(showMock).toHaveBeenCalledWith(
        'web.admin.domains.configs.delete.success',
        'success'
      );
      expect(warnSpy).toHaveBeenCalledWith(
        expect.stringContaining('delete ack failed schema validation')
      );
      expect(mockApi.get).toHaveBeenCalledTimes(2);
      warnSpy.mockRestore();
    });

    it('keeps a delete failure inside the dialog', async () => {
      mockApi.delete.mockRejectedValue(axiosError(404, { error: 'Config not found' }));
      wrapper = mountSection();
      await flushPromises();

      await wrapper.find('[data-testid="config-delete-signin"]').trigger('click');
      await flushPromises();
      await dialogInput(wrapper).setValue('signin');
      await wrapper.find('form').trigger('submit');
      await flushPromises();

      expect(wrapper.find('[data-testid="admin-confirm-dialog"]').text()).toContain(
        'Config not found'
      );
      expect(showMock).not.toHaveBeenCalled();
    });
  });
});
