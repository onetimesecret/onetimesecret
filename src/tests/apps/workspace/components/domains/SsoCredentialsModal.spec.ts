// src/tests/apps/workspace/components/domains/SsoCredentialsModal.spec.ts
//
// The modal is a thin shell around DomainSsoConfigForm. What it owns, and
// what these tests pin, is the wiring the form cannot supply itself: the
// install-wide SAML switch (SAML_ENABLED, #4604) read from the bootstrap
// payload through features.isSamlEnabled and handed to the form as the
// samlEnabled prop, and the domain's verification state handed through as
// domainVerified (#4579), which drives the form's unverified-domain notice.
// A regression that drops either binding would otherwise be caught only by
// the type-checker.
//
// It also owns the return-to-window refresh of the last sign-in outcome:
// Confirm sign-in happens in another (private) window, so when this window
// regains focus or visibility the modal asks the page to re-read it,
// passively (no person caused the request).

import { createTestingPinia } from '@pinia/testing';
import { flushPromises, mount, VueWrapper } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import SsoCredentialsModal from '../../../../../apps/workspace/components/domains/SsoCredentialsModal.vue';
import type { CustomDomainSsoConfig } from '../../../../../schemas/shapes/domains/sso-config';
import type { SsoConfigFormState } from '../../../../../shared/composables/useSsoConfig';
import { createTestI18n } from '../../../../setup';

// ─────────────────────────────────────────────────────────────────────────────
// Mocks
// ─────────────────────────────────────────────────────────────────────────────

const isSamlEnabledMock = vi.fn<() => boolean>();

vi.mock('@/utils/features', async () => {
  const actual = await vi.importActual<typeof import('@/utils/features')>('@/utils/features');
  return {
    ...actual,
    isSamlEnabled: () => isSamlEnabledMock(),
  };
});

// HeadlessUI renders its dialog through a portal; stub it so the form
// mounts inline where the assertions can see it.
vi.mock('@headlessui/vue', () => ({
  Dialog: {
    name: 'Dialog',
    template: '<div role="dialog"><slot /></div>',
    props: ['class'],
    emits: ['close'],
  },
  DialogPanel: {
    name: 'DialogPanel',
    template: '<div class="dialog-panel"><slot /></div>',
    props: ['class'],
  },
  DialogTitle: {
    name: 'DialogTitle',
    template: '<h3><slot /></h3>',
    props: ['as', 'class'],
  },
  TransitionRoot: {
    name: 'TransitionRoot',
    template: '<div v-if="show"><slot /></div>',
    props: ['as', 'show'],
  },
  TransitionChild: {
    name: 'TransitionChild',
    template: '<div><slot /></div>',
    props: ['as', 'enter', 'enterFrom', 'enterTo', 'leave', 'leaveFrom', 'leaveTo'],
  },
}));

vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="o-icon" :data-icon="name" />',
    props: ['collection', 'name'],
  },
}));

vi.mock('@/shared/components/common/ToggleWithIcon.vue', () => ({
  default: {
    name: 'ToggleWithIcon',
    template: '<button type="button" role="switch" :aria-checked="modelValue" />',
    props: ['modelValue', 'label', 'disabled'],
    emits: ['update:modelValue'],
  },
}));

// ─────────────────────────────────────────────────────────────────────────────
// Fixtures
// ─────────────────────────────────────────────────────────────────────────────

function createDefaultFormState(): SsoConfigFormState {
  return {
    provider_type: 'entra_id',
    display_name: '',
    client_id: '',
    client_secret: '',
    tenant_id: '',
    issuer: '',
    token_endpoint_auth_method: '',
    idp_sso_service_url: '',
    idp_entity_id: '',
    idp_cert: '',
    allowed_domains: [],
    enabled: false,
    enforce_sso_only: false,
    grant_org_scope: false,
  };
}

const savedConfig: CustomDomainSsoConfig = {
  domain_id: 'dm_123',
  provider_type: 'entra_id',
  enabled: false,
  enforce_sso_only: false,
  grant_org_scope: false,
  display_name: 'Acme',
  client_id: 'client-id',
  client_secret_masked: '****5678',
  tenant_id: '12345678-1234-1234-1234-123456789abc',
  issuer: null,
  token_endpoint_auth_method: null,
  idp_sso_service_url: null,
  idp_entity_id: null,
  idp_cert: null,
  sp_entity_id: null,
  acs_url: null,
  unreadable_fields: [],
  allowed_domains: [],
  requires_domain_filter: false,
  idp_controls_access: true,
  last_sign_in: null,
  created_at: new Date(),
  updated_at: new Date(),
};

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

describe('SsoCredentialsModal', () => {
  let wrapper: VueWrapper;
  const i18n = createTestI18n();

  const mountModal = async ({
    domainVerified = true,
    isOpen = true,
    isConfigured = false,
  }: { domainVerified?: boolean; isOpen?: boolean; isConfigured?: boolean } = {}) => {
    const component = mount(SsoCredentialsModal, {
      props: {
        isOpen,
        domainExtId: 'dm_123',
        domainHost: 'secrets.example.com',
        domainVerified,
        orgId: 'org_ext_123',
        formState: createDefaultFormState(),
        ssoConfig: isConfigured ? savedConfig : null,
        isLoading: false,
        isSaving: false,
        isDeleting: false,
        isTesting: false,
        isDiagnosing: false,
        hasUnsavedChanges: false,
        isConfigured,
        clientSecretMasked: null,
        testResult: null,
        testError: '',
        diagnosticsResult: null,
        savedCredentialsChecked: false,
        savedCredentialsUnchecked: false,
        diagnosticsError: '',
        isRefreshingLastSignIn: false,
      },
      global: {
        plugins: [i18n, createTestingPinia({ createSpy: vi.fn })],
        stubs: { Teleport: true },
      },
    });
    await flushPromises();
    return component;
  };

  beforeEach(() => {
    isSamlEnabledMock.mockReset();
  });

  afterEach(() => {
    wrapper?.unmount();
  });

  it('forwards retained credential-check evidence independently of the displayed verdict', async () => {
    isSamlEnabledMock.mockReturnValue(true);
    wrapper = await mountModal();
    await wrapper.setProps({ savedCredentialsChecked: true });

    const form = wrapper.getComponent({ name: 'DomainSsoConfigForm' });
    expect(form.props('savedCredentialsChecked')).toBe(true);
    expect(form.props('diagnosticsResult')).toBeNull();
  });

  it('offers SAML for a new config when the install-wide switch is on', async () => {
    isSamlEnabledMock.mockReturnValue(true);
    wrapper = await mountModal();

    expect(isSamlEnabledMock).toHaveBeenCalled();
    expect(wrapper.find('#domain-provider-saml').exists()).toBe(true);
    expect(wrapper.findAll('input[type="radio"][name="provider_type"]')).toHaveLength(3);
  });

  it('drops SAML for a new config when the install-wide switch is off', async () => {
    isSamlEnabledMock.mockReturnValue(false);
    wrapper = await mountModal();

    expect(isSamlEnabledMock).toHaveBeenCalled();
    expect(wrapper.find('#domain-provider-saml').exists()).toBe(false);
    expect(wrapper.find('#domain-provider-entra_id').exists()).toBe(true);
    expect(wrapper.find('#domain-provider-oidc').exists()).toBe(true);
    expect(wrapper.findAll('input[type="radio"][name="provider_type"]')).toHaveLength(2);
  });

  it('hands domainVerified to the form: unverified shows the notice', async () => {
    isSamlEnabledMock.mockReturnValue(true);
    wrapper = await mountModal({ domainVerified: false });

    expect(wrapper.find('[data-testid="sso-domain-unverified-notice"]').exists()).toBe(true);
  });

  it('hands domainVerified to the form: verified shows no notice', async () => {
    isSamlEnabledMock.mockReturnValue(true);
    wrapper = await mountModal({ domainVerified: true });

    expect(wrapper.find('[data-testid="sso-domain-unverified-notice"]').exists()).toBe(false);
  });

  it('hands the tenant-SSO verdict and the unchecked-credentials flag to the form', async () => {
    isSamlEnabledMock.mockReturnValue(true);
    wrapper = await mountModal({ isConfigured: true });
    const verdict = { available: false, unavailable_reason: 'sso_not_permitted' };
    await wrapper.setProps({ tenantSso: verdict, savedCredentialsUnchecked: true });

    const form = wrapper.getComponent({ name: 'DomainSsoConfigForm' });
    expect(form.props('tenantSso')).toEqual(verdict);
    expect(form.props('savedCredentialsUnchecked')).toBe(true);
  });

  it('relays the dialog events, with no disable event left to relay', async () => {
    isSamlEnabledMock.mockReturnValue(true);
    wrapper = await mountModal({ isConfigured: true });
    const form = wrapper.getComponent({ name: 'DomainSsoConfigForm' });

    form.vm.$emit('diagnostics');
    form.vm.$emit('save');
    await flushPromises();

    expect(wrapper.emitted('diagnostics')).toHaveLength(1);
    expect(wrapper.emitted('save')).toHaveLength(1);
    expect(wrapper.emitted('disable')).toBeUndefined();
  });

  it('relays a Refresh click as an active refresh', async () => {
    isSamlEnabledMock.mockReturnValue(true);
    wrapper = await mountModal({ isConfigured: true });

    await wrapper.get('[data-testid="sso-last-sign-in-refresh"]').trigger('click');

    expect(wrapper.emitted('refresh-last-sign-in')).toEqual([[false]]);
  });

  describe('refresh on returning to this window', () => {
    let now = 1_000_000;

    beforeEach(() => {
      isSamlEnabledMock.mockReturnValue(true);
      vi.spyOn(document, 'visibilityState', 'get').mockReturnValue('visible');
      vi.spyOn(Date, 'now').mockImplementation(() => now);
    });

    afterEach(() => {
      vi.restoreAllMocks();
    });

    it('asks for a passive refresh when the window regains focus or visibility', async () => {
      wrapper = await mountModal({ isConfigured: true });

      window.dispatchEvent(new Event('focus'));
      expect(wrapper.emitted('refresh-last-sign-in')).toEqual([[true]]);

      now += 10_000;
      document.dispatchEvent(new Event('visibilitychange'));
      expect(wrapper.emitted('refresh-last-sign-in')).toEqual([[true], [true]]);
    });

    it('asks once when focus and visibility fire together', async () => {
      wrapper = await mountModal({ isConfigured: true });

      document.dispatchEvent(new Event('visibilitychange'));
      window.dispatchEvent(new Event('focus'));

      expect(wrapper.emitted('refresh-last-sign-in')).toHaveLength(1);
    });

    it('does not ask while the window is hidden', async () => {
      vi.spyOn(document, 'visibilityState', 'get').mockReturnValue('hidden');
      wrapper = await mountModal({ isConfigured: true });

      document.dispatchEvent(new Event('visibilitychange'));

      expect(wrapper.emitted('refresh-last-sign-in')).toBeUndefined();
    });

    it.each([
      ['the dialog is closed', { isOpen: false, isConfigured: true }],
      ['nothing is saved yet', { isOpen: true, isConfigured: false }],
    ])('does not ask when %s', async (_state, options) => {
      wrapper = await mountModal(options);

      window.dispatchEvent(new Event('focus'));

      expect(wrapper.emitted('refresh-last-sign-in')).toBeUndefined();
    });
  });
});
