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

import { createTestingPinia } from '@pinia/testing';
import { flushPromises, mount, VueWrapper } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import SsoCredentialsModal from '../../../../../apps/workspace/components/domains/SsoCredentialsModal.vue';
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
    idp_sso_service_url: '',
    idp_entity_id: '',
    idp_cert: '',
    allowed_domains: [],
    enabled: false,
    enforce_sso_only: false,
    grant_org_scope: false,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

describe('SsoCredentialsModal', () => {
  let wrapper: VueWrapper;
  const i18n = createTestI18n();

  const mountModal = async ({ domainVerified = true }: { domainVerified?: boolean } = {}) => {
    const component = mount(SsoCredentialsModal, {
      props: {
        isOpen: true,
        domainExtId: 'dm_123',
        domainHost: 'secrets.example.com',
        domainVerified,
        orgId: 'org_ext_123',
        formState: createDefaultFormState(),
        ssoConfig: null,
        isLoading: false,
        isSaving: false,
        isDeleting: false,
        isTesting: false,
        hasUnsavedChanges: false,
        isConfigured: false,
        clientSecretMasked: null,
        testResult: null,
        testError: '',
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
});
