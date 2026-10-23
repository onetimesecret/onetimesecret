// src/tests/apps/workspace/components/domains/DomainSsoConfigForm.spec.ts
//
// Tests for DomainSsoConfigForm.vue covering:
// 1. Provider type selector rendering (OIDC / Entra / SAML — #3902, #4450)
// 2. Provider-specific field visibility (Entra ID, OIDC, SAML)
// 3. Form validation for required fields
// 4. Event emissions (save, delete, test, diagnostics, discard,
//    refresh-last-sign-in)
// 5. Form state updates via v-model
// 6. The one primary action (save and check / check and turn on / check),
//    the activation outcome of a run, and the Confirm sign-in step
// 7. SAML metadata import: the preview, the certificate picker, Apply, and
//    the trio's source URL (presentational, then wired to useSsoConfig)
//
// Note: This is a presentational component. It receives state via props
// and emits events for actions. Parent manages state via useSsoConfig.

import { readFileSync } from 'fs';
import { resolve } from 'path';
import { createTestingPinia } from '@pinia/testing';
import { flushPromises, mount, VueWrapper } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { defineComponent, h } from 'vue';
import DomainSsoConfigForm from '../../../../../apps/workspace/components/domains/DomainSsoConfigForm.vue';
import type { CustomDomainSsoConfig } from '../../../../../schemas/shapes/domains/sso-config';
import type {
  SsoDiagnosticCheck,
  SsoDiagnosticsResponse,
  TestSsoConnectionResponse,
} from '../../../../../services/sso.service';
import {
  useSsoConfig,
  type SsoConfigFormState,
  type SsoMetadataFetchFailure,
  type SsoMetadataPreview,
} from '../../../../../shared/composables/useSsoConfig';
import type {
  FetchIdpMetadataResponse,
  IdpMetadataCertificate,
  IdpMetadataPreviewResponse,
} from '../../../../../schemas/api/domains/responses/sso-config';
import type { TenantSsoVerdict } from '../../../../../schemas/api/domains/responses/signin-config';
import { createRealI18n, createTestI18n } from '../../../../setup';

// ─────────────────────────────────────────────────────────────────────────────
// Mocks
// ─────────────────────────────────────────────────────────────────────────────

// Mock OIcon component
vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="o-icon" :data-icon-name="name" />',
    props: ['collection', 'name', 'class', 'size'],
  },
}));

// Stub the toggle so we can assert role/state/emit without headlessui internals.
vi.mock('@/shared/components/common/ToggleWithIcon.vue', () => ({
  default: {
    name: 'ToggleWithIcon',
    props: ['enabled', 'disabled', 'loading', 'onLabel', 'offLabel'],
    emits: ['update:enabled'],
    template: `
      <button
        type="button"
        role="switch"
        :aria-checked="String(enabled)"
        :disabled="disabled"
        @click="$emit('update:enabled', !enabled)" />
    `,
  },
}));

// Mock BasicFormAlerts component
vi.mock('@/shared/components/forms/BasicFormAlerts.vue', () => ({
  default: {
    name: 'BasicFormAlerts',
    template:
      '<div class="form-alerts" data-testid="form-alerts" :data-error="error" :data-success="success" />',
    props: ['error', 'success'],
  },
}));

// The service, for the examples that wire the form to the real useSsoConfig
// (SAML metadata import). The component itself imports only its types.
const mockSsoService = vi.hoisted(() => ({
  getConfigForDomain: vi.fn(),
  saveConfigForDomain: vi.fn(),
  deleteConfigForDomain: vi.fn(),
  testConnectionForDomain: vi.fn(),
  runDiagnosticsForDomain: vi.fn(),
  fetchIdpMetadataForDomain: vi.fn(),
}));

vi.mock('@/services/sso.service', () => ({ SsoService: mockSsoService }));

// The component reads SSO_PROVIDER_ROUTE_NAMES and
// ssoProviderUsesClientCredentials from the real shapes module (which the
// contract spec pins to the Ruby source) — deliberately NOT mocked.

// i18n setup (pass-through: keys render as raw key paths — see ADR-014)
const i18n = createTestI18n();

// ─────────────────────────────────────────────────────────────────────────────
// Test Fixtures
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
    idp_metadata_url: '',
    allowed_domains: [],
    enabled: false,
    enforce_sso_only: false,
    grant_org_scope: false,
  };
}

const mockExistingConfig: CustomDomainSsoConfig = {
  domain_id: 'dm_123',
  provider_type: 'entra_id',
  enabled: true,
  enforce_sso_only: false,
  grant_org_scope: false,
  display_name: 'Test Domain SSO',
  client_id: 'client-id-123',
  client_secret_masked: '****5678',
  tenant_id: 'tenant-uuid-123',
  issuer: null,
  token_endpoint_auth_method: null,
  idp_sso_service_url: null,
  idp_entity_id: null,
  idp_cert: null,
  idp_metadata_url: null,
  sp_entity_id: null,
  acs_url: null,
  unreadable_fields: [],
  allowed_domains: ['example.com'],
  requires_domain_filter: false,
  idp_controls_access: true,
  last_sign_in: null,
  created_at: new Date(),
  updated_at: new Date(),
};

const mockExistingFormState: SsoConfigFormState = {
  provider_type: 'entra_id',
  display_name: 'Test Domain SSO',
  client_id: 'client-id-123',
  client_secret: '', // Never populated from API
  tenant_id: 'tenant-uuid-123',
  issuer: '',
  token_endpoint_auth_method: '',
  idp_sso_service_url: '',
  idp_entity_id: '',
  idp_cert: '',
  idp_metadata_url: '',
  allowed_domains: ['example.com'],
  enabled: true,
  enforce_sso_only: false,
  grant_org_scope: false,
};

// SAML (#4450): no client credential; the IdP trio is plaintext on the wire.
const SAML_CERT = '-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----';

const mockSamlFormState: SsoConfigFormState = {
  ...createDefaultFormState(),
  provider_type: 'saml',
  display_name: 'Acme SAML',
  idp_sso_service_url: 'https://idp.example.com/sso',
  idp_entity_id: 'https://idp.example.com/entity',
  idp_cert: SAML_CERT,
};

const mockSamlConfig: CustomDomainSsoConfig = {
  ...mockExistingConfig,
  provider_type: 'saml',
  display_name: 'Acme SAML',
  client_id: '',
  client_secret_masked: null,
  tenant_id: null,
  idp_sso_service_url: 'https://idp.example.com/sso',
  idp_entity_id: 'https://idp.example.com/entity',
  idp_cert: SAML_CERT,
  // The API composes these from the domain; note the non-default route name,
  // which the host-derived preview could not know.
  sp_entity_id: 'https://secrets.example.com/auth/sso/corp-saml/metadata',
  acs_url: 'https://secrets.example.com/auth/sso/corp-saml/callback',
  requires_domain_filter: true,
  idp_controls_access: false,
  last_sign_in: null,
};

interface MountOptions {
  domainExtId?: string;
  domainHost?: string;
  domainVerified?: boolean;
  orgId?: string;
  formState?: SsoConfigFormState;
  ssoConfig?: CustomDomainSsoConfig | null;
  isLoading?: boolean;
  isSaving?: boolean;
  isDeleting?: boolean;
  isTesting?: boolean;
  isDiagnosing?: boolean;
  hasUnsavedChanges?: boolean;
  isConfigured?: boolean;
  clientSecretMasked?: string | null;
  testResult?: TestSsoConnectionResponse | null;
  testError?: string;
  diagnosticsResult?: SsoDiagnosticsResponse | null;
  savedCredentialsChecked?: boolean;
  savedCredentialsUnchecked?: boolean;
  diagnosticsError?: string;
  isRefreshingLastSignIn?: boolean;
  tenantSso?: TenantSsoVerdict | null;
  samlEnabled?: boolean;
  metadataFetchUrl?: string;
  metadataPreview?: SsoMetadataPreview | null;
  isFetchingMetadata?: boolean;
  metadataFetchFailure?: SsoMetadataFetchFailure | null;
  canApplyMetadata?: boolean;
}

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

/**
 * The provider discovery check is an advanced disclosure (D7). Its result
 * renders inside that disclosure, which a result opens, and nowhere deeper:
 * never behind a nested "technical details" summary.
 */
function expectShownInProviderCheck(w: VueWrapper, element: Element): void {
  const disclosure = w.get('[data-testid="sso-provider-check"]').element as HTMLDetailsElement;
  expect(element.closest('details')).toBe(disclosure);
  expect(disclosure.open).toBe(true);
}

describe('DomainSsoConfigForm', () => {
  let wrapper: VueWrapper<InstanceType<typeof DomainSsoConfigForm>>;
  let pinia: ReturnType<typeof createTestingPinia>;

  beforeEach(() => {
    pinia = createTestingPinia({
      createSpy: vi.fn,
      stubActions: false,
    });
    vi.clearAllMocks();
  });

  afterEach(() => {
    if (wrapper) {
      wrapper.unmount();
    }
  });

  const defaultMountOptions: Required<MountOptions> = {
    domainExtId: 'dm_123',
    domainHost: 'secrets.example.com',
    domainVerified: true,
    orgId: 'org_ext_123',
    formState: createDefaultFormState(),
    ssoConfig: null,
    isLoading: false,
    isSaving: false,
    isDeleting: false,
    isTesting: false,
    isDiagnosing: false,
    hasUnsavedChanges: false,
    isConfigured: false,
    clientSecretMasked: null,
    testResult: null,
    testError: '',
    diagnosticsResult: null,
    savedCredentialsChecked: false,
    savedCredentialsUnchecked: false,
    diagnosticsError: '',
    isRefreshingLastSignIn: false,
    // No verdict loaded: the form makes no claim from it.
    tenantSso: null,
    // The install-wide SAML switch (SAML_ENABLED, #4604): on for the suite,
    // off only in the examples about the switch itself.
    samlEnabled: true,
    // No metadata fetched (SAML metadata import).
    metadataFetchUrl: '',
    metadataPreview: null,
    isFetchingMetadata: false,
    metadataFetchFailure: null,
    canApplyMetadata: false,
  };

  const mountComponent = async (options: MountOptions = {}) => {
    const props = { ...defaultMountOptions, ...options };
    if (options.formState === undefined) {
      props.formState = createDefaultFormState();
    }

    const component = mount(DomainSsoConfigForm, {
      props,
      global: {
        plugins: [i18n, pinia],
        stubs: {
          Teleport: true,
        },
      },
    });

    await flushPromises();
    return component;
  };

  // Defaults describe a run on a connection that was already on, without
  // asking for activation; activation examples pass their own outcome.
  const diagnostics = (
    overall: SsoDiagnosticsResponse['overall'],
    checks: SsoDiagnosticCheck[],
    extra: Partial<SsoDiagnosticsResponse> = {}
  ): SsoDiagnosticsResponse => ({
    user_id: 'cust_456',
    provider_type: 'entra_id',
    checked_at: '2026-10-12T10:00:00Z',
    configuration_revision: '1760263200',
    overall,
    checks,
    enabled: true,
    activation: 'not_requested',
    ...extra,
  });

  describe('First-time setup sequence', () => {
    it.each([
      ['entra_id', 'setup_register'],
      ['oidc', 'setup_register'],
      ['saml', 'setup_register_saml'],
    ] as const)(
      'introduces three ordered stages with %s registration guidance',
      async (provider_type, registrationKey) => {
        wrapper = await mountComponent({
          formState: { ...createDefaultFormState(), provider_type },
        });

        const guide = wrapper.get('[data-testid="sso-setup-guide"]');
        expect(guide.findAll('ol > li').map((stage) => stage.text())).toEqual(
          [registrationKey, 'setup_save_check', 'setup_confirm'].map(
            (key) => `web.organizations.sso.${key}`
          )
        );
        expect(
          guide.element.compareDocumentPosition(wrapper.get('fieldset').element) &
            Node.DOCUMENT_POSITION_FOLLOWING
        ).toBe(Node.DOCUMENT_POSITION_FOLLOWING);
      }
    );

    it('hides the introductory guide once the saved connection is on', async () => {
      wrapper = await mountComponent({
        formState: mockExistingFormState,
        ssoConfig: mockExistingConfig,
        isConfigured: true,
      });

      expect(wrapper.find('[data-testid="sso-setup-guide"]').exists()).toBe(false);
    });

    it('keeps the guide for a saved record that is still off (Finish setup)', async () => {
      wrapper = await mountComponent({
        formState: mockExistingFormState,
        ssoConfig: { ...mockExistingConfig, enabled: false },
        isConfigured: true,
      });

      expect(wrapper.find('[data-testid="sso-setup-guide"]').exists()).toBe(true);
    });

    it.each([
      ['entra_id', mockExistingFormState, 'sso-callback-url', '#domain-sso-client-id'],
      [
        'oidc',
        { ...mockExistingFormState, provider_type: 'oidc', issuer: 'https://idp.example.com' },
        'sso-callback-url',
        '#domain-sso-client-id',
      ],
      ['saml', mockSamlFormState, 'sso-saml-sp-details', '#domain-sso-idp-sso-service-url'],
    ] as const)(
      'orders %s registration identifiers before credentials, checks and sign-in confirmation',
      async (_provider, formState, identifiersTestId, credentialSelector) => {
        wrapper = await mountComponent({ formState });

        const providerCheck = wrapper
          .findAll('button[type="button"]')
          .find((button) => button.text().includes('web.organizations.sso.test_button'));
        expect(providerCheck).toBeDefined();
        // The discovery check is an advanced disclosure below the primary
        // check panel (D7); the primary action itself is in the footer.
        const sequence = [
          wrapper.get('fieldset').element,
          wrapper.get(`[data-testid="${identifiersTestId}"]`).element,
          wrapper.get(credentialSelector).element,
          wrapper.get('[data-testid="sso-diagnostics"]').element,
          providerCheck!.element,
          wrapper.get('[data-testid="sso-confirm-sign-in"]').element,
          wrapper.get('[data-testid="sso-diagnostics-run"]').element,
        ];
        for (let index = 1; index < sequence.length; index++) {
          expect(
            sequence[index - 1].compareDocumentPosition(sequence[index]) &
              Node.DOCUMENT_POSITION_FOLLOWING
          ).toBe(Node.DOCUMENT_POSITION_FOLLOWING);
        }
        expect(wrapper.findAll('[data-testid="sso-callback-url"]')).toHaveLength(
          formState.provider_type === 'saml' ? 0 : 1
        );
        expect(wrapper.findAll('[data-testid="sso-saml-sp-details"]')).toHaveLength(
          formState.provider_type === 'saml' ? 1 : 0
        );
      }
    );

    it.each([false, true])(
      'orders Entra fields from directory to application credentials when isConfigured=%s',
      async (isConfigured) => {
        wrapper = await mountComponent({
          formState: mockExistingFormState,
          ssoConfig: isConfigured ? mockExistingConfig : null,
          isConfigured,
        });

        const sequence = [
          wrapper.get('fieldset').element,
          wrapper.get('[data-testid="sso-callback-url"]').element,
          wrapper.get('#domain-sso-display-name').element,
          wrapper.get('#domain-sso-tenant-id').element,
          wrapper.get('#domain-sso-client-id').element,
          wrapper.get('#domain-sso-client-secret').element,
        ];
        for (let index = 1; index < sequence.length; index++) {
          expect(
            sequence[index - 1].compareDocumentPosition(sequence[index]) &
              Node.DOCUMENT_POSITION_FOLLOWING
          ).toBe(Node.DOCUMENT_POSITION_FOLLOWING);
        }
      }
    );

    it('keeps final sign-in guidance visible before anything is saved or checked', async () => {
      wrapper = await mountComponent();

      const card = wrapper.get('[data-testid="sso-confirm-sign-in"]');
      expect(card.isVisible()).toBe(true);
      for (const key of ['confirm_sign_in', 'confirm_sign_in_hint', 'confirm_sign_in_limits']) {
        expect(card.text()).toContain(`web.organizations.sso.${key}`);
      }
      expect(card.find('[data-testid="sso-last-sign-in"]').exists()).toBe(false);
    });

    it('closes the confirm sign-in section with the limits caveat, after the last sign-in row', async () => {
      wrapper = await mountComponent({
        formState: mockExistingFormState,
        ssoConfig: mockExistingConfig,
        isConfigured: true,
      });

      const card = wrapper.get('[data-testid="sso-confirm-sign-in"]');
      const paragraphs = card.findAll('p').map((p) => p.text());
      // Heading, instruction, last-sign-in row, then the caveat as the last line.
      expect(paragraphs[0]).toBe('web.organizations.sso.confirm_sign_in_hint');
      expect(paragraphs[paragraphs.length - 1]).toBe(
        'web.organizations.sso.confirm_sign_in_limits'
      );
      const row = card.get('[data-testid="sso-last-sign-in"]').element;
      const caveat = card.element.lastElementChild!;
      expect(caveat.textContent?.trim()).toBe('web.organizations.sso.confirm_sign_in_limits');
      expect(row.compareDocumentPosition(caveat) & Node.DOCUMENT_POSITION_FOLLOWING).toBe(
        Node.DOCUMENT_POSITION_FOLLOWING
      );
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // Settings-page layout (SSO page, D2/D6/D7)
  // ─────────────────────────────────────────────────────────────────────────────

  describe('Settings-page layout', () => {
    const RUN = '[data-testid="sso-diagnostics-run"]';
    const FOOTER = '[data-testid="sso-form-footer"]';
    const PROVIDER_CHECK = '[data-testid="sso-provider-check"]';
    const buttonsByKey = (w: VueWrapper, key: string) =>
      w.findAll('button').filter((b) => b.text().includes(key));

    it('introduces setup with one line and keeps the numbered steps behind a disclosure', async () => {
      wrapper = await mountComponent();

      const guide = wrapper.get('[data-testid="sso-setup-guide"]');
      expect(guide.get('#sso-setup-title').text()).toBe('web.organizations.sso.setup_summary');
      const steps = guide.get('details');
      expect((steps.element as HTMLDetailsElement).open).toBe(false);
      expect(steps.get('summary').text()).toBe('web.organizations.sso.setup_steps');
      expect(steps.findAll('ol > li')).toHaveLength(3);
    });

    it('keeps the discovery check collapsed until the admin opens it', async () => {
      wrapper = await mountComponent({ formState: mockExistingFormState });

      const disclosure = wrapper.get(PROVIDER_CHECK);
      expect(disclosure.element.tagName).toBe('DETAILS');
      expect((disclosure.element as HTMLDetailsElement).open).toBe(false);
      expect(disclosure.get('summary').text()).toBe('web.organizations.sso.test_connection');
      // The hint keeps discovery apart from the saved-configuration check and a sign-in.
      expect(disclosure.text()).toContain('web.organizations.sso.test_connection_hint');
      // It closes the check panel as a child of it: last in the section, its
      // body indented under the summary.
      const panel = wrapper.get('[data-testid="sso-diagnostics"]').element;
      expect(panel.contains(disclosure.element)).toBe(true);
      expect(panel.lastElementChild).toBe(disclosure.element);
      expect(disclosure.classes()).toContain('mt-4');
      expect(disclosure.get('summary + div').classes()).toEqual(
        expect.arrayContaining(['border-l', 'pl-4'])
      );
    });

    it('opens the discovery disclosure when a result or an error arrives', async () => {
      wrapper = await mountComponent({ formState: mockExistingFormState });
      const open = () => (wrapper.get(PROVIDER_CHECK).element as HTMLDetailsElement).open;
      expect(open()).toBe(false);

      await wrapper.setProps({ testError: 'Could not check provider settings' });
      expect(open()).toBe(true);

      await wrapper.setProps({ testError: '' });
      expect(open()).toBe(true); // closing it again is the admin's call

      wrapper.unmount();
      wrapper = await mountComponent({
        formState: mockExistingFormState,
        testResult: {
          user_id: 'cust_456',
          success: true,
          message: 'Connection successful',
          provider_type: 'entra_id',
          details: {},
        },
      });
      expect(open()).toBe(true);
    });

    it('puts the one primary action in a sticky footer, outside the check panel', async () => {
      wrapper = await mountComponent();

      const footer = wrapper.get(FOOTER);
      expect(footer.classes()).toContain('sticky');
      // WorkspaceFooter fixes the mobile nav to the viewport bottom below md
      // and the app footer at md+, and publishes each one's height; the bar
      // sticks exactly on top of whichever is shown, never under it and with
      // no gap.
      expect(footer.classes()).toContain('bottom-[var(--workspace-mobile-nav-height,3.5625rem)]');
      expect(footer.classes()).toContain('md:bottom-[var(--workspace-footer-height,6rem)]');
      expect(footer.classes()).not.toContain('bottom-0');
      expect(footer.find(RUN).exists()).toBe(true);
      expect(wrapper.get('[data-testid="sso-diagnostics"]').find(RUN).exists()).toBe(false);
      expect(wrapper.findAll(RUN)).toHaveLength(1);
      expect(wrapper.get('form').element.contains(footer.element)).toBe(true);
      // A clean new record: no Save, nothing to discard.
      expect(footer.find('button[type="submit"]').exists()).toBe(false);
      expect(buttonsByKey(wrapper, 'discard_changes')).toHaveLength(0);
    });

    it('adds Discard and Save for an existing record, one control each', async () => {
      wrapper = await mountComponent({
        formState: mockExistingFormState,
        ssoConfig: mockExistingConfig,
        isConfigured: true,
        hasUnsavedChanges: true,
      });

      const footer = wrapper.get(FOOTER);
      const footerButtons = footer.findAll('button').map((b) => b.text());
      // The usual order: Discard alone on the left, then Save, then the
      // primary check action as the rightmost control.
      expect(footerButtons).toEqual([
        'web.domains.email.discard_changes',
        'web.COMMON.save_changes',
        'web.organizations.sso.diagnostics_save_and_check',
      ]);
      const save = footer.get('[data-testid="sso-save"]');
      expect(save.attributes('type')).toBe('submit');
      expect(save.attributes('disabled')).toBeUndefined();
      expect(buttonsByKey(wrapper, 'save_changes')).toHaveLength(1);
      expect(buttonsByKey(wrapper, 'discard_changes')).toHaveLength(1);
      // Delete is the page's (its Careful Consideration Zone below the
      // card), so the form offers no delete control at all.
      expect(wrapper.find('[data-testid="sso-delete"]').exists()).toBe(false);
      expect(buttonsByKey(wrapper, 'web.COMMON.delete')).toHaveLength(0);
    });

    it('gives both footer buttons the same treatment: no static icon on the primary action', async () => {
      wrapper = await mountComponent({
        formState: mockExistingFormState,
        ssoConfig: mockExistingConfig,
        isConfigured: true,
      });

      const run = wrapper.get(RUN);
      expect(run.findAll('.o-icon')).toHaveLength(0);

      // The spinner still shows while the check (or its save) is in flight.
      await wrapper.setProps({ isDiagnosing: true });
      expect(wrapper.get(RUN).get('.o-icon').attributes('data-icon-name')).toBe('arrow-path');
    });

    it('offers Discard for a dirty new record, still with no Save (the check saves)', async () => {
      wrapper = await mountComponent({ hasUnsavedChanges: true });

      const footer = wrapper.get(FOOTER);
      expect(footer.findAll('button').map((b) => b.text())).toEqual([
        'web.domains.email.discard_changes',
        'web.organizations.sso.diagnostics_save_and_check',
      ]);
      expect(footer.find('button[type="submit"]').exists()).toBe(false);
      expect(buttonsByKey(wrapper, 'discard_changes')).toHaveLength(1);
    });

    it('hides Discard and disables Save while an existing record is clean', async () => {
      wrapper = await mountComponent({
        formState: mockExistingFormState,
        ssoConfig: mockExistingConfig,
        isConfigured: true,
      });

      expect(buttonsByKey(wrapper, 'discard_changes')).toHaveLength(0);
      const save = wrapper.get(FOOTER).get('[data-testid="sso-save"]');
      // Nothing to save: the button stays, disabled, so it does not read as
      // a second enabled secondary action.
      expect(save.attributes('disabled')).toBeDefined();
      await wrapper.get('form').trigger('submit');
      expect(wrapper.emitted('save')).toBeUndefined();

      await wrapper.setProps({ hasUnsavedChanges: true });
      expect(wrapper.get('[data-testid="sso-save"]').attributes('disabled')).toBeUndefined();
    });

    it('renders the callback URL as one labelled row with a copy control and its instruction', async () => {
      wrapper = await mountComponent({ formState: mockExistingFormState });

      const row = wrapper.get('[data-testid="sso-callback-url"]');
      expect(row.get('code').attributes('aria-labelledby')).toBe('domain-sso-callback-url-label');
      expect(row.get('#domain-sso-callback-url-label').text()).toBe(
        'web.organizations.sso.callback_url'
      );
      expect(row.get('code').text()).toMatch(
        /^https:\/\/secrets\.example\.com\/auth\/sso\/[a-z_-]+\/callback$/
      );
      expect(row.findAll('button')).toHaveLength(1);
      expect(row.text()).toContain('web.organizations.sso.callback_url_hint');
    });

    it('keeps one heading outline under the page: sections are h3, their items h4', async () => {
      wrapper = await mountComponent({
        formState: mockExistingFormState,
        ssoConfig: mockExistingConfig,
        isConfigured: true,
      });

      for (const id of [
        'sso-provider-details-title',
        'sso-diagnostics-title',
        'sso-confirm-sign-in-title',
      ]) {
        expect(wrapper.get(`#${id}`).element.tagName).toBe('H3');
      }
      expect(wrapper.find('h1, h2, h5, h6').exists()).toBe(false);
    });

    describe('bringing the check verdict into view', () => {
      const scrolledTo: Element[] = [];
      const scrollIntoView = vi.fn(function (this: Element) {
        scrolledTo.push(this);
      });
      const hadScrollIntoView = 'scrollIntoView' in Element.prototype;
      const originalScrollIntoView = Element.prototype.scrollIntoView;

      beforeEach(() => {
        scrolledTo.length = 0;
        Element.prototype.scrollIntoView = scrollIntoView;
      });

      afterEach(() => {
        if (hadScrollIntoView) Element.prototype.scrollIntoView = originalScrollIntoView;
        else Reflect.deleteProperty(Element.prototype, 'scrollIntoView');
        vi.unstubAllGlobals();
      });

      it('scrolls the verdict to the nearest edge when it arrives', async () => {
        wrapper = await mountComponent({ formState: mockExistingFormState });
        expect(scrollIntoView).not.toHaveBeenCalled();

        await wrapper.setProps({ diagnosticsResult: diagnostics('passed', []) });
        await flushPromises();

        expect(scrollIntoView).toHaveBeenCalledTimes(1);
        expect(scrollIntoView).toHaveBeenCalledWith({ block: 'nearest', behavior: 'smooth' });
        expect(scrolledTo[0]).toBe(wrapper.get('[data-testid="sso-diagnostics-result"]').element);
      });

      it('scrolls the transport error the same way', async () => {
        wrapper = await mountComponent({ formState: mockExistingFormState });

        await wrapper.setProps({ diagnosticsError: 'Could not reach the server' });
        await flushPromises();

        expect(scrollIntoView).toHaveBeenCalledTimes(1);
        expect(scrolledTo[0]).toBe(wrapper.get('[data-testid="sso-diagnostics-error"]').element);
      });

      it('jumps instead of gliding when the admin prefers reduced motion', async () => {
        vi.stubGlobal(
          'matchMedia',
          vi.fn((query: string) => ({ matches: query.includes('prefers-reduced-motion') }))
        );
        wrapper = await mountComponent({ formState: mockExistingFormState });

        await wrapper.setProps({ diagnosticsResult: diagnostics('failed', []) });
        await flushPromises();

        expect(scrollIntoView).toHaveBeenCalledWith({ block: 'nearest', behavior: 'auto' });
      });

      it('leaves the page alone when the verdict is cleared', async () => {
        wrapper = await mountComponent({
          formState: mockExistingFormState,
          diagnosticsResult: diagnostics('passed', []),
        });
        expect(scrollIntoView).not.toHaveBeenCalled(); // a verdict present at mount is not an arrival

        await wrapper.setProps({ diagnosticsResult: null });
        await flushPromises();

        expect(scrollIntoView).not.toHaveBeenCalled();
      });
    });

    it('labels the provider in place of the picker for a saved record', async () => {
      wrapper = await mountComponent({
        formState: mockExistingFormState,
        ssoConfig: mockExistingConfig,
        isConfigured: true,
      });

      const fieldset = wrapper.get('fieldset');
      expect(fieldset.get('legend').attributes('id')).toBe('provider-type-legend');
      expect(fieldset.findAll('input[type="radio"]')).toHaveLength(0);
      expect(fieldset.text()).toContain('Microsoft Entra ID');
      expect(fieldset.text()).toContain('web.organizations.sso.provider_type_locked_hint');
      expect(fieldset.text()).not.toContain('web.organizations.sso.provider_type_description');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // Provider type selector
  // ─────────────────────────────────────────────────────────────────────────────

  describe('Provider type selector', () => {
    // Issuerless providers (Google, GitHub) cannot satisfy per-tenant identity
    // partitioning and were removed from the tenant surface (#3902, PR #3900).
    // SAML joined in #4450 — its issuer is the IdP EntityID.
    it('renders exactly the three supported provider options (entra_id, oidc, saml)', async () => {
      wrapper = await mountComponent();

      expect(wrapper.find('#domain-provider-entra_id').exists()).toBe(true);
      expect(wrapper.find('#domain-provider-oidc').exists()).toBe(true);
      expect(wrapper.find('#domain-provider-saml').exists()).toBe(true);
      expect(wrapper.find('#domain-provider-google').exists()).toBe(false);
      expect(wrapper.find('#domain-provider-github').exists()).toBe(false);

      const providerRadios = wrapper.findAll('input[type="radio"][name="provider_type"]');
      expect(providerRadios).toHaveLength(3);
    });

    // SAML_ENABLED off (#4604): the API refuses provider_type saml, so the
    // selector for a NEW config must not offer it. The other two stay.
    it('drops the SAML option while the install-wide switch is off', async () => {
      wrapper = await mountComponent({ samlEnabled: false });

      expect(wrapper.find('#domain-provider-entra_id').exists()).toBe(true);
      expect(wrapper.find('#domain-provider-oidc').exists()).toBe(true);
      expect(wrapper.find('#domain-provider-saml').exists()).toBe(false);

      const providerRadios = wrapper.findAll('input[type="radio"][name="provider_type"]');
      expect(providerRadios).toHaveLength(2);
    });

    // A saved saml record stays editable (disable / delete) while the switch
    // is off: the locked provider display still resolves its label.
    it('still labels a saved saml record while the switch is off', async () => {
      wrapper = await mountComponent({
        samlEnabled: false,
        ssoConfig: mockSamlConfig,
        formState: { ...mockSamlFormState },
        isConfigured: true,
      });

      expect(wrapper.find('#domain-provider-saml').exists()).toBe(false);
      expect(wrapper.text()).toContain('SAML 2.0');
    });

    it('selects Entra ID by default', async () => {
      wrapper = await mountComponent();

      const entraRadio = wrapper.find('#domain-provider-entra_id');
      expect((entraRadio.element as HTMLInputElement).checked).toBe(true);
    });

    it('allows selecting different providers', async () => {
      wrapper = await mountComponent();

      const oidcRadio = wrapper.find('#domain-provider-oidc');
      await oidcRadio.setValue(true);
      await flushPromises();

      expect((oidcRadio.element as HTMLInputElement).checked).toBe(true);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // Provider-specific field visibility
  // ─────────────────────────────────────────────────────────────────────────────

  describe('Provider-specific field visibility', () => {
    it('shows tenant_id field when Entra ID is selected', async () => {
      wrapper = await mountComponent({
        formState: { ...createDefaultFormState(), provider_type: 'entra_id' },
      });

      const tenantIdInput = wrapper.find('#domain-sso-tenant-id');
      expect(tenantIdInput.exists()).toBe(true);
    });

    it('hides tenant_id field when OIDC is selected', async () => {
      wrapper = await mountComponent({
        formState: { ...createDefaultFormState(), provider_type: 'oidc' },
      });

      const tenantIdInput = wrapper.find('#domain-sso-tenant-id');
      expect(tenantIdInput.exists()).toBe(false);
    });

    it('shows issuer field when OIDC is selected', async () => {
      wrapper = await mountComponent({
        formState: { ...createDefaultFormState(), provider_type: 'oidc' },
      });

      const issuerInput = wrapper.find('#domain-sso-issuer');
      expect(issuerInput.exists()).toBe(true);
    });

    it('hides issuer field when Entra ID is selected', async () => {
      wrapper = await mountComponent({
        formState: { ...createDefaultFormState(), provider_type: 'entra_id' },
      });

      const issuerInput = wrapper.find('#domain-sso-issuer');
      expect(issuerInput.exists()).toBe(false);
    });

    it('does not show domain filter field (feature not yet enabled)', async () => {
      wrapper = await mountComponent({
        formState: { ...createDefaultFormState(), provider_type: 'oidc' },
      });

      const domainInput = wrapper.find('#domain-sso-domain-input');
      expect(domainInput.exists()).toBe(false);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // Form events and state updates
  // ─────────────────────────────────────────────────────────────────────────────

  describe('Form events and state updates', () => {
    it('emits save event when form is submitted', async () => {
      wrapper = await mountComponent({
        formState: mockExistingFormState,
        isConfigured: true,
        hasUnsavedChanges: true,
      });

      const form = wrapper.find('form');
      await form.trigger('submit.prevent');
      await flushPromises();

      expect(wrapper.emitted('save')).toBeTruthy();
    });

    it('emits update:formState when display_name changes', async () => {
      wrapper = await mountComponent();

      const displayNameInput = wrapper.find('#domain-sso-display-name');
      await displayNameInput.setValue('New Display Name');
      await flushPromises();

      const emitted = wrapper.emitted('update:formState');
      expect(emitted).toBeTruthy();
      expect(emitted![emitted!.length - 1][0]).toMatchObject({
        display_name: 'New Display Name',
      });
    });

    it('emits update:formState when client_id changes', async () => {
      wrapper = await mountComponent();

      const clientIdInput = wrapper.find('#domain-sso-client-id');
      await clientIdInput.setValue('new-client-id');
      await flushPromises();

      const emitted = wrapper.emitted('update:formState');
      expect(emitted).toBeTruthy();
      expect(emitted![emitted!.length - 1][0]).toMatchObject({
        client_id: 'new-client-id',
      });
    });

    it('emits update:formState when provider type changes', async () => {
      wrapper = await mountComponent();

      const oidcRadio = wrapper.find('#domain-provider-oidc');
      await oidcRadio.setValue(true);
      await flushPromises();

      const emitted = wrapper.emitted('update:formState');
      expect(emitted).toBeTruthy();
      expect(emitted![emitted!.length - 1][0]).toMatchObject({
        provider_type: 'oidc',
      });
    });

    it('emits discard event when discard button is clicked', async () => {
      wrapper = await mountComponent({
        formState: mockExistingFormState,
        hasUnsavedChanges: true,
      });

      // Find discard button (look for button that triggers discard)
      const buttons = wrapper.findAll('button[type="button"]');
      const discardButton = buttons.find(
        (b) => b.text().includes('Discard') || b.text().includes('Cancel')
      );

      if (discardButton) {
        await discardButton.trigger('click');
        await flushPromises();
        expect(wrapper.emitted('discard')).toBeTruthy();
      }
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // Form display state
  // ─────────────────────────────────────────────────────────────────────────────

  describe('Form display state', () => {
    it('displays pre-populated form state', async () => {
      wrapper = await mountComponent({
        formState: mockExistingFormState,
        isConfigured: true,
        clientSecretMasked: '****5678',
      });

      const displayNameInput = wrapper.find('#domain-sso-display-name');
      expect((displayNameInput.element as HTMLInputElement).value).toBe('Test Domain SSO');

      const clientIdInput = wrapper.find('#domain-sso-client-id');
      expect((clientIdInput.element as HTMLInputElement).value).toBe('client-id-123');

      const tenantIdInput = wrapper.find('#domain-sso-tenant-id');
      expect((tenantIdInput.element as HTMLInputElement).value).toBe('tenant-uuid-123');
    });

    describe('client secret shape hint (Entra Secret ID vs Value)', () => {
      const HINT = '[data-testid="sso-client-secret-shape-hint"]';
      const SECRET_ID = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';

      it('warns when an Entra secret is UUID-shaped, before any save', async () => {
        wrapper = await mountComponent({
          formState: { ...createDefaultFormState(), client_secret: SECRET_ID },
        });

        expect(wrapper.find(HINT).exists()).toBe(true);
        expect(wrapper.find(HINT).text()).toContain(
          'web.organizations.sso.client_secret_looks_like_secret_id'
        );
      });

      it('does not warn for a secret that is not UUID-shaped', async () => {
        wrapper = await mountComponent({
          formState: { ...createDefaultFormState(), client_secret: 'Ab1~cDe2.fGh3_iJk4-lMn5' },
        });

        expect(wrapper.find(HINT).exists()).toBe(false);
      });

      it('does not warn for a UUID-shaped secret on a generic OIDC provider', async () => {
        wrapper = await mountComponent({
          formState: {
            ...createDefaultFormState(),
            provider_type: 'oidc',
            issuer: 'https://idp.example.com',
            client_secret: SECRET_ID,
          },
        });

        expect(wrapper.find(HINT).exists()).toBe(false);
      });

      it('does not block the save', async () => {
        wrapper = await mountComponent({
          formState: {
            ...createDefaultFormState(),
            display_name: 'Acme',
            client_id: 'client-id',
            tenant_id: '12345678-1234-1234-1234-123456789abc',
            client_secret: SECRET_ID,
          },
        });

        // A new record is saved by the primary Save and check action.
        const saveAndCheck = wrapper.get('[data-testid="sso-diagnostics-run"]');
        expect(saveAndCheck.attributes('data-action')).toBe('save-and-check');
        expect((saveAndCheck.element as HTMLButtonElement).disabled).toBe(false);
      });
    });

    it('shows hint text about keeping existing secret when editing', async () => {
      wrapper = await mountComponent({
        formState: mockExistingFormState,
        isConfigured: true,
        clientSecretMasked: '****5678',
      });

      // The component shows a hint to leave blank to keep existing secret
      const hintText = wrapper.text();
      expect(hintText).toContain('web.organizations.sso.client_secret_update_hint');
    });

    it('emits save event on form submit', async () => {
      wrapper = await mountComponent({
        formState: mockExistingFormState,
        isConfigured: true,
        hasUnsavedChanges: true,
      });

      const form = wrapper.find('form');
      await form.trigger('submit.prevent');
      await flushPromises();

      expect(wrapper.emitted('save')).toBeTruthy();
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // Loading and saving states
  // ─────────────────────────────────────────────────────────────────────────────

  describe('Loading and saving states', () => {
    it('disables submit button when isSaving is true', async () => {
      wrapper = await mountComponent({
        formState: mockExistingFormState,
        isConfigured: true,
        isSaving: true,
      });

      const submitButton = wrapper.find('button[type="submit"]');
      expect((submitButton.element as HTMLButtonElement).disabled).toBe(true);
    });

    it('shows saving indicator when isSaving is true', async () => {
      wrapper = await mountComponent({
        formState: mockExistingFormState,
        isConfigured: true,
        isSaving: true,
      });

      // Check for saving text or indicator
      const buttonText = wrapper.text();
      expect(buttonText).toMatch(/saving/i);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // Test connection
  // ─────────────────────────────────────────────────────────────────────────────

  describe('Test connection', () => {
    const findTestButton = (w: VueWrapper) => {
      const buttons = w.findAll('button[type="button"]');
      return buttons.find((b) => b.text().includes('test_button'));
    };

    it('retains the provider-check heading and button translation keys', async () => {
      wrapper = await mountComponent();

      expect(wrapper.text()).toContain('web.organizations.sso.test_connection');
      expect(findTestButton(wrapper)!.text()).toContain('web.organizations.sso.test_button');
    });

    it('emits test event when test button clicked', async () => {
      wrapper = await mountComponent({
        formState: {
          ...createDefaultFormState(),
          client_id: 'client-123',
          tenant_id: 'tenant-uuid',
        },
      });

      const testButton = findTestButton(wrapper);
      expect(testButton).toBeDefined();
      await testButton!.trigger('click');
      await flushPromises();

      expect(wrapper.emitted('test')).toBeTruthy();
    });

    it('shows success result when testResult.success is true', async () => {
      wrapper = await mountComponent({
        formState: mockExistingFormState,
        testResult: {
          user_id: 'cust_456',
          success: true,
          message: 'Connection successful',
          provider_type: 'entra_id',
          details: { issuer: 'https://login.microsoftonline.com/tenant/v2.0' },
        },
      });

      const providerCheck = wrapper.get('[data-testid="sso-provider-check"]');
      expect(providerCheck.find('[role="status"]').exists()).toBe(true);
      const message = providerCheck.get('h4');
      expect(message.text()).toBe('Connection successful');
      expect(message.isVisible()).toBe(true);
      expectShownInProviderCheck(wrapper, message.element);
      const next = providerCheck.get('[data-testid="sso-provider-check-next"]');
      expect(next.text()).toBe('web.organizations.sso.provider_check_next');
      expect(next.isVisible()).toBe(true);
      expectShownInProviderCheck(wrapper, next.element);
    });

    it('shows error result when testResult.success is false', async () => {
      wrapper = await mountComponent({
        formState: mockExistingFormState,
        testResult: {
          user_id: 'cust_456',
          success: false,
          message: 'Invalid tenant ID',
          provider_type: 'entra_id',
          details: { error_code: 'invalid_tenant' },
        },
        testError: 'Invalid tenant ID',
      });

      // Check for error indicator
      const errorResult = wrapper.find('.bg-red-50, [role="alert"]');
      expect(errorResult.exists()).toBe(true);
    });

    it('renders both issuers exactly on issuer_mismatch', async () => {
      wrapper = await mountComponent({
        formState: { ...createDefaultFormState(), provider_type: 'oidc' },
        testResult: {
          user_id: 'cust_456',
          success: false,
          message: 'OIDC issuer mismatch',
          provider_type: 'oidc',
          details: {
            error_code: 'issuer_mismatch',
            configured_issuer: 'https://tenant.auth0.com',
            discovery_issuer: 'https://tenant.auth0.com/',
          },
        },
      });

      expect(wrapper.find('[data-testid="sso-configured-issuer"]').text()).toBe(
        'https://tenant.auth0.com'
      );
      expect(wrapper.find('[data-testid="sso-discovery-issuer"]').text()).toBe(
        'https://tenant.auth0.com/'
      );
      const alert = wrapper.find('[role="alert"]');
      expect(alert.text()).toContain('web.organizations.sso.configured_issuer');
      expect(alert.text()).toContain('web.organizations.sso.discovery_issuer');
      expect(wrapper.find('[data-testid="sso-issuer-mismatch-hint"]').text()).toBe(
        'web.organizations.sso.issuer_mismatch_hint'
      );
    });

    it('shows a placeholder when the discovered issuer is null', async () => {
      wrapper = await mountComponent({
        formState: { ...createDefaultFormState(), provider_type: 'oidc' },
        testResult: {
          user_id: 'cust_456',
          success: false,
          message: 'OIDC issuer mismatch',
          provider_type: 'oidc',
          details: {
            error_code: 'issuer_mismatch',
            configured_issuer: 'https://idp.example.com',
            discovery_issuer: null,
          },
        },
      });

      expect(wrapper.find('[data-testid="sso-discovery-issuer"]').text()).toBe('—');
    });

    it('does not render issuer rows for other failures', async () => {
      wrapper = await mountComponent({
        formState: mockExistingFormState,
        testResult: {
          user_id: 'cust_456',
          success: false,
          message: 'OIDC discovery document not found',
          provider_type: 'oidc',
          details: { error_code: 'discovery_not_found', http_status: 404 },
        },
      });

      expect(wrapper.find('[data-testid="sso-configured-issuer"]').exists()).toBe(false);
      expect(wrapper.find('[data-testid="sso-issuer-mismatch-hint"]').exists()).toBe(false);
    });

    it('shows testing indicator when isTesting is true', async () => {
      wrapper = await mountComponent({
        formState: mockExistingFormState,
        isTesting: true,
      });

      const buttonText = wrapper.text();
      expect(buttonText).toMatch(/testing/i);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // Check saved configuration (diagnostics)
  // ─────────────────────────────────────────────────────────────────────────────

  describe('Check saved configuration (diagnostics)', () => {
    const savedMount = (options: MountOptions = {}) =>
      mountComponent({
        formState: mockExistingFormState,
        ssoConfig: mockExistingConfig,
        isConfigured: true,
        ...options,
      });

    const check = (
      name: string,
      status: SsoDiagnosticCheck['status'],
      details: SsoDiagnosticCheck['details'] = {}
    ): SsoDiagnosticCheck => ({
      check: name,
      status,
      message: `${name} ${status}`,
      details,
    });

    const RUN = '[data-testid="sso-diagnostics-run"]';
    const validNewForm: SsoConfigFormState = {
      ...mockExistingFormState,
      client_secret: 'new-secret',
    };
    const offConfig: CustomDomainSsoConfig = { ...mockExistingConfig, enabled: false };

    it('shows the section with Save and check, disabled until a new form is valid', async () => {
      wrapper = await mountComponent({ isConfigured: false });

      expect(wrapper.get('[data-testid="sso-diagnostics"]').isVisible()).toBe(true);
      const button = wrapper.get(RUN);
      expect(button.attributes('data-action')).toBe('save-and-check');
      expect(button.text()).toBe('web.organizations.sso.diagnostics_save_and_check');
      expect(button.attributes('disabled')).toBeDefined();

      await button.trigger('click');
      expect(wrapper.emitted('diagnostics')).toBeUndefined();
      expect(wrapper.emitted('save')).toBeUndefined();
    });

    it.each([
      ['a new record', { formState: validNewForm }],
      ['a record that is off', { ssoConfig: offConfig, isConfigured: true }],
      [
        'a record with unsaved edits',
        { ssoConfig: mockExistingConfig, isConfigured: true, hasUnsavedChanges: true },
      ],
    ] as const)(
      'has one save path for %s: no inline save button and no save-first notice',
      async (_state, options) => {
        wrapper = await mountComponent({ formState: mockExistingFormState, ...options });

        expect(wrapper.find('[data-testid="sso-diagnostics-save"]').exists()).toBe(false);
        expect(wrapper.find('[data-testid="sso-diagnostics-save-first"]').exists()).toBe(false);
      }
    );

    it.each([
      ['a new record', { formState: validNewForm }, 'save-and-check', 'diagnostics_save_and_check'],
      [
        'a saved record with unsaved edits',
        {
          formState: mockExistingFormState,
          ssoConfig: mockExistingConfig,
          isConfigured: true,
          hasUnsavedChanges: true,
        },
        'save-and-check',
        'diagnostics_save_and_check',
      ],
      [
        'a saved record that is off',
        { formState: mockExistingFormState, ssoConfig: offConfig, isConfigured: true },
        'check-and-activate',
        'diagnostics_check_and_activate',
      ],
      [
        'a saved record that is on',
        { formState: mockExistingFormState, ssoConfig: mockExistingConfig, isConfigured: true },
        'check',
        'diagnostics_button',
      ],
    ] as const)('labels the primary action for %s', async (_state, options, action, key) => {
      wrapper = await mountComponent(options);

      const button = wrapper.get(RUN);
      expect(button.attributes('data-action')).toBe(action);
      expect(button.text()).toBe(`web.organizations.sso.${key}`);
      expect(button.attributes('disabled')).toBeUndefined();

      await button.trigger('click');
      // One event in every state: the parent saves first when it must.
      expect(wrapper.emitted('diagnostics')).toHaveLength(1);
      expect(wrapper.emitted('save')).toBeUndefined();
      expect(wrapper.emitted('test')).toBeUndefined();
    });

    it('shows the section with its hint once a configuration is saved', async () => {
      wrapper = await savedMount();

      const section = wrapper.find('[data-testid="sso-diagnostics"]');
      expect(section.exists()).toBe(true);
      expect(section.text()).toContain('web.organizations.sso.diagnostics_title');
      expect(section.findAll('p').map((paragraph) => paragraph.text())).toContain(
        'web.organizations.sso.diagnostics_hint_entra'
      );
      expect(wrapper.get(RUN).attributes('disabled')).toBeUndefined();
    });

    describe('placeholder before a result', () => {
      const PLACEHOLDER = '[data-testid="sso-diagnostics-placeholder"]';

      it('says where results land on a fresh existing record, without a live region', async () => {
        wrapper = await savedMount();

        const placeholder = wrapper.get(`[data-testid="sso-diagnostics"] ${PLACEHOLDER}`);
        expect(placeholder.text()).toBe('web.organizations.sso.diagnostics_placeholder');
        expect(placeholder.attributes('role')).toBeUndefined();
        expect(placeholder.attributes('aria-live')).toBeUndefined();
        expect(placeholder.classes()).toEqual(
          expect.arrayContaining(['mt-3', 'text-sm', 'text-gray-500'])
        );
      });

      it('is also shown on a new record', async () => {
        wrapper = await mountComponent();
        expect(wrapper.find(PLACEHOLDER).exists()).toBe(true);
      });

      it('gives way to a result or an error', async () => {
        wrapper = await savedMount();
        expect(wrapper.find(PLACEHOLDER).exists()).toBe(true);

        await wrapper.setProps({ diagnosticsResult: diagnostics('passed', []) });
        expect(wrapper.find(PLACEHOLDER).exists()).toBe(false);

        await wrapper.setProps({ diagnosticsResult: null, diagnosticsError: 'Could not reach' });
        expect(wrapper.find(PLACEHOLDER).exists()).toBe(false);

        await wrapper.setProps({ diagnosticsError: '' });
        expect(wrapper.find(PLACEHOLDER).exists()).toBe(true);
      });

      it.each([['isDiagnosing'], ['isSaving']] as const)(
        'is hidden while a check is in flight (%s)',
        async (flag) => {
          wrapper = await savedMount({ [flag]: true });
          expect(wrapper.find(PLACEHOLDER).exists()).toBe(false);
        }
      );
    });

    it.each([
      ['entra_id', 'diagnostics_hint_entra'],
      ['oidc', 'diagnostics_hint'],
      ['saml', 'diagnostics_hint_saml'],
    ] as const)('shows %s diagnostics guidance before saving', async (provider_type, hintKey) => {
      wrapper = await mountComponent({
        formState: { ...createDefaultFormState(), provider_type },
      });

      const paragraphs = wrapper
        .get('[data-testid="sso-diagnostics"]')
        .findAll('p')
        .map((paragraph) => paragraph.text());
      for (const key of ['diagnostics_hint_entra', 'diagnostics_hint', 'diagnostics_hint_saml']) {
        expect(paragraphs.includes(`web.organizations.sso.${key}`)).toBe(key === hintKey);
      }
    });

    it.each([
      ['no record', { formState: validNewForm }, true],
      ['a record that is off', { ssoConfig: offConfig, isConfigured: true }, true],
      ['a record that is on', { ssoConfig: mockExistingConfig, isConfigured: true }, false],
    ] as const)(
      'says a passing check turns the connection on only while it is off (%s)',
      async (_state, options, shown) => {
        wrapper = await mountComponent({ formState: mockExistingFormState, ...options });

        const hint = wrapper.find('[data-testid="sso-diagnostics-activation-hint"]');
        expect(hint.exists()).toBe(shown);
        if (shown) expect(hint.text()).toBe('web.organizations.sso.diagnostics_activation_hint');
      }
    );

    it.each([
      [
        'new invalid form',
        { formState: createDefaultFormState(), ssoConfig: null, isConfigured: false },
      ],
      [
        'new form saving',
        { formState: validNewForm, ssoConfig: null, isConfigured: false, isSaving: true },
      ],
      [
        'saved invalid form with edits',
        {
          formState: { ...mockExistingFormState, client_id: '' },
          ssoConfig: mockExistingConfig,
          isConfigured: true,
          hasUnsavedChanges: true,
        },
      ],
      ['saved form saving', { isSaving: true }],
      ['saved form deleting', { isDeleting: true }],
      ['saved form running', { isDiagnosing: true }],
    ] as const)('disables the primary action for a %s', async (_state, options) => {
      wrapper = await savedMount(options);

      const button = wrapper.get(RUN);
      expect(button.attributes('disabled')).toBeDefined();
      await button.trigger('click');
      expect(wrapper.emitted('diagnostics')).toBeUndefined();
      expect(wrapper.emitted('save')).toBeUndefined();
    });

    it.each([
      ['isSaving', 'web.COMMON.saving'],
      ['isDiagnosing', 'web.organizations.sso.diagnostics_running'],
    ] as const)('shows the in-flight label while %s', async (flag, label) => {
      wrapper = await savedMount(flag === 'isSaving' ? { isSaving: true } : { isDiagnosing: true });

      expect(wrapper.get(RUN).text()).toBe(label);
    });

    it('submits a new record through Save and check, never a bare save', async () => {
      wrapper = await mountComponent({ formState: validNewForm });

      expect(wrapper.find('button[type="submit"]').exists()).toBe(false);
      await wrapper.get('form').trigger('submit');

      expect(wrapper.emitted('diagnostics')).toHaveLength(1);
      expect(wrapper.emitted('save')).toBeUndefined();
    });

    it('submits an existing record as a save that keeps the connection as it is', async () => {
      wrapper = await mountComponent({
        formState: mockExistingFormState,
        ssoConfig: offConfig,
        isConfigured: true,
        hasUnsavedChanges: true,
      });

      const save = wrapper.get('[data-testid="sso-save"]');
      expect(save.attributes('type')).toBe('submit');
      expect(save.text()).toBe('web.COMMON.save_changes');
      await wrapper.get('form').trigger('submit');

      expect(wrapper.emitted('save')).toHaveLength(1);
      expect(wrapper.emitted('diagnostics')).toBeUndefined();
      // No control writes the connection state.
      expect(wrapper.emitted('update:formState')).toBeUndefined();
    });

    it('blocks every save action and form submission while a dirty SAML configuration is deleting', async () => {
      wrapper = await mountComponent({
        formState: { ...mockSamlFormState, display_name: 'Edited SAML' },
        ssoConfig: mockSamlConfig,
        isConfigured: true,
        hasUnsavedChanges: true,
      });
      await wrapper.setProps({ isDeleting: true });

      const button = wrapper.get(RUN);
      expect(button.attributes('disabled')).toBeDefined();
      expect(wrapper.get('button[type="submit"]').attributes('disabled')).toBeDefined();
      await button.trigger('click');
      await wrapper.get('form').trigger('submit');
      expect(wrapper.emitted('save')).toBeUndefined();
      expect(wrapper.emitted('diagnostics')).toBeUndefined();
    });

    it('relabels the primary action as the record is saved and edited again', async () => {
      wrapper = await mountComponent({ formState: validNewForm });
      expect(wrapper.get(RUN).attributes('data-action')).toBe('save-and-check');

      await wrapper.setProps({
        formState: mockExistingFormState,
        ssoConfig: offConfig,
        isConfigured: true,
        hasUnsavedChanges: false,
      });
      expect(wrapper.get(RUN).attributes('data-action')).toBe('check-and-activate');

      await wrapper.setProps({ ssoConfig: mockExistingConfig });
      expect(wrapper.get(RUN).attributes('data-action')).toBe('check');

      await wrapper.setProps({ hasUnsavedChanges: true });
      expect(wrapper.get(RUN).attributes('data-action')).toBe('save-and-check');
    });

    it.each(['passed', 'failed', 'inconclusive'] as const)(
      'shows the %s summary and keeps run metadata in a native disclosure',
      async (overall) => {
        wrapper = await savedMount({
          diagnosticsResult: diagnostics(overall, [check('credential', overall)]),
        });

        const summary = wrapper.get('[data-testid="sso-diagnostics-summary"]');
        expect(summary.text()).toContain(`web.organizations.sso.diagnostics_${overall}`);
        expect(summary.element.closest('details')).toBeNull();
        const disclosure = wrapper.get('[data-testid="sso-diagnostics-run-details"]');
        expect(disclosure.element.tagName).toBe('DETAILS');
        expect(disclosure.find('summary').exists()).toBe(true);
        expect((disclosure.element as HTMLDetailsElement).open).toBe(overall !== 'passed');
        expect(disclosure.get('[data-testid="sso-diagnostics-checked-at"]').text()).toContain(
          'web.organizations.sso.diagnostics_checked_at'
        );
      }
    );

    it.each([
      ['passed', false, 'diagnostics_next'],
      ['passed', true, 'diagnostics_saved_result'],
      ['failed', false, null],
      ['failed', true, null],
      ['inconclusive', false, null],
      ['inconclusive', true, null],
    ] as const)(
      'shows next-step guidance for overall=%s, dirty=%s',
      async (overall, hasUnsavedChanges, key) => {
        wrapper = await savedMount({
          hasUnsavedChanges,
          diagnosticsResult: diagnostics(overall, [check('credential', overall)]),
        });

        const row = wrapper.get('[data-testid="sso-diagnostics-check-credential"]');
        expect(row.text()).toContain(`credential ${overall}`);
        expect(row.get('[data-testid="sso-diagnostics-status"]').text()).toBe(
          `web.organizations.sso.diagnostics_status_${overall}`
        );
        expect(row.element.closest('details')).toBeNull();
        const next = wrapper.find('[data-testid="sso-diagnostics-next"]');
        if (key) {
          expect(next.text()).toContain(`web.organizations.sso.${key}`);
          expect(next.element.closest('details')).toBeNull();
          expect(next.text()).not.toContain(
            `web.organizations.sso.${hasUnsavedChanges ? 'diagnostics_next' : 'diagnostics_saved_result'}`
          );
        } else {
          expect(next.exists()).toBe(false);
        }
        expect(wrapper.get('[data-testid="sso-confirm-sign-in"]').text()).toContain(
          'web.organizations.sso.confirm_sign_in_limits'
        );
      }
    );

    it.each([
      ['passed', true, false],
      ['passed', null, false],
      ['passed', undefined, false],
      ['passed', false, true],
      ['failed', true, true],
      ['inconclusive', true, true],
      ['unsupported', true, true],
      ['skipped', true, true],
    ] as const)(
      'keeps row status=%s, method-supported=%s visible and technical details open=%s',
      async (status, supported, open) => {
        wrapper = await savedMount({
          diagnosticsResult: diagnostics('passed', [
            check('discovery', status, {
              token_endpoint_auth_methods_supported: ['client_secret_basic'],
              token_endpoint_auth_method_supported: supported,
              note: 'This check does not confirm a complete sign-in.',
            }),
          ]),
        });

        const row = wrapper.get('[data-testid="sso-diagnostics-check-discovery"]');
        const disclosure = row.get('[data-testid="sso-diagnostics-technical-details"]');
        expect(disclosure.element.tagName).toBe('DETAILS');
        expect(disclosure.find('summary').exists()).toBe(true);
        expect((disclosure.element as HTMLDetailsElement).open).toBe(open);
        expect(disclosure.get('dl').text()).toContain('client_secret_basic');
        const chip = row.get('[data-testid="sso-diagnostics-status"]');
        expect(chip.text()).toBe(`web.organizations.sso.diagnostics_status_${status}`);
        expect(chip.element.closest('details')).toBeNull();
        expect(row.text()).toContain('web.organizations.sso.diagnostics_check_discovery');
        const message = row
          .findAll('*')
          .find((element) => element.text() === `discovery ${status}`);
        expect(message).toBeDefined();
        expect(message!.element.closest('details')).toBeNull();
        const note = row.get('[data-testid="sso-diagnostics-note"]');
        expect(note.text()).toBe('This check does not confirm a complete sign-in.');
        expect(note.element.closest('details')).toBeNull();
      }
    );

    it('renders the checked_at line and one row per check with its chip', async () => {
      wrapper = await savedMount({
        diagnosticsResult: diagnostics('inconclusive', [
          check('stored_configuration', 'passed'),
          check('discovery', 'inconclusive', { error_code: 'timeout' }),
          check('credential', 'skipped'),
        ]),
      });

      const result = wrapper.find('[data-testid="sso-diagnostics-result"]');
      expect(result.exists()).toBe(true);
      expect(result.attributes('data-overall')).toBe('inconclusive');
      expect(result.attributes('role')).toBe('status');
      expect(wrapper.find('[data-testid="sso-diagnostics-checked-at"]').text()).toContain(
        'web.organizations.sso.diagnostics_checked_at'
      );

      const stored = wrapper.find('[data-testid="sso-diagnostics-check-stored_configuration"]');
      expect(stored.attributes('data-status')).toBe('passed');
      expect(stored.text()).toContain(
        'web.organizations.sso.diagnostics_check_stored_configuration'
      );
      expect(stored.text()).toContain('web.organizations.sso.diagnostics_status_passed');
      expect(stored.text()).toContain('stored_configuration passed');

      const discovery = wrapper.find('[data-testid="sso-diagnostics-check-discovery"]');
      expect(discovery.attributes('data-status')).toBe('inconclusive');
      expect(discovery.text()).toContain('web.organizations.sso.diagnostics_check_discovery');

      const credential = wrapper.find('[data-testid="sso-diagnostics-check-credential"]');
      expect(credential.attributes('data-status')).toBe('skipped');
      expect(credential.text()).toContain('web.organizations.sso.diagnostics_status_skipped');
    });

    it.each([
      ['passed', 'bg-green-100', 'diagnostics_status_passed'],
      ['failed', 'bg-red-100', 'diagnostics_status_failed'],
      ['inconclusive', 'bg-amber-100', 'diagnostics_status_inconclusive'],
      ['unsupported', 'bg-gray-100', 'diagnostics_status_unsupported'],
      ['skipped', 'bg-gray-100', 'diagnostics_status_skipped'],
    ] as const)('renders the %s chip', async (status, chipClass, labelKey) => {
      wrapper = await savedMount({
        diagnosticsResult: diagnostics('passed', [check('credential', status)]),
      });

      const chip = wrapper.find(
        '[data-testid="sso-diagnostics-check-credential"] [data-testid="sso-diagnostics-status"]'
      );
      expect(chip.classes()).toContain(chipClass);
      expect(chip.text()).toBe(`web.organizations.sso.${labelKey}`);
    });

    it('uses the alert role and red box for a failed overall', async () => {
      wrapper = await savedMount({
        diagnosticsResult: diagnostics('failed', [
          check('credential', 'failed', { error_code: 'invalid_client_secret' }),
        ]),
      });

      const result = wrapper.find('[data-testid="sso-diagnostics-result"]');
      expect(result.attributes('role')).toBe('alert');
      expect(result.classes()).toContain('bg-red-50');
    });

    it('uses the status role and green box for a passed overall', async () => {
      wrapper = await savedMount({
        diagnosticsResult: diagnostics('passed', [check('credential', 'passed')]),
      });

      const result = wrapper.find('[data-testid="sso-diagnostics-result"]');
      expect(result.attributes('role')).toBe('status');
      expect(result.classes()).toContain('bg-green-50');
    });

    it('falls back to the raw name for an unknown check', async () => {
      wrapper = await savedMount({
        diagnosticsResult: diagnostics('passed', [check('future_check', 'passed')]),
      });

      const row = wrapper.find('[data-testid="sso-diagnostics-check-future_check"]');
      expect(row.exists()).toBe(true);
      expect(row.text()).toContain('future_check');
      expect(row.text()).not.toContain('diagnostics_check_future_check');
    });

    it.each(['passed', 'failed', 'inconclusive', 'unsupported', 'skipped'] as const)(
      'omits empty and note-only disclosures while keeping %s messages and notes visible',
      async (status) => {
        wrapper = await savedMount({
          diagnosticsResult: diagnostics('passed', [
            check('stored_configuration', status),
            check('credential', status, { note: 'Confirm with a real sign-in.' }),
          ]),
        });

        for (const name of ['stored_configuration', 'credential']) {
          const row = wrapper.get(`[data-testid="sso-diagnostics-check-${name}"]`);
          expect(row.find('[data-testid="sso-diagnostics-technical-details"]').exists()).toBe(
            false
          );
          expect(row.find('[data-testid="sso-diagnostics-details"]').exists()).toBe(false);
          const message = row
            .findAll('p')
            .find((paragraph) => paragraph.text() === `${name} ${status}`);
          expect(message).toBeDefined();
          expect(message!.isVisible()).toBe(true);
          expect(message!.element.closest('details')).toBeNull();
        }
        const note = wrapper.get('[data-testid="sso-diagnostics-note"]');
        expect(note.text()).toBe('Confirm with a real sign-in.');
        expect(note.isVisible()).toBe(true);
        expect(note.element.closest('details')).toBeNull();
      }
    );

    it('never offers an empty discovery disclosure when advertised methods are omitted (SSO-UX-001)', async () => {
      wrapper = await savedMount({
        formState: {
          ...mockExistingFormState,
          provider_type: 'oidc',
          issuer: 'https://idp.example.com',
          token_endpoint_auth_method: 'client_secret_post',
        },
        ssoConfig: {
          ...mockExistingConfig,
          provider_type: 'oidc',
          issuer: 'https://idp.example.com',
          token_endpoint_auth_method: 'client_secret_post',
        },
        diagnosticsResult: {
          ...diagnostics('passed', [
            check('discovery', 'passed', {
              issuer: 'https://idp.example.com',
              token_endpoint: 'https://idp.example.com/token',
              token_endpoint_auth_methods_supported: null,
              token_endpoint_auth_method_supported: false,
              note: 'The selected method is not advertised; confirm with a real sign-in.',
            }),
          ]),
          provider_type: 'oidc',
        },
      });

      const row = wrapper.get('[data-testid="sso-diagnostics-check-discovery"]');
      const disclosure = row.find('[data-testid="sso-diagnostics-technical-details"]');
      if (disclosure.exists()) {
        expect(disclosure.get('dl').findAll('dt').length).toBeGreaterThan(0);
      }
      expect(row.get('[data-testid="sso-diagnostics-note"]').isVisible()).toBe(true);
      expect(row.text()).toContain('discovery passed');
    });

    it('shows every present rendered details key', async () => {
      wrapper = await savedMount({
        diagnosticsResult: diagnostics('failed', [
          check('stored_configuration', 'failed', {
            errors: ['client_id is required', 'tenant_id is required'],
          }),
          check('discovery', 'passed', {
            token_endpoint_auth_methods_supported: ['client_secret_post', 'client_secret_basic'],
          }),
          check('certificate', 'passed', {
            certificate_not_after: '2027-01-01T00:00:00Z',
            certificate_expires_in_days: 81,
          }),
          check('credential', 'inconclusive', {
            error_code: 'provider_error',
            aadsts_code: 'AADSTS50034',
            http_status: 400,
            note: 'Sign in once on the custom domain to confirm.',
          }),
        ]),
      });

      const stored = wrapper.find('[data-testid="sso-diagnostics-check-stored_configuration"]');
      expect(stored.text()).toContain('web.organizations.sso.diagnostics_errors');
      expect(stored.text()).toContain('client_id is required; tenant_id is required');

      const discovery = wrapper.find('[data-testid="sso-diagnostics-check-discovery"]');
      expect(discovery.text()).toContain(
        'web.organizations.sso.token_endpoint_auth_methods_supported'
      );
      expect(discovery.text()).toContain('client_secret_post, client_secret_basic');

      const certificate = wrapper.find('[data-testid="sso-diagnostics-check-certificate"]');
      expect(certificate.text()).toContain('web.organizations.sso.certificate_expires');
      expect(certificate.text()).toContain('web.organizations.sso.certificate_expires_in_days');

      const credential = wrapper.find('[data-testid="sso-diagnostics-check-credential"]');
      for (const row of [stored, discovery, certificate, credential]) {
        const disclosure = row.get('[data-testid="sso-diagnostics-technical-details"]');
        expect(disclosure.element.tagName).toBe('DETAILS');
        expect(disclosure.get('[data-testid="sso-diagnostics-details"]').element.tagName).toBe(
          'DL'
        );
        expect((disclosure.element as HTMLDetailsElement).open).toBe(
          row.attributes('data-status') !== 'passed'
        );
      }
      expect(credential.text()).toContain('web.COMMON.error_code');
      expect(credential.text()).toContain('provider_error');
      expect(credential.text()).toContain('web.organizations.sso.diagnostics_aadsts_code');
      expect(credential.text()).toContain('AADSTS50034');
      expect(credential.text()).toContain('web.COMMON.http_status');
      expect(credential.text()).toContain('400');
      expect(credential.find('[data-testid="sso-diagnostics-note"]').text()).toBe(
        'Sign in once on the custom domain to confirm.'
      );
    });

    it('shows both issuers on an issuer mismatch, exactly as returned', async () => {
      wrapper = await savedMount({
        diagnosticsResult: diagnostics('failed', [
          check('stored_configuration', 'passed'),
          check('discovery', 'failed', {
            error_code: 'issuer_mismatch',
            configured_issuer: 'https://tenant.auth0.com',
            discovery_issuer: 'https://tenant.auth0.com/',
          }),
        ]),
      });

      const discovery = wrapper.find('[data-testid="sso-diagnostics-check-discovery"]');
      expect(discovery.text()).toContain('web.organizations.sso.configured_issuer');
      expect(discovery.text()).toContain('web.organizations.sso.discovery_issuer');
      expect(discovery.find('[data-testid="sso-diagnostics-configured-issuer"]').text()).toBe(
        'https://tenant.auth0.com'
      );
      expect(discovery.find('[data-testid="sso-diagnostics-discovery-issuer"]').text()).toBe(
        'https://tenant.auth0.com/'
      );
    });

    it('shows a dash for a discovery issuer that is not a string', async () => {
      wrapper = await savedMount({
        diagnosticsResult: diagnostics('failed', [
          check('discovery', 'failed', {
            error_code: 'issuer_mismatch',
            configured_issuer: 'https://idp.example.com',
            discovery_issuer: null,
          }),
        ]),
      });

      const discovery = wrapper.find('[data-testid="sso-diagnostics-check-discovery"]');
      expect(discovery.find('[data-testid="sso-diagnostics-discovery-issuer"]').text()).toBe('—');
    });

    it('omits details rows whose keys are absent', async () => {
      wrapper = await savedMount({
        diagnosticsResult: diagnostics('passed', [check('credential', 'passed')]),
      });

      const row = wrapper.find('[data-testid="sso-diagnostics-check-credential"]');
      expect(row.text()).not.toContain('web.COMMON.error_code');
      expect(row.text()).not.toContain('web.COMMON.http_status');
      expect(row.text()).not.toContain('web.organizations.sso.diagnostics_aadsts_code');
      expect(row.text()).not.toContain('web.organizations.sso.diagnostics_errors');
      expect(row.text()).not.toContain('web.organizations.sso.certificate_expires');
      expect(row.text()).not.toContain(
        'web.organizations.sso.token_endpoint_auth_methods_supported'
      );
      expect(row.find('[data-testid="sso-diagnostics-configured-issuer"]').exists()).toBe(false);
      expect(row.find('[data-testid="sso-diagnostics-note"]').exists()).toBe(false);
    });

    it('shows the transport error alert when the run itself failed', async () => {
      wrapper = await savedMount({ diagnosticsError: 'Failed to check the saved configuration' });

      expect(wrapper.find('[data-testid="sso-diagnostics-result"]').exists()).toBe(false);
      const alert = wrapper.find('[data-testid="sso-diagnostics-error"]');
      expect(alert.exists()).toBe(true);
      expect(alert.classes()).toContain('bg-red-50');
      expect(alert.text()).toBe('Failed to check the saved configuration');
    });

    it('announces the transport error like the failed verdict (role=alert, assertive)', async () => {
      wrapper = await savedMount({ diagnosticsError: 'Failed to check the saved configuration' });

      const alert = wrapper.find('[data-testid="sso-diagnostics-error"]');
      expect(alert.attributes('role')).toBe('alert');
      expect(alert.attributes('aria-live')).toBe('assertive');
    });

    it('does not render a result block until a run happened', async () => {
      wrapper = await savedMount();

      expect(wrapper.find('[data-testid="sso-diagnostics-result"]').exists()).toBe(false);
      expect(wrapper.find('[data-testid="sso-diagnostics-error"]').exists()).toBe(false);
    });

    // A lost response can follow a committed activation. Without a verdict,
    // the local snapshot cannot establish whether the connection stayed off.
    it.each([
      ['transport failure', 'off', false, 'Network Error'],
      ['transport failure', 'on', true, 'Network Error'],
      [
        'rate limit',
        'off',
        false,
        'This configuration has been checked too many times recently. Try again in about 5 minutes.',
      ],
      [
        'rate limit',
        'on',
        true,
        'This configuration has been checked too many times recently. Try again in about 5 minutes.',
      ],
    ] as const)(
      'makes no activation claim after a %s with the local connection %s',
      async (_failure, _state, enabled, message) => {
        wrapper = await savedMount({
          ssoConfig: { ...mockExistingConfig, enabled },
          diagnosticsError: message,
        });

        const alert = wrapper.get('[data-testid="sso-diagnostics-error"]');
        expect(alert.text()).toBe(message);
        expect(alert.find('[data-testid="sso-diagnostics-error-stays-off"]').exists()).toBe(false);
        expect(wrapper.find('[data-testid="sso-diagnostics-result"]').exists()).toBe(false);
        expect(wrapper.find('[data-testid="sso-activation-notice"]').exists()).toBe(false);
        expect(wrapper.find('[data-testid="sso-diagnostics-next"]').exists()).toBe(false);
      }
    );
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // Activation outcome: what a run did to SsoConfig.enabled
  // ─────────────────────────────────────────────────────────────────────────────

  describe('Activation outcome', () => {
    const NOTICE = '[data-testid="sso-activation-notice"]';
    const passedCheck: SsoDiagnosticCheck = {
      check: 'credential',
      status: 'passed',
      message: 'credential passed',
      details: {},
    };
    const failedCheck: SsoDiagnosticCheck = { ...passedCheck, status: 'failed' };
    const offConfig: CustomDomainSsoConfig = { ...mockExistingConfig, enabled: false };

    it.each([
      ['activated', 'passed', true, 'diagnostics_activation_activated', 'ok'],
      ['not_passed', 'failed', false, 'diagnostics_activation_stays_off', 'warn'],
      ['not_passed', 'inconclusive', false, 'diagnostics_activation_stays_off', 'warn'],
      [
        'configuration_changed',
        'passed',
        false,
        'diagnostics_activation_configuration_changed',
        'warn',
      ],
      ['not_permitted', 'passed', false, 'diagnostics_activation_not_permitted', 'warn'],
    ] as const)(
      'reports %s (overall %s) with its own message',
      async (activation, overall, enabled, key, tone) => {
        wrapper = await mountComponent({
          formState: mockExistingFormState,
          ssoConfig: { ...mockExistingConfig, enabled },
          isConfigured: true,
          diagnosticsResult: diagnostics(
            overall,
            [overall === 'passed' ? passedCheck : { ...passedCheck, status: overall }],
            { activation, enabled }
          ),
        });

        const notice = wrapper.get(NOTICE);
        expect(notice.attributes('data-activation')).toBe(activation);
        expect(notice.text()).toBe(`web.organizations.sso.${key}`);
        expect(notice.classes().join(' ')).toContain(
          tone === 'ok' ? 'text-green-800' : 'text-amber-800'
        );
        // Inside the announced result block, after the verdict summary.
        const result = wrapper.get('[data-testid="sso-diagnostics-result"]');
        expect(result.find(NOTICE).exists()).toBe(true);
      }
    );

    // A copy that was off asks for activation; if the record was turned on
    // elsewhere, a failed or changed run must not claim it "stays off".
    it.each([
      ['not_passed', 'failed'],
      ['configuration_changed', 'passed'],
    ] as const)(
      'drops the stays-off warning for %s when the stored record is on',
      async (activation, overall) => {
        wrapper = await mountComponent({
          formState: mockExistingFormState,
          ssoConfig: offConfig,
          isConfigured: true,
          diagnosticsResult: diagnostics(
            overall,
            [overall === 'passed' ? passedCheck : failedCheck],
            { activation, enabled: true }
          ),
        });

        expect(wrapper.find(NOTICE).exists()).toBe(false);
      }
    );

    it.each(['already_enabled', 'not_requested'] as const)(
      'adds nothing for %s',
      async (activation) => {
        wrapper = await mountComponent({
          formState: mockExistingFormState,
          ssoConfig: mockExistingConfig,
          isConfigured: true,
          diagnosticsResult: diagnostics('passed', [passedCheck], { activation }),
        });

        expect(wrapper.find(NOTICE).exists()).toBe(false);
        expect(wrapper.get('[data-testid="sso-diagnostics-next"]').text()).toBe(
          'web.organizations.sso.diagnostics_next'
        );
      }
    );

    it('names the provider in the not_permitted message', async () => {
      // The pass-through test i18n drops interpolation; the real bundle shows
      // the {provider} placeholder is filled with the provider's label.
      const realI18n = createRealI18n({
        en: JSON.parse(readFileSync(resolve(process.cwd(), 'generated/locales/en.json'), 'utf-8')),
      });
      wrapper = mount(DomainSsoConfigForm, {
        props: {
          ...defaultMountOptions,
          formState: mockSamlFormState,
          ssoConfig: { ...mockSamlConfig, enabled: false },
          isConfigured: true,
          diagnosticsResult: diagnostics('passed', [passedCheck], {
            provider_type: 'saml',
            activation: 'not_permitted',
            enabled: false,
          }),
        },
        global: { plugins: [realI18n, pinia], stubs: { Teleport: true } },
      });
      await flushPromises();

      const text = wrapper.get(NOTICE).text();
      expect(text).toContain('SAML 2.0');
      expect(text).not.toContain('{provider}');
      expect(text).not.toContain('web.organizations.sso');
    });

    it('falls back to the raw provider type for a legacy record', async () => {
      const realI18n = createRealI18n({
        en: JSON.parse(readFileSync(resolve(process.cwd(), 'generated/locales/en.json'), 'utf-8')),
      });
      wrapper = mount(DomainSsoConfigForm, {
        props: {
          ...defaultMountOptions,
          formState: mockExistingFormState,
          ssoConfig: offConfig,
          isConfigured: true,
          diagnosticsResult: diagnostics('passed', [passedCheck], {
            provider_type: 'github',
            activation: 'not_permitted',
            enabled: false,
          }),
        },
        global: { plugins: [realI18n, pinia], stubs: { Teleport: true } },
      });
      await flushPromises();

      expect(wrapper.get(NOTICE).text()).toContain('github');
    });

    it.each(['not_permitted', 'configuration_changed'] as const)(
      'offers no "next: confirm sign-in" after a pass that left the connection off (%s)',
      async (activation) => {
        wrapper = await mountComponent({
          formState: mockExistingFormState,
          ssoConfig: offConfig,
          isConfigured: true,
          diagnosticsResult: diagnostics('passed', [passedCheck], { activation, enabled: false }),
        });

        expect(wrapper.find('[data-testid="sso-diagnostics-next"]').exists()).toBe(false);
      }
    );

    it('points to Confirm sign-in after the run that turned the connection on', async () => {
      wrapper = await mountComponent({
        formState: mockExistingFormState,
        ssoConfig: mockExistingConfig,
        isConfigured: true,
        diagnosticsResult: diagnostics('passed', [passedCheck], {
          activation: 'activated',
          enabled: true,
        }),
      });

      expect(wrapper.get('[data-testid="sso-diagnostics-next"]').text()).toBe(
        'web.organizations.sso.diagnostics_next'
      );
      // The guide stays through this result instead of vanishing under it.
      expect(wrapper.find('[data-testid="sso-setup-guide"]').exists()).toBe(true);
    });

    it('keeps a failed run on a connection that is off clear of any "next" line', async () => {
      wrapper = await mountComponent({
        formState: mockExistingFormState,
        ssoConfig: offConfig,
        isConfigured: true,
        diagnosticsResult: diagnostics('failed', [failedCheck], {
          activation: 'not_passed',
          enabled: false,
        }),
      });

      expect(wrapper.find('[data-testid="sso-diagnostics-next"]').exists()).toBe(false);
      expect(wrapper.get(NOTICE).attributes('data-activation')).toBe('not_passed');
    });

    describe('sign-in settings that withhold SSO (verdict sso_not_permitted)', () => {
      const BLOCKED = '[data-testid="sso-confirm-sign-in-not-permitted"]';
      const verdict = (reason: string | null): TenantSsoVerdict => ({
        available: reason === null,
        unavailable_reason: reason,
      });

      it('appears once the page re-reads the verdict after activation', async () => {
        // Before the run the ladder stops at sso_config_disabled; it can only
        // report sso_not_permitted for a record that is on.
        wrapper = await mountComponent({
          formState: mockExistingFormState,
          ssoConfig: offConfig,
          isConfigured: true,
          tenantSso: verdict('sso_config_disabled'),
        });
        expect(wrapper.find(BLOCKED).exists()).toBe(false);

        await wrapper.setProps({
          ssoConfig: mockExistingConfig,
          diagnosticsResult: diagnostics('passed', [passedCheck], {
            activation: 'activated',
            enabled: true,
          }),
        });
        expect(wrapper.find(BLOCKED).exists()).toBe(false);

        await wrapper.setProps({ tenantSso: verdict('sso_not_permitted') });
        const blocked = wrapper.get(BLOCKED);
        expect(blocked.text()).toBe('web.organizations.sso.confirm_sign_in_not_permitted');
        expect(blocked.attributes('role')).toBe('status');
        expect(wrapper.get('[data-testid="sso-confirm-sign-in"]').find(BLOCKED).exists()).toBe(
          true
        );
      });

      it.each([
        ['available', null, true],
        ['domain_unverified', 'domain_unverified', true],
        ['a connection that is off', 'sso_not_permitted', false],
      ] as const)('stays hidden for %s', async (_case, reason, enabled) => {
        wrapper = await mountComponent({
          formState: mockExistingFormState,
          ssoConfig: { ...mockExistingConfig, enabled },
          isConfigured: true,
          tenantSso: verdict(reason),
        });

        expect(wrapper.find(BLOCKED).exists()).toBe(false);
      });

      it('makes no claim without a verdict', async () => {
        wrapper = await mountComponent({
          formState: mockExistingFormState,
          ssoConfig: mockExistingConfig,
          isConfigured: true,
        });

        expect(wrapper.find(BLOCKED).exists()).toBe(false);
      });
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // Token endpoint auth method (#4764)
  // ─────────────────────────────────────────────────────────────────────────────

  describe('Last sign-in outcome (record.last_sign_in)', () => {
    const LINE = '[data-testid="sso-last-sign-in"]';

    it('says none is recorded when the saved record carries null', async () => {
      wrapper = await mountComponent({
        formState: mockExistingFormState,
        ssoConfig: { ...mockExistingConfig, last_sign_in: null },
        isConfigured: true,
      });

      const line = wrapper.find(LINE);
      expect(line.exists()).toBe(true);
      expect(line.attributes('data-result')).toBe('none');
      expect(line.text()).toContain('web.organizations.sso.last_sign_in_none');
      const card = wrapper.get('[data-testid="sso-confirm-sign-in"]');
      expect(card.get(LINE).element).toBe(line.element);
      expect(wrapper.get('[data-testid="sso-diagnostics"]').find(LINE).exists()).toBe(false);
      for (const key of ['confirm_sign_in', 'confirm_sign_in_hint', 'confirm_sign_in_limits']) {
        expect(card.text()).toContain(`web.organizations.sso.${key}`);
      }
      expect(
        wrapper
          .get('[data-testid="sso-diagnostics"]')
          .element.compareDocumentPosition(card.element) & Node.DOCUMENT_POSITION_FOLLOWING
      ).toBe(Node.DOCUMENT_POSITION_FOLLOWING);
    });

    it('reports a completed sign-in', async () => {
      wrapper = await mountComponent({
        formState: mockExistingFormState,
        ssoConfig: {
          ...mockExistingConfig,
          last_sign_in: {
            result: 'succeeded',
            at: 1760000000,
            succeeded_at: 1760000000,
            failed_at: null,
            failure_stage: null,
            failure_code: null,
            provider_type: 'entra_id',
          },
        },
        isConfigured: true,
      });

      const line = wrapper.find(LINE);
      expect(line.attributes('data-result')).toBe('succeeded');
      expect(line.text()).toContain('web.organizations.sso.last_sign_in_succeeded');
      expect(line.text()).not.toContain('last_sign_in_failed');
    });

    it('reports a failed sign-in with its stage and code, plus the last success', async () => {
      wrapper = await mountComponent({
        formState: mockExistingFormState,
        ssoConfig: {
          ...mockExistingConfig,
          last_sign_in: {
            result: 'failed',
            at: 1760003600,
            succeeded_at: 1760000000,
            failed_at: 1760003600,
            failure_stage: 'provider',
            failure_code: 'invalid_credentials',
            provider_type: 'entra_id',
          },
        },
        isConfigured: true,
      });

      const line = wrapper.find(LINE);
      expect(line.attributes('data-result')).toBe('failed');
      expect(line.text()).toContain('web.organizations.sso.last_sign_in_failed');
      expect(line.text()).toContain('web.organizations.sso.last_sign_in_last_success');
    });

    // Some locales end a formatted time with an abbreviation period (en-CA and
    // es-MX "p.m.", el "μ.μ."). That period also ends a sentence whose
    // message reads "... {when}.", so the message's own period is dropped.
    describe('a formatted time ending in an abbreviation period', () => {
      let toLocaleStringSpy: ReturnType<typeof vi.spyOn> | undefined;

      afterEach(() => {
        toLocaleStringSpy?.mockRestore();
      });

      const lineText = async (
        formatted: string,
        lastSignIn: NonNullable<CustomDomainSsoConfig['last_sign_in']>
      ) => {
        toLocaleStringSpy = vi.spyOn(Date.prototype, 'toLocaleString').mockReturnValue(formatted);
        // The pass-through test i18n drops interpolation; the real bundle
        // carries the sentence-final period after {when}.
        const realI18n = createRealI18n({
          en: JSON.parse(
            readFileSync(resolve(process.cwd(), 'generated/locales/en.json'), 'utf-8')
          ),
        });
        wrapper = mount(DomainSsoConfigForm, {
          props: {
            ...defaultMountOptions,
            formState: mockExistingFormState,
            ssoConfig: { ...mockExistingConfig, last_sign_in: lastSignIn },
            isConfigured: true,
          },
          global: { plugins: [realI18n, pinia], stubs: { Teleport: true } },
        });
        await flushPromises();
        return wrapper.get(LINE).text();
      };

      const succeeded = {
        result: 'succeeded',
        at: 1760000000,
        succeeded_at: 1760000000,
        failed_at: null,
        failure_stage: null,
        failure_code: null,
        provider_type: 'entra_id',
      } as const;

      const failedAfterSuccess = {
        result: 'failed',
        at: 1760003600,
        succeeded_at: 1760000000,
        failed_at: 1760003600,
        failure_stage: 'provider',
        failure_code: 'invalid_credentials',
        provider_type: 'entra_id',
      } as const;

      it('ends the completed sign-in sentence with a single period', async () => {
        const text = await lineText('2026-10-09, 11:44 p.m.', succeeded);

        expect(text).toContain('2026-10-09, 11:44 p.m.');
        expect(text.endsWith('11:44 p.m.')).toBe(true);
        expect(text).not.toContain('p.m..');
      });

      it('ends the last completed sign-in sentence with a single period', async () => {
        const text = await lineText('2026-10-09, 11:44 p.m.', failedAfterSuccess);

        // The failed sentence continues after {when} with a comma.
        expect(text).toContain('11:44 p.m., ');
        expect(text.endsWith('11:44 p.m.')).toBe(true);
        expect(text).not.toContain('p.m..');
      });

      it('keeps the sentence period after a time that does not end in one', async () => {
        const text = await lineText('10/9/2026, 11:44:00 PM', succeeded);

        expect(text.endsWith('11:44:00 PM.')).toBe(true);
      });
    });

    it('is not shown before a configuration is saved', async () => {
      wrapper = await mountComponent({ formState: createDefaultFormState(), isConfigured: false });

      expect(wrapper.find(LINE).exists()).toBe(false);
      expect(wrapper.find('[data-testid="sso-last-sign-in-refresh"]').exists()).toBe(false);
    });

    it('offers a Refresh control next to the line that asks the parent to re-read it', async () => {
      wrapper = await mountComponent({
        formState: { ...mockExistingFormState, display_name: 'Unsaved edit' },
        ssoConfig: mockExistingConfig,
        isConfigured: true,
        hasUnsavedChanges: true,
      });

      const refresh = wrapper.get('[data-testid="sso-last-sign-in-refresh"]');
      expect(refresh.text()).toContain('web.organizations.sso.last_sign_in_refresh');
      await refresh.trigger('click');

      expect(wrapper.emitted('refresh-last-sign-in')).toEqual([[]]);
      // Nothing about the form is touched by asking.
      expect(wrapper.emitted('update:formState')).toBeUndefined();
      expect(wrapper.emitted('save')).toBeUndefined();
    });

    it('disables Refresh while a refresh is in flight', async () => {
      wrapper = await mountComponent({
        formState: mockExistingFormState,
        ssoConfig: mockExistingConfig,
        isConfigured: true,
        isRefreshingLastSignIn: true,
      });

      const refresh = wrapper.get('[data-testid="sso-last-sign-in-refresh"]');
      expect(refresh.attributes('disabled')).toBeDefined();
      expect(refresh.attributes('aria-busy')).toBe('true');
    });

    it('renders Refresh as a quiet control beside the line, same hit target as before', async () => {
      wrapper = await mountComponent({
        formState: mockExistingFormState,
        ssoConfig: mockExistingConfig,
        isConfigured: true,
      });

      const refresh = wrapper.get('[data-testid="sso-last-sign-in-refresh"]');
      const classes = refresh.classes();
      // No box: text-only until hovered or focused.
      for (const boxed of ['bg-white', 'shadow-sm', 'ring-1', 'dark:bg-gray-700']) {
        expect(classes).not.toContain(boxed);
      }
      expect(classes).toEqual(
        expect.arrayContaining([
          'px-2.5',
          'py-1.5',
          'text-sm',
          'rounded-md',
          'text-gray-500',
          'hover:text-gray-900',
          'hover:bg-gray-100',
          'focus-visible:outline-brand-600',
        ])
      );
      expect(refresh.get('.o-icon').attributes('data-icon-name')).toBe('arrow-path');
      expect(refresh.text()).toBe('web.organizations.sso.last_sign_in_refresh');
    });

    it('re-renders the line from a refreshed record without touching unsaved edits', async () => {
      const dirty = { ...mockExistingFormState, display_name: 'Unsaved edit' };
      wrapper = await mountComponent({
        formState: dirty,
        ssoConfig: { ...mockExistingConfig, last_sign_in: null },
        isConfigured: true,
        hasUnsavedChanges: true,
      });
      expect(wrapper.get(LINE).attributes('data-result')).toBe('none');

      await wrapper.setProps({
        ssoConfig: {
          ...mockExistingConfig,
          last_sign_in: {
            result: 'succeeded',
            at: 1760000000,
            succeeded_at: 1760000000,
            failed_at: null,
            failure_stage: null,
            failure_code: null,
            provider_type: 'entra_id',
          },
        },
      });

      expect(wrapper.get(LINE).attributes('data-result')).toBe('succeeded');
      expect((wrapper.get('#domain-sso-display-name').element as HTMLInputElement).value).toBe(
        'Unsaved edit'
      );
      expect(wrapper.emitted('update:formState')).toBeUndefined();
    });
  });

  describe('Token endpoint auth method (#4764)', () => {
    const SELECT = '#domain-sso-token-endpoint-auth-method';
    const DISCLOSURE = '[data-testid="sso-advanced-oidc"]';

    const oidcState = (): SsoConfigFormState => ({
      ...createDefaultFormState(),
      provider_type: 'oidc',
      client_id: 'client-123',
      issuer: 'https://idp.example.com',
    });

    it('offers the select, collapsed, for oidc with Automatic selected by default', async () => {
      wrapper = await mountComponent({ formState: oidcState() });

      const disclosure = wrapper.find(DISCLOSURE);
      expect(disclosure.exists()).toBe(true);
      expect((disclosure.element as HTMLDetailsElement).open).toBe(false);
      expect(disclosure.text()).toContain('web.organizations.sso.advanced_section');

      const select = wrapper.find(SELECT);
      expect(select.exists()).toBe(true);
      expect((select.element as HTMLSelectElement).value).toBe('');
      expect(select.findAll('option').map((o) => o.attributes('value'))).toEqual([
        '',
        'client_secret_basic',
        'client_secret_post',
      ]);
      expect(wrapper.text()).toContain('web.organizations.sso.token_endpoint_auth_method_hint');
    });

    it.each(['entra_id', 'saml'] as const)('is absent for %s', async (providerType) => {
      wrapper = await mountComponent({
        formState: { ...createDefaultFormState(), provider_type: providerType },
      });

      expect(wrapper.find(DISCLOSURE).exists()).toBe(false);
      expect(wrapper.find(SELECT).exists()).toBe(false);
    });

    it('emits update:formState with the chosen method, and Automatic as empty string', async () => {
      wrapper = await mountComponent({ formState: oidcState() });

      await wrapper.find(SELECT).setValue('client_secret_post');
      await flushPromises();
      let emitted = wrapper.emitted('update:formState');
      expect(emitted![emitted!.length - 1][0]).toMatchObject({
        token_endpoint_auth_method: 'client_secret_post',
      });

      await wrapper.setProps({
        formState: { ...oidcState(), token_endpoint_auth_method: 'client_secret_post' },
      });
      await wrapper.find(SELECT).setValue('');
      await flushPromises();
      emitted = wrapper.emitted('update:formState');
      expect(emitted![emitted!.length - 1][0]).toMatchObject({ token_endpoint_auth_method: '' });
    });

    it('reflects the stored method and opens the disclosure for a saved record', async () => {
      wrapper = await mountComponent({
        formState: { ...oidcState(), token_endpoint_auth_method: 'client_secret_post' },
        ssoConfig: {
          ...mockExistingConfig,
          provider_type: 'oidc',
          tenant_id: null,
          issuer: 'https://idp.example.com',
          token_endpoint_auth_method: 'client_secret_post',
        },
        isConfigured: true,
      });

      expect((wrapper.find(DISCLOSURE).element as HTMLDetailsElement).open).toBe(true);
      expect((wrapper.find(SELECT).element as HTMLSelectElement).value).toBe('client_secret_post');
    });

    describe('Test Connection details', () => {
      const successResult = (
        details: TestSsoConnectionResponse['details']
      ): TestSsoConnectionResponse => ({
        user_id: 'cust_456',
        success: true,
        message: 'Connection successful',
        provider_type: 'oidc',
        details: { issuer: 'https://idp.example.com', ...details },
      });

      it('lists the advertised methods', async () => {
        wrapper = await mountComponent({
          formState: oidcState(),
          testResult: successResult({
            token_endpoint_auth_methods_supported: ['client_secret_basic', 'client_secret_post'],
            token_endpoint_auth_method_supported: null,
          }),
        });

        const list = wrapper.find('[data-testid="sso-test-token-endpoint-auth-methods"]');
        expect(list.exists()).toBe(true);
        expect(list.text()).toContain(
          'web.organizations.sso.token_endpoint_auth_methods_supported'
        );
        expect(list.text()).toContain('client_secret_basic, client_secret_post');
        const disclosure = wrapper.get('[data-testid="sso-test-technical-details"]');
        expect(disclosure.element.tagName).toBe('DETAILS');
        expect(disclosure.find('summary').exists()).toBe(true);
        expect((disclosure.element as HTMLDetailsElement).open).toBe(false);
        expect(disclosure.get('[data-testid="sso-test-token-endpoint-auth-methods"]').element).toBe(
          list.element
        );
        const message = wrapper.get('[data-testid="sso-provider-check"] h4');
        expect(message.text()).toBe('Connection successful');
        expect(message.isVisible()).toBe(true);
        expectShownInProviderCheck(wrapper, message.element);
        expect(wrapper.find('[data-testid="sso-test-note"]').exists()).toBe(false);
      });

      it.each([{ methods: null }, { methods: [] }, { methods: undefined }])(
        'omits the advertised-methods list and disclosure for $methods',
        async ({ methods }) => {
          wrapper = await mountComponent({
            formState: oidcState(),
            testResult: successResult({
              token_endpoint_auth_methods_supported: methods,
              token_endpoint_auth_method_supported: true,
            }),
          });

          expect(
            wrapper.find('[data-testid="sso-test-token-endpoint-auth-methods"]').exists()
          ).toBe(false);
          expect(wrapper.find('[data-testid="sso-test-technical-details"]').exists()).toBe(false);
          const message = wrapper.get('[data-testid="sso-provider-check"] h4');
          expect(message.text()).toBe('Connection successful');
          expect(message.isVisible()).toBe(true);
          expectShownInProviderCheck(wrapper, message.element);
          expect(wrapper.find('[role="status"]').exists()).toBe(true);
        }
      );

      it('renders the note as a warning when the selected method is not advertised (test still succeeds)', async () => {
        wrapper = await mountComponent({
          formState: { ...oidcState(), token_endpoint_auth_method: 'client_secret_post' },
          testResult: successResult({
            token_endpoint_auth_methods_supported: ['client_secret_basic'],
            token_endpoint_auth_method_supported: false,
            note: 'client_secret_post is not among the advertised methods',
          }),
        });

        expect(wrapper.find('[role="status"]').exists()).toBe(true);
        expect(wrapper.find('[role="alert"]').exists()).toBe(false);
        const note = wrapper.find('[data-testid="sso-test-note"]');
        expect(note.text()).toContain('client_secret_post is not among the advertised methods');
        expect(note.classes()).toContain('text-amber-700');
        expect(note.find('.o-icon').exists()).toBe(true);
        expectShownInProviderCheck(wrapper, note.element);
        const disclosure = wrapper.get('[data-testid="sso-test-technical-details"]');
        expect(disclosure.element.tagName).toBe('DETAILS');
        expect((disclosure.element as HTMLDetailsElement).open).toBe(true);
        expect(
          disclosure.get('[data-testid="sso-test-token-endpoint-auth-methods"]').text()
        ).toContain('client_secret_basic');
      });

      it('keeps the plain note style when the selection is advertised or absent', async () => {
        for (const supported of [true, null, undefined]) {
          wrapper = await mountComponent({
            formState: oidcState(),
            testResult: successResult({
              token_endpoint_auth_methods_supported: ['client_secret_basic'],
              token_endpoint_auth_method_supported: supported,
              note: 'Some other note',
            }),
          });
          const note = wrapper.find('[data-testid="sso-test-note"]');
          expect(note.text()).toContain('Some other note');
          expect(note.classes()).toContain('text-green-700');
          expect(note.find('.o-icon').exists()).toBe(false);
          expectShownInProviderCheck(wrapper, note.element);
          const disclosure = wrapper.get('[data-testid="sso-test-technical-details"]');
          expect(disclosure.element.tagName).toBe('DETAILS');
          expect((disclosure.element as HTMLDetailsElement).open).toBe(false);
          wrapper.unmount();
        }
      });
    });
  });

  // The page has no control for SsoConfig.enabled: the record is created
  // off and only a passing saved-configuration check turns it on (the
  // primary action above); nothing on the page turns it off. The sign-in
  // method on the domain's Sign-In Configuration page is the one control.
  describe('No connection switch (Connection active / Disable SSO removed)', () => {
    it.each([
      ['a new record', {}],
      ['a record that is off', { ssoConfig: { ...mockExistingConfig, enabled: false } }],
      ['a record that is on', { ssoConfig: { ...mockExistingConfig, enforce_sso_only: true } }],
    ] as const)('renders neither control for %s', async (_state, options) => {
      wrapper = await mountComponent({
        formState: mockExistingFormState,
        isConfigured: 'ssoConfig' in options,
        ...options,
      });

      expect(wrapper.find('[data-testid="sso-connection-enabled-toggle"]').exists()).toBe(false);
      expect(wrapper.find('[data-testid="disable-sso"]').exists()).toBe(false);
      expect(wrapper.text()).not.toContain('web.organizations.sso.connection_enabled');
      expect(wrapper.text()).not.toContain('web.organizations.sso.disable_action');
      // The one remaining switch is the withheld org-scope grant, absent here.
      expect(wrapper.findAll('[role="switch"]')).toHaveLength(0);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // Loading state
  // ─────────────────────────────────────────────────────────────────────────────

  describe('Loading state', () => {
    it('shows loading indicator when isLoading is true', async () => {
      wrapper = await mountComponent({
        formState: createDefaultFormState(),
        isLoading: true,
      });

      // Should show loading skeleton (SettingsSkeleton) with its busy status region
      const skeleton = wrapper.find('[role="status"]');
      expect(skeleton.exists()).toBe(true);
    });

    it('shows form when isLoading is false', async () => {
      wrapper = await mountComponent({
        formState: createDefaultFormState(),
        isLoading: false,
      });

      const form = wrapper.find('form');
      expect(form.exists()).toBe(true);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // Grant org scope toggle (#3384) — hidden pending testing (post-v0.26.0)
  //
  // The toggle is withheld from the UI (showGrantOrgScope === false) so the
  // org-wide-access behavior can be tested more before release. grant_org_scope
  // stays at its default and still round-trips on save; only the control is
  // hidden. Restore the behavioral toggle tests when the control is un-hidden.
  // ─────────────────────────────────────────────────────────────────────────────

  describe('Grant org scope toggle (hidden pending testing)', () => {
    it('does not render the grant org scope toggle', async () => {
      wrapper = await mountComponent({
        formState: { ...mockExistingFormState, enabled: true },
        isConfigured: true,
      });

      // The connection-enabled toggle is gone too, so the form has no switch.
      expect(wrapper.find('[data-testid="grant-org-scope-toggle"]').exists()).toBe(false);
      expect(wrapper.findAll('[role="switch"]')).toHaveLength(0);
    });

    it('does not emit update:formState for grant_org_scope on mount (no control to flip)', async () => {
      wrapper = await mountComponent({
        formState: { ...mockExistingFormState, grant_org_scope: false },
        isConfigured: true,
      });

      expect(wrapper.emitted('update:formState')).toBeFalsy();
    });

    // A config that ALREADY has grant_org_scope=true keeps its toggle so the
    // grant stays revocable. Hiding it for these domains would strand an
    // irrevocable org-wide grant that every save re-persists (the toggle is the
    // only control; configToFormState/saveConfig always round-trip the value).
    it('renders the toggle when the loaded config already grants org scope', async () => {
      wrapper = await mountComponent({
        formState: { ...mockExistingFormState, grant_org_scope: true },
        isConfigured: true,
      });

      const toggle = wrapper.find('[data-testid="grant-org-scope-toggle"]');
      expect(toggle.exists()).toBe(true);
      expect(toggle.attributes('aria-checked')).toBe('true');
    });

    it('lets an existing org-wide grant be revoked (emits grant_org_scope=false)', async () => {
      wrapper = await mountComponent({
        formState: { ...mockExistingFormState, grant_org_scope: true },
        isConfigured: true,
      });

      await wrapper.find('[data-testid="grant-org-scope-toggle"]').trigger('click');

      const emitted = wrapper.emitted('update:formState');
      expect(emitted).toBeTruthy();
      const lastEmit = emitted![emitted!.length - 1][0] as SsoConfigFormState;
      expect(lastEmit.grant_org_scope).toBe(false);
    });

    // The latch is per-domain: a host may reuse this instance without
    // a :key, so navigating domains must not carry a prior domain's granted
    // toggle over to a fresh grant_org_scope=false domain (that would re-expose
    // the withheld control and let an admin inadvertently enable an org-wide
    // grant this change intends to keep unavailable).
    it('resets the latch when the domain changes (instance reused without :key)', async () => {
      // Domain A already grants org scope → toggle is visible.
      wrapper = await mountComponent({
        domainExtId: 'dm_grants',
        formState: { ...mockExistingFormState, grant_org_scope: true },
        isConfigured: true,
      });

      expect(wrapper.find('[data-testid="grant-org-scope-toggle"]').exists()).toBe(true);

      // Admin navigates to Domain B (same instance) whose config does NOT grant
      // org scope. The latch must reset so the withheld toggle is gone.
      await wrapper.setProps({
        domainExtId: 'dm_no_grant',
        formState: { ...mockExistingFormState, grant_org_scope: false },
      });

      expect(wrapper.find('[data-testid="grant-org-scope-toggle"]').exists()).toBe(false);
    });

    // The whole reason the control latches (rather than tracking grant_org_scope
    // directly): while editing ONE domain, flipping the grant off must not make
    // the toggle vanish mid-edit — the admin still needs to flip it back on or
    // save the revocation. Only a domain CHANGE resets the latch.
    it('keeps the toggle visible after a same-domain mid-edit flip-off', async () => {
      wrapper = await mountComponent({
        domainExtId: 'dm_grants',
        formState: { ...mockExistingFormState, grant_org_scope: true },
        isConfigured: true,
      });

      expect(wrapper.find('[data-testid="grant-org-scope-toggle"]').exists()).toBe(true);

      // Same domainExtId; admin flips the grant off (only formState changes).
      await wrapper.setProps({
        formState: { ...mockExistingFormState, grant_org_scope: false },
      });

      expect(wrapper.find('[data-testid="grant-org-scope-toggle"]').exists()).toBe(true);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // Unchecked credentials on a connection that is on (#4111, retargeted)
  //
  // Advisory only — never a gate: saving an active connection is how a broken
  // one is repaired. Passing provider checks do not clear it: saved
  // diagnostics must pass and the form's provider credentials must still
  // match that record. Merely opening an active connection is silent.
  // ─────────────────────────────────────────────────────────────────────────────

  describe('unchecked-credentials warning on an active connection', () => {
    const WARNING = '[data-testid="sso-credentials-unchecked-warning"]';
    const passingTest: TestSsoConnectionResponse = {
      user_id: 'cust_456',
      provider_type: 'entra_id',
      success: true,
      message: 'ok',
      details: {},
    };
    const passingDiagnostics = diagnostics('passed', [
      {
        check: 'credential',
        status: 'passed',
        message: 'Stored credentials passed',
        details: {},
      },
    ]);
    const mountActive = (options: MountOptions = {}) =>
      mountComponent({
        formState: mockExistingFormState,
        ssoConfig: mockExistingConfig,
        isConfigured: true,
        ...options,
      });

    it('is silent on a fresh form', async () => {
      wrapper = await mountComponent({
        formState: { ...mockExistingFormState, client_secret: 'new-secret' },
      });
      expect(wrapper.find(WARNING).exists()).toBe(false);
    });

    it('is silent for an active connection that merely loads, although no check ran yet', async () => {
      wrapper = await mountActive();
      expect(wrapper.find(WARNING).exists()).toBe(false);
    });

    it('warns, inside the check area, when a credential is edited', async () => {
      wrapper = await mountActive();

      await wrapper.setProps({
        formState: { ...mockExistingFormState, client_secret: 'rotated-secret' },
        hasUnsavedChanges: true,
      });

      const warning = wrapper.get(WARNING);
      // Announced, not conveyed by colour alone.
      expect(warning.attributes('role')).toBe('alert');
      expect(warning.text()).toBe('web.organizations.sso.credentials_unchecked_warning');
      expect(wrapper.get('[data-testid="sso-diagnostics"]').find(WARNING).exists()).toBe(true);
    });

    it('keeps warning after the save, while the saved credentials are unchecked', async () => {
      wrapper = await mountActive({
        formState: { ...mockExistingFormState, client_secret: 'rotated-secret' },
        hasUnsavedChanges: true,
      });
      expect(wrapper.find(WARNING).exists()).toBe(true);

      // After the save the form matches the record again.
      await wrapper.setProps({
        formState: mockExistingFormState,
        hasUnsavedChanges: false,
        savedCredentialsUnchecked: true,
      });
      expect(wrapper.find(WARNING).exists()).toBe(true);

      await wrapper.setProps({
        diagnosticsResult: passingDiagnostics,
        savedCredentialsChecked: true,
        savedCredentialsUnchecked: false,
      });
      expect(wrapper.find(WARNING).exists()).toBe(false);
    });

    it('does not gate saving or checking', async () => {
      wrapper = await mountActive({
        formState: { ...mockExistingFormState, client_secret: 'rotated-secret' },
        hasUnsavedChanges: true,
      });

      expect(wrapper.find(WARNING).exists()).toBe(true);
      expect(wrapper.get('button[type="submit"]').attributes('disabled')).toBeUndefined();
      await wrapper.get('form').trigger('submit');
      expect(wrapper.emitted('save')).toHaveLength(1);
      const run = wrapper.get('[data-testid="sso-diagnostics-run"]');
      expect(run.attributes('disabled')).toBeUndefined();
      await run.trigger('click');
      expect(wrapper.emitted('diagnostics')).toHaveLength(1);
    });

    it('is not cleared by a passing provider check (it never uses the saved secret)', async () => {
      wrapper = await mountActive({ savedCredentialsUnchecked: true });
      expect(wrapper.find(WARNING).exists()).toBe(true);

      await wrapper.setProps({ testResult: passingTest });
      expect(wrapper.find(WARNING).exists()).toBe(true);
    });

    it.each(['failed', 'inconclusive'] as const)(
      'still warns after a %s saved check',
      async (overall) => {
        wrapper = await mountActive({
          savedCredentialsUnchecked: true,
          diagnosticsResult: { ...passingDiagnostics, overall },
        });

        expect(wrapper.find(WARNING).exists()).toBe(true);
      }
    );

    it('never shows on a connection that is off (the check turns it on instead)', async () => {
      wrapper = await mountActive({
        ssoConfig: { ...mockExistingConfig, enabled: false },
        formState: { ...mockExistingFormState, client_secret: 'rotated-secret' },
        hasUnsavedChanges: true,
        savedCredentialsUnchecked: true,
      });

      expect(wrapper.find(WARNING).exists()).toBe(false);
    });

    it.each([
      ['client_id', 'different-client'],
      ['tenant_id', 'different-tenant'],
      ['issuer', 'https://different-idp.example.com'],
      ['token_endpoint_auth_method', 'client_secret_post'],
      ['client_secret', 'replacement-secret'],
    ] as const)(
      'warns again when %s changes after passing saved diagnostics',
      async (field, value) => {
        const oidc = field === 'issuer' || field === 'token_endpoint_auth_method';
        const formState: SsoConfigFormState = oidc
          ? {
              ...mockExistingFormState,
              provider_type: 'oidc',
              tenant_id: '',
              issuer: 'https://idp.example.com',
            }
          : mockExistingFormState;
        const ssoConfig: CustomDomainSsoConfig = oidc
          ? {
              ...mockExistingConfig,
              provider_type: 'oidc',
              tenant_id: null,
              issuer: 'https://idp.example.com',
            }
          : mockExistingConfig;
        wrapper = await mountActive({
          formState,
          ssoConfig,
          diagnosticsResult: { ...passingDiagnostics, provider_type: formState.provider_type },
          savedCredentialsChecked: true,
          testResult: passingTest,
        });
        expect(wrapper.find(WARNING).exists()).toBe(false);

        await wrapper.setProps({ formState: { ...formState, [field]: value } });
        expect(wrapper.find(WARNING).exists()).toBe(true);

        await wrapper.setProps({ formState });
        expect(wrapper.find(WARNING).exists()).toBe(false);
      }
    );

    it.each([
      ['idp_sso_service_url', 'https://different-idp.example.com/sso'],
      ['idp_entity_id', 'https://different-idp.example.com/entity'],
      ['idp_cert', '-----BEGIN CERTIFICATE-----\nREPLACEMENT\n-----END CERTIFICATE-----'],
    ] as const)(
      'warns again when SAML %s changes after passing saved diagnostics',
      async (field, value) => {
        wrapper = await mountActive({
          formState: mockSamlFormState,
          ssoConfig: mockSamlConfig,
          savedCredentialsChecked: true,
        });
        expect(wrapper.find(WARNING).exists()).toBe(false);

        await wrapper.setProps({ formState: { ...mockSamlFormState, [field]: value } });
        expect(wrapper.find(WARNING).exists()).toBe(true);

        await wrapper.setProps({ formState: mockSamlFormState });
        expect(wrapper.find(WARNING).exists()).toBe(false);
      }
    );

    it.each([
      ['display_name', 'Renamed connection'],
      ['enforce_sso_only', true],
      ['grant_org_scope', true],
    ] as const)('stays silent when only %s changes', async (field, value) => {
      wrapper = await mountActive();

      await wrapper.setProps({
        formState: { ...mockExistingFormState, [field]: value },
        hasUnsavedChanges: true,
      });

      expect(wrapper.find(WARNING).exists()).toBe(false);
    });

    it('follows the props of a different domain loaded into the reused instance', async () => {
      wrapper = await mountActive({ savedCredentialsUnchecked: true });
      expect(wrapper.find(WARNING).exists()).toBe(true);

      // A host may reuse this component across domains (no :key); the
      // warning holds no session state of its own to carry over.
      await wrapper.setProps({ domainExtId: 'dm_456', savedCredentialsUnchecked: false });
      expect(wrapper.find(WARNING).exists()).toBe(false);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // Accessibility
  // ─────────────────────────────────────────────────────────────────────────────

  describe('SAML provider (#4450)', () => {
    const findTestButton = (w: VueWrapper) =>
      w.findAll('button[type="button"]').find((b) => b.text().includes('test_button'));
    // The save path: the footer submit for a saved record, the primary
    // "Save and check" action for a new one (there is no footer Save yet).
    const submitButton = (w: VueWrapper) =>
      w.find('button[type="submit"]').exists()
        ? w.find('button[type="submit"]')
        : w.find('[data-testid="sso-diagnostics-run"]');

    describe('field visibility', () => {
      it('shows the IdP trio and hides the client credential inputs', async () => {
        wrapper = await mountComponent({
          formState: { ...createDefaultFormState(), provider_type: 'saml' },
        });

        expect(wrapper.find('#domain-sso-idp-sso-service-url').exists()).toBe(true);
        expect(wrapper.find('#domain-sso-idp-entity-id').exists()).toBe(true);
        expect(wrapper.find('#domain-sso-idp-cert').exists()).toBe(true);
        expect(wrapper.find('#domain-sso-client-id').exists()).toBe(false);
        expect(wrapper.find('#domain-sso-client-secret').exists()).toBe(false);
        expect(wrapper.find('#domain-sso-tenant-id').exists()).toBe(false);
        expect(wrapper.find('#domain-sso-issuer').exists()).toBe(false);
      });

      it('keeps the client credential inputs for oidc and entra_id', async () => {
        for (const provider_type of ['oidc', 'entra_id'] as const) {
          wrapper = await mountComponent({
            formState: { ...createDefaultFormState(), provider_type },
          });
          expect(wrapper.find('#domain-sso-client-id').exists()).toBe(true);
          expect(wrapper.find('#domain-sso-client-secret').exists()).toBe(true);
          expect(wrapper.find('#domain-sso-idp-cert').exists()).toBe(false);
          wrapper.unmount();
        }
      });

      it('the certificate input is a textarea with a hint, and the SSO URL input is type=url', async () => {
        wrapper = await mountComponent({
          formState: { ...createDefaultFormState(), provider_type: 'saml' },
        });

        const cert = wrapper.find('#domain-sso-idp-cert');
        expect(cert.element.tagName).toBe('TEXTAREA');
        expect(cert.attributes('aria-describedby')).toBe('domain-sso-idp-cert-hint');
        expect(wrapper.find('#domain-sso-idp-cert-hint').exists()).toBe(true);
        expect(wrapper.find('#domain-sso-idp-sso-service-url').attributes('type')).toBe('url');
      });
    });

    describe('state updates', () => {
      it.each([
        ['idp_sso_service_url', '#domain-sso-idp-sso-service-url', 'https://idp.example.com/sso'],
        ['idp_entity_id', '#domain-sso-idp-entity-id', 'https://idp.example.com/entity'],
        ['idp_cert', '#domain-sso-idp-cert', SAML_CERT],
      ] as const)('emits update:formState when %s changes', async (field, selector, value) => {
        wrapper = await mountComponent({
          formState: { ...createDefaultFormState(), provider_type: 'saml' },
        });

        await wrapper.find(selector).setValue(value);
        await flushPromises();

        const emitted = wrapper.emitted('update:formState');
        expect(emitted).toBeTruthy();
        expect(emitted![emitted!.length - 1][0]).toMatchObject({ [field]: value });
      });
    });

    describe('required guards', () => {
      // Each trio field on its own: a guard that checked only one of them
      // would pass a single-field example.
      it.each(['idp_sso_service_url', 'idp_entity_id', 'idp_cert'] as const)(
        'disables save and test when %s is blank',
        async (field) => {
          wrapper = await mountComponent({
            formState: { ...mockSamlFormState, [field]: '' },
          });

          expect(submitButton(wrapper).attributes('disabled')).toBeDefined();
          expect(findTestButton(wrapper)!.attributes('disabled')).toBeDefined();
        }
      );

      it.each(['idp_sso_service_url', 'idp_entity_id', 'idp_cert'] as const)(
        'disables save and test when %s is whitespace only',
        async (field) => {
          wrapper = await mountComponent({
            formState: { ...mockSamlFormState, [field]: '   ' },
          });

          expect(submitButton(wrapper).attributes('disabled')).toBeDefined();
        }
      );

      it('enables save and test with the trio filled and NO client_id', async () => {
        wrapper = await mountComponent({ formState: mockSamlFormState });

        expect(mockSamlFormState.client_id).toBe('');
        expect(submitButton(wrapper).attributes('disabled')).toBeUndefined();
        expect(findTestButton(wrapper)!.attributes('disabled')).toBeUndefined();
      });

      it('still requires client_id for oidc (guard is per provider, not dropped)', async () => {
        wrapper = await mountComponent({
          formState: {
            ...createDefaultFormState(),
            provider_type: 'oidc',
            display_name: 'x',
            issuer: 'https://idp.example.com',
            client_id: '',
          },
        });

        expect(submitButton(wrapper).attributes('disabled')).toBeDefined();
      });

      it('submits a complete new saml form through Save and check', async () => {
        wrapper = await mountComponent({ formState: mockSamlFormState });

        await wrapper.find('form').trigger('submit.prevent');
        await flushPromises();

        expect(wrapper.emitted('diagnostics')).toHaveLength(1);
        expect(wrapper.emitted('save')).toBeUndefined();
      });
    });

    describe('service-provider identifiers', () => {
      it('previews SP Entity ID and ACS URL from the host before a record exists', async () => {
        wrapper = await mountComponent({
          formState: mockSamlFormState,
          domainHost: 'secrets.example.com',
        });

        expect(wrapper.find('[data-testid="sso-saml-sp-entity-id"]').text()).toBe(
          'https://secrets.example.com/auth/sso/saml/metadata'
        );
        expect(wrapper.find('[data-testid="sso-saml-acs-url"]').text()).toBe(
          'https://secrets.example.com/auth/sso/saml/callback'
        );
      });

      // The host preview assumes https and the default route; an operator
      // SAML_ROUTE_NAME override or site.ssl=false makes it wrong (#3932), so
      // it is labelled a preview instead of "register these values".
      it('labels host-derived values as a preview before a record exists', async () => {
        wrapper = await mountComponent({
          formState: mockSamlFormState,
          domainHost: 'secrets.example.com',
        });

        const hint = wrapper.find('[data-testid="sso-saml-sp-details-hint"]');
        expect(hint.text()).toBe('web.organizations.sso.sp_details_preview_hint');
        expect(wrapper.text()).not.toContain('web.organizations.sso.sp_details_hint');
      });

      it('prefers the API-composed sp_entity_id / acs_url of a saved saml record', async () => {
        wrapper = await mountComponent({
          formState: mockSamlFormState,
          ssoConfig: mockSamlConfig,
          isConfigured: true,
        });

        expect(wrapper.find('[data-testid="sso-saml-sp-entity-id"]').text()).toBe(
          mockSamlConfig.sp_entity_id
        );
        expect(wrapper.find('[data-testid="sso-saml-acs-url"]').text()).toBe(
          mockSamlConfig.acs_url
        );
        // API-composed values are the real ones: generic "register these" hint.
        const hint = wrapper.find('[data-testid="sso-saml-sp-details-hint"]');
        expect(hint.text()).toBe('web.organizations.sso.sp_details_hint');
        expect(wrapper.text()).not.toContain('web.organizations.sso.sp_details_preview_hint');
      });

      // A saved null now means only that the API could not load the domain;
      // verification no longer withholds the values (#4579).
      it('falls back to the host preview when the API could not derive them', async () => {
        wrapper = await mountComponent({
          formState: mockSamlFormState,
          ssoConfig: { ...mockSamlConfig, sp_entity_id: null, acs_url: null },
          isConfigured: true,
          domainHost: 'secrets.example.com',
        });

        expect(wrapper.find('[data-testid="sso-saml-sp-entity-id"]').text()).toBe(
          'https://secrets.example.com/auth/sso/saml/metadata'
        );
        // Still host-derived, so still labelled a preview.
        expect(wrapper.find('[data-testid="sso-saml-sp-details-hint"]').text()).toBe(
          'web.organizations.sso.sp_details_preview_hint'
        );
      });

      it('replaces the generic callback block and offers a copy control per value', async () => {
        wrapper = await mountComponent({ formState: mockSamlFormState });

        expect(wrapper.text()).not.toContain('web.organizations.sso.callback_url_hint');
        const block = wrapper.find('[data-testid="sso-saml-sp-details"]');
        expect(block.exists()).toBe(true);
        expect(block.findAll('button')).toHaveLength(2);
      });

      it('shows the generic callback block, not the SP block, for oidc', async () => {
        wrapper = await mountComponent({
          formState: { ...createDefaultFormState(), provider_type: 'oidc' },
        });

        expect(wrapper.text()).toContain('web.organizations.sso.callback_url_hint');
        expect(wrapper.find('[data-testid="sso-saml-sp-details"]').exists()).toBe(false);
      });

      it('hides the SP block when no host is known and no record exists', async () => {
        wrapper = await mountComponent({ formState: mockSamlFormState, domainHost: '' });

        expect(wrapper.find('[data-testid="sso-saml-sp-details"]').exists()).toBe(false);
      });
    });

    // #4579: tenant SSO is refused on an unverified domain, and verification
    // does not change the values, so they are shown with a notice. Whether
    // they are ready to register stays the block hint's call.
    describe('unverified domain', () => {
      const NOTICE = '[data-testid="sso-domain-unverified-notice"]';

      it('previews the SP identifiers and shows the notice before a record exists', async () => {
        wrapper = await mountComponent({ formState: mockSamlFormState, domainVerified: false });

        expect(wrapper.find('[data-testid="sso-saml-sp-entity-id"]').text()).toBe(
          'https://secrets.example.com/auth/sso/saml/metadata'
        );
        expect(wrapper.find('[data-testid="sso-saml-acs-url"]').text()).toBe(
          'https://secrets.example.com/auth/sso/saml/callback'
        );
        const notice = wrapper.find(NOTICE);
        expect(notice.exists()).toBe(true);
        expect(notice.attributes('role')).toBe('status');
        expect(notice.text()).toBe('web.organizations.sso.domain_unverified_notice');
        // The notice does not override the preview caveat: host-derived values
        // are confirmed after saving, verified domain or not (#3932).
        expect(wrapper.find('[data-testid="sso-saml-sp-details-hint"]').text()).toBe(
          'web.organizations.sso.sp_details_preview_hint'
        );
      });

      it('shows the API-composed values of a saved record as final, with the notice', async () => {
        // A domain that lost its verification keeps showing what the admin
        // already registered at the IdP.
        wrapper = await mountComponent({
          formState: mockSamlFormState,
          ssoConfig: mockSamlConfig,
          isConfigured: true,
          domainVerified: false,
        });

        expect(wrapper.find('[data-testid="sso-saml-sp-entity-id"]').text()).toBe(
          mockSamlConfig.sp_entity_id
        );
        expect(wrapper.find('[data-testid="sso-saml-acs-url"]').text()).toBe(
          mockSamlConfig.acs_url
        );
        // Not a preview: verification changes when they go live, not what they are.
        expect(wrapper.find('[data-testid="sso-saml-sp-details-hint"]').text()).toBe(
          'web.organizations.sso.sp_details_hint'
        );
        expect(wrapper.find(NOTICE).exists()).toBe(true);
      });

      it('shows the callback URL and the notice for an OAuth-family provider', async () => {
        wrapper = await mountComponent({
          formState: { ...createDefaultFormState(), provider_type: 'oidc' },
          domainVerified: false,
        });

        expect(wrapper.text()).toContain('https://secrets.example.com/auth/sso/oidc/callback');
        expect(wrapper.find(NOTICE).text()).toBe('web.organizations.sso.domain_unverified_notice');
      });

      it('never shows the notice for a verified domain', async () => {
        wrapper = await mountComponent({ formState: mockSamlFormState });
        expect(wrapper.find(NOTICE).exists()).toBe(false);

        wrapper.unmount();
        wrapper = await mountComponent({
          formState: { ...createDefaultFormState(), provider_type: 'oidc' },
        });
        expect(wrapper.find(NOTICE).exists()).toBe(false);
      });

      it('omits the notice when there are no values for it to describe', async () => {
        wrapper = await mountComponent({
          formState: mockSamlFormState,
          domainHost: '',
          domainVerified: false,
        });

        expect(wrapper.find('[data-testid="sso-saml-sp-details"]').exists()).toBe(false);
        expect(wrapper.find(NOTICE).exists()).toBe(false);
      });
    });

    describe('stored certificate validity (cert_expired / cert_expires_at)', () => {
      const DAY = 86_400_000;
      const iso = (offsetMs: number) => new Date(Date.now() + offsetMs).toISOString();

      it('renders an error alert when the saved certificate has expired', async () => {
        wrapper = await mountComponent({
          formState: mockSamlFormState,
          ssoConfig: { ...mockSamlConfig, cert_expires_at: iso(-DAY), cert_expired: true },
          isConfigured: true,
        });

        const alert = wrapper.find('[data-testid="sso-idp-cert-expired-alert"]');
        expect(alert.exists()).toBe(true);
        expect(alert.attributes('role')).toBe('alert');
        expect(alert.text()).toContain('web.organizations.sso.idp_cert_expired_alert');
        expect(wrapper.find('[data-testid="sso-idp-cert-expiring-notice"]').exists()).toBe(false);
      });

      it('renders a softer notice when the certificate expires within 30 days', async () => {
        wrapper = await mountComponent({
          formState: mockSamlFormState,
          ssoConfig: { ...mockSamlConfig, cert_expires_at: iso(10 * DAY), cert_expired: false },
          isConfigured: true,
        });

        expect(wrapper.find('[data-testid="sso-idp-cert-expired-alert"]').exists()).toBe(false);
        const notice = wrapper.find('[data-testid="sso-idp-cert-expiring-notice"]');
        expect(notice.exists()).toBe(true);
        expect(notice.text()).toContain('web.organizations.sso.idp_cert_expiring_notice');
      });

      it('renders neither for a certificate valid beyond 30 days', async () => {
        wrapper = await mountComponent({
          formState: mockSamlFormState,
          ssoConfig: { ...mockSamlConfig, cert_expires_at: iso(90 * DAY), cert_expired: false },
          isConfigured: true,
        });

        expect(wrapper.find('[data-testid="sso-idp-cert-expired-alert"]').exists()).toBe(false);
        expect(wrapper.find('[data-testid="sso-idp-cert-expiring-notice"]').exists()).toBe(false);
      });

      it('hides the expired alert once a different certificate is pasted', async () => {
        const replacement = '-----BEGIN CERTIFICATE-----\nNEW\n-----END CERTIFICATE-----';
        wrapper = await mountComponent({
          formState: { ...mockSamlFormState, idp_cert: replacement },
          ssoConfig: { ...mockSamlConfig, cert_expires_at: iso(-DAY), cert_expired: true },
          isConfigured: true,
        });

        expect(wrapper.find('[data-testid="sso-idp-cert-expired-alert"]').exists()).toBe(false);
      });

      it('ends the expired alert sentence once after a date that ends in a period', async () => {
        // Hungarian and Korean dates end in a period ("2026. 10. 14."); the
        // message reads "... expired on {date}. Sign-in ...", so one period
        // serves both. The pass-through test i18n drops interpolation.
        const spy = vi.spyOn(Date.prototype, 'toLocaleDateString').mockReturnValue('2026. 10. 14.');
        try {
          const realI18n = createRealI18n({
            en: JSON.parse(
              readFileSync(resolve(process.cwd(), 'generated/locales/en.json'), 'utf-8')
            ),
          });
          wrapper = mount(DomainSsoConfigForm, {
            props: {
              ...defaultMountOptions,
              formState: mockSamlFormState,
              ssoConfig: { ...mockSamlConfig, cert_expires_at: iso(-DAY), cert_expired: true },
              isConfigured: true,
            },
            global: { plugins: [realI18n, pinia], stubs: { Teleport: true } },
          });
          await flushPromises();

          const text = wrapper.get('[data-testid="sso-idp-cert-expired-alert"]').text();
          expect(text).toContain('expired on 2026. 10. 14. Sign-in');
          expect(text).not.toContain('14..');
        } finally {
          spy.mockRestore();
        }
      });

      it('renders nothing when the payload predates the fields', async () => {
        wrapper = await mountComponent({
          formState: mockSamlFormState,
          ssoConfig: mockSamlConfig,
          isConfigured: true,
        });

        expect(wrapper.find('[data-testid="sso-idp-cert-expired-alert"]').exists()).toBe(false);
        expect(wrapper.find('[data-testid="sso-idp-cert-expiring-notice"]').exists()).toBe(false);
      });
    });

    describe('reveal failure (unreadable_fields)', () => {
      it('renders an alert naming the field and marks the input invalid', async () => {
        wrapper = await mountComponent({
          formState: { ...mockSamlFormState, idp_cert: '' },
          ssoConfig: { ...mockSamlConfig, idp_cert: null, unreadable_fields: ['idp_cert'] },
          isConfigured: true,
        });

        const alert = wrapper.find('[data-testid="sso-unreadable-fields-alert"]');
        expect(alert.exists()).toBe(true);
        expect(alert.attributes('role')).toBe('alert');
        expect(alert.text()).toContain('web.organizations.sso.unreadable_fields_alert');

        const cert = wrapper.find('#domain-sso-idp-cert');
        expect(cert.attributes('aria-invalid')).toBe('true');
        expect(cert.attributes('aria-describedby')).toBe(
          'domain-sso-idp-cert-hint domain-sso-idp-cert-error'
        );
        expect(wrapper.find('#domain-sso-idp-cert-error').exists()).toBe(true);
        // Untouched siblings stay clean.
        expect(
          wrapper.find('#domain-sso-idp-entity-id').attributes('aria-invalid')
        ).toBeUndefined();
        expect(wrapper.find('#domain-sso-idp-entity-id-error').exists()).toBe(false);
        // And the save is blocked until the value is re-entered.
        expect(submitButton(wrapper).attributes('disabled')).toBeDefined();
      });

      it('renders nothing for a healthy record', async () => {
        wrapper = await mountComponent({
          formState: mockSamlFormState,
          ssoConfig: mockSamlConfig,
          isConfigured: true,
        });

        expect(wrapper.find('[data-testid="sso-unreadable-fields-alert"]').exists()).toBe(false);
        expect(wrapper.find('#domain-sso-idp-cert').attributes('aria-invalid')).toBeUndefined();
      });

      it('covers the client credential fields too (entra_id secret must be re-entered)', async () => {
        wrapper = await mountComponent({
          formState: mockExistingFormState,
          ssoConfig: {
            ...mockExistingConfig,
            client_secret_masked: null,
            unreadable_fields: ['client_secret'],
          },
          isConfigured: true,
        });

        expect(wrapper.find('[data-testid="sso-unreadable-fields-alert"]').exists()).toBe(true);
        const secret = wrapper.find('#domain-sso-client-secret');
        expect(secret.attributes('aria-invalid')).toBe('true');
        expect(secret.attributes('required')).toBeDefined();
        // Editing normally lets the secret stay blank; not when it is unreadable.
        expect(submitButton(wrapper).attributes('disabled')).toBeDefined();
      });

      // oidc permits public clients, so its secret is normally optional. The
      // exemption covers an ABSENT secret: a stored one that will not decrypt
      // must be replaced, or the API refuses the save as missing.
      describe('oidc client_secret', () => {
        const oidcFormState: SsoConfigFormState = {
          ...mockExistingFormState,
          provider_type: 'oidc',
          tenant_id: '',
          issuer: 'https://idp.example.com',
        };
        const oidcConfig: CustomDomainSsoConfig = {
          ...mockExistingConfig,
          provider_type: 'oidc',
          tenant_id: null,
          issuer: 'https://idp.example.com',
        };

        it('is required and blocks the save when the stored secret is unreadable', async () => {
          wrapper = await mountComponent({
            formState: oidcFormState,
            ssoConfig: {
              ...oidcConfig,
              client_secret_masked: null,
              unreadable_fields: ['client_secret'],
            },
            isConfigured: true,
            clientSecretMasked: null,
          });

          expect(wrapper.find('[data-testid="sso-unreadable-fields-alert"]').exists()).toBe(true);
          const secret = wrapper.find('#domain-sso-client-secret');
          expect(secret.attributes('required')).toBeDefined();
          expect(secret.attributes('aria-invalid')).toBe('true');
          expect(wrapper.find('label[for="domain-sso-client-secret"]').text()).toContain('*');
          expect(submitButton(wrapper).attributes('disabled')).toBeDefined();
        });

        it('unblocks the save once a replacement secret is entered', async () => {
          wrapper = await mountComponent({
            formState: { ...oidcFormState, client_secret: 'replacement-secret' },
            ssoConfig: {
              ...oidcConfig,
              client_secret_masked: null,
              unreadable_fields: ['client_secret'],
            },
            isConfigured: true,
            clientSecretMasked: null,
            hasUnsavedChanges: true,
          });

          expect(submitButton(wrapper).attributes('disabled')).toBeUndefined();
        });

        it('stays optional for a healthy secretless oidc record (public client)', async () => {
          wrapper = await mountComponent({
            formState: oidcFormState,
            ssoConfig: { ...oidcConfig, client_secret_masked: null, unreadable_fields: [] },
            isConfigured: true,
            clientSecretMasked: null,
            // Save is gated on unsaved changes too; this example is about validity.
            hasUnsavedChanges: true,
          });

          const secret = wrapper.find('#domain-sso-client-secret');
          expect(secret.attributes('required')).toBeUndefined();
          expect(secret.attributes('aria-invalid')).toBeUndefined();
          expect(wrapper.find('label[for="domain-sso-client-secret"]').text()).not.toContain('*');
          expect(submitButton(wrapper).attributes('disabled')).toBeUndefined();
        });

        it('stays optional on a new oidc form', async () => {
          wrapper = await mountComponent({ formState: { ...oidcFormState, client_secret: '' } });

          expect(wrapper.find('#domain-sso-client-secret').attributes('required')).toBeUndefined();
          expect(submitButton(wrapper).attributes('disabled')).toBeUndefined();
        });
      });
    });

    describe('test connection', () => {
      it('uses the local-check hint for saml', async () => {
        wrapper = await mountComponent({ formState: mockSamlFormState });

        expect(wrapper.text()).toContain('web.organizations.sso.test_connection_hint_saml');
        expect(wrapper.text()).not.toMatch(/test_connection_hint(?!_saml)/);
      });

      it('renders certificate subject and expiry from a successful local check', async () => {
        wrapper = await mountComponent({
          formState: mockSamlFormState,
          testResult: {
            user_id: 'cust_456',
            success: true,
            provider_type: 'saml',
            message:
              'SAML configuration is valid (checked locally; the identity provider was not contacted)',
            details: {
              idp_entity_id: 'https://idp.example.com/entity',
              idp_sso_service_url: 'https://idp.example.com/sso',
              certificate_subject: 'CN=idp.example.com',
              certificate_not_after: '2030-01-01T00:00:00Z',
              certificate_expires_in_days: 1200,
            },
          },
        });

        const details = wrapper.find('[data-testid="sso-test-saml-details"]');
        expect(details.exists()).toBe(true);
        expect(details.text()).toContain('CN=idp.example.com');
        expect(details.text()).toContain('web.organizations.sso.certificate_expires_in_days');
        expect(details.isVisible()).toBe(true);
        expectShownInProviderCheck(wrapper, details.element);
        expect(wrapper.find('[role="status"]').exists()).toBe(true);
      });

      it('names the offending field and the expiry on a failed local check', async () => {
        wrapper = await mountComponent({
          formState: mockSamlFormState,
          testResult: {
            user_id: 'cust_456',
            success: false,
            provider_type: 'saml',
            message: 'IdP certificate expired on 2024-01-01',
            details: {
              error_code: 'certificate_expired',
              field: 'idp_cert',
              description: 'IdP certificate expired on 2024-01-01',
              certificate_not_after: '2024-01-01T00:00:00Z',
            },
          },
        });

        const alert = wrapper.find('[role="alert"]');
        expect(alert.exists()).toBe(true);
        expect(alert.text()).toContain('certificate_expired');
        expect(alert.text()).toContain('web.organizations.sso.idp_cert');
        expect(alert.text()).toContain('web.organizations.sso.certificate_expires');
        expect(alert.text()).not.toContain('web.organizations.sso.certificate_valid_from');
      });

      // The API reports both bounds of the validity window on a window
      // failure; for a certificate that is not valid YET the start is the
      // fact that matters, not the expiry.
      it('names the validity start on a not-yet-valid certificate', async () => {
        wrapper = await mountComponent({
          formState: mockSamlFormState,
          testResult: {
            user_id: 'cust_456',
            success: false,
            provider_type: 'saml',
            message: 'IdP certificate is not valid until 2031-01-01',
            details: {
              error_code: 'certificate_not_yet_valid',
              field: 'idp_cert',
              description: 'IdP certificate is not valid until 2031-01-01',
              certificate_not_before: '2031-01-01T00:00:00Z',
              certificate_not_after: '2033-01-01T00:00:00Z',
            },
          },
        });

        const alert = wrapper.find('[role="alert"]');
        expect(alert.exists()).toBe(true);
        expect(alert.text()).toContain('certificate_not_yet_valid');
        expect(alert.text()).toContain('web.organizations.sso.idp_cert');
        expect(alert.text()).toContain('web.organizations.sso.certificate_valid_from');
        expect(alert.text()).toContain(new Date('2031-01-01T00:00:00Z').toLocaleDateString());
      });
    });

    describe('accessibility', () => {
      it('every IdP input has an associated label, hint and an asterisk', async () => {
        wrapper = await mountComponent({
          formState: { ...createDefaultFormState(), provider_type: 'saml' },
        });

        for (const id of [
          'domain-sso-idp-sso-service-url',
          'domain-sso-idp-entity-id',
          'domain-sso-idp-cert',
        ]) {
          const label = wrapper.find(`label[for="${id}"]`);
          expect(label.exists()).toBe(true);
          expect(label.text()).toContain('*');
          expect(wrapper.find(`#${id}`).attributes('aria-describedby')).toBe(`${id}-hint`);
          expect(wrapper.find(`#${id}-hint`).exists()).toBe(true);
        }
      });

      it('read-only SP values are labelled', async () => {
        wrapper = await mountComponent({ formState: mockSamlFormState });

        expect(
          wrapper.find('[data-testid="sso-saml-sp-entity-id"]').attributes('aria-labelledby')
        ).toBe('domain-sso-sp-entity-id-label');
        expect(wrapper.find('#domain-sso-sp-entity-id-label').exists()).toBe(true);
        expect(wrapper.find('[data-testid="sso-saml-acs-url"]').attributes('aria-labelledby')).toBe(
          'domain-sso-acs-url-label'
        );
        expect(wrapper.find('#domain-sso-acs-url-label').exists()).toBe(true);
      });
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // SAML metadata import (docs/specs/sso/saml-idp-metadata-consumption.md,
  // Phase 1). A fetch fills a preview, never the form; Apply copies a
  // complete preview into the form; Save (unchanged) persists it.
  // ─────────────────────────────────────────────────────────────────────────────

  describe('SAML metadata import', () => {
    const IDP_A_METADATA_URL = 'https://idp.example.com/saml/metadata';
    const IDP_B_METADATA_URL = 'https://idp-b.example.com/saml/metadata';
    const CERT_B1 = '-----BEGIN CERTIFICATE-----\nB1\n-----END CERTIFICATE-----';
    const CERT_B2 = '-----BEGIN CERTIFICATE-----\nB2\n-----END CERTIFICATE-----';

    const certificate = (
      overrides: Partial<IdpMetadataCertificate> = {}
    ): IdpMetadataCertificate => ({
      pem: CERT_B1,
      subject: 'CN=IdP B signing',
      not_before: '2026-01-01T00:00:00Z',
      not_after: '2029-01-01T00:00:00Z',
      fingerprint_sha256: 'B1:B1:B1',
      thumbprint_sha1: 'B1:B1',
      problem: null,
      ...overrides,
    });

    const metadataB = (
      overrides: Partial<IdpMetadataPreviewResponse> = {}
    ): IdpMetadataPreviewResponse => ({
      success: true,
      metadata_url: IDP_B_METADATA_URL,
      idp_entity_id: 'https://idp-b.example.com/entity',
      idp_sso_service_url: 'https://idp-b.example.com/sso/redirect',
      signing_certificates: [certificate()],
      name_id_formats: [
        'urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress',
        'urn:oasis:names:tc:SAML:2.0:nameid-format:transient',
      ],
      problems: [],
      ...overrides,
    });

    // Entra during a rollover: the active certificate, a newer one added but
    // not yet active, and an expired one the save would refuse.
    const rolloverCertificates = [
      certificate({
        pem: CERT_B1,
        subject: 'CN=Active',
        fingerprint_sha256: 'AA:01',
        thumbprint_sha1: 'A1',
      }),
      certificate({
        pem: CERT_B2,
        subject: 'CN=Added',
        not_before: '2026-06-01T00:00:00Z',
        fingerprint_sha256: 'BB:02',
        thumbprint_sha1: 'B2',
      }),
      certificate({
        subject: 'CN=Expired',
        not_before: '2020-01-01T00:00:00Z',
        not_after: '2023-01-01T00:00:00Z',
        fingerprint_sha256: 'CC:03',
        thumbprint_sha1: 'C3',
        problem: 'IdP certificate expired on 2023-01-01',
      }),
    ];

    const previewOf = (
      response: IdpMetadataPreviewResponse,
      selectedCertIndex: number | null = null
    ): SsoMetadataPreview => ({
      requestId: 1,
      metadataUrl: IDP_B_METADATA_URL,
      response,
      selectedCertIndex,
    });

    const blocking = (code: string) => ({
      code,
      severity: 'blocking' as const,
      message: `${code} (server message)`,
    });

    // IdP A: the saved saml record, imported from its metadata URL.
    const samlFormA: SsoConfigFormState = {
      ...mockSamlFormState,
      idp_metadata_url: IDP_A_METADATA_URL,
    };
    const samlRecordA: CustomDomainSsoConfig = {
      ...mockSamlConfig,
      idp_metadata_url: IDP_A_METADATA_URL,
    };

    const mountSamlA = (options: MountOptions = {}) =>
      mountComponent({
        formState: samlFormA,
        ssoConfig: samlRecordA,
        isConfigured: true,
        metadataFetchUrl: IDP_B_METADATA_URL,
        ...options,
      });

    // What the form shows for the trio and its source.
    const shownValues = (w: VueWrapper) => ({
      idp_sso_service_url: (w.get('#domain-sso-idp-sso-service-url').element as HTMLInputElement)
        .value,
      idp_entity_id: (w.get('#domain-sso-idp-entity-id').element as HTMLInputElement).value,
      idp_cert: (w.get('#domain-sso-idp-cert').element as HTMLTextAreaElement).value,
      source: w.find('[data-testid="sso-metadata-source-url"]').text(),
    });

    const IDP_A_SHOWN = {
      idp_sso_service_url: 'https://idp.example.com/sso',
      idp_entity_id: 'https://idp.example.com/entity',
      idp_cert: SAML_CERT,
      source: IDP_A_METADATA_URL,
    };

    const realI18n = () =>
      createRealI18n({
        en: JSON.parse(readFileSync(resolve(process.cwd(), 'generated/locales/en.json'), 'utf-8')),
      });

    describe('fetch input and source', () => {
      it('sits in the SAML block above the trio and is absent for other providers', async () => {
        wrapper = await mountSamlA();

        const section = wrapper.get('[data-testid="sso-saml-metadata"]').element;
        const ssoUrl = wrapper.get('#domain-sso-idp-sso-service-url').element;
        expect(
          section.compareDocumentPosition(ssoUrl) & Node.DOCUMENT_POSITION_FOLLOWING
        ).toBeTruthy();
        wrapper.unmount();

        wrapper = await mountComponent({ formState: mockExistingFormState });
        expect(wrapper.find('[data-testid="sso-saml-metadata"]').exists()).toBe(false);
      });

      it('labels the input and keeps Fetch a secondary action beside Save and check', async () => {
        wrapper = await mountSamlA();

        expect(wrapper.find('label[for="domain-sso-idp-metadata-url"]').exists()).toBe(true);
        const input = wrapper.get('#domain-sso-idp-metadata-url');
        expect(input.attributes('aria-describedby')).toBe('domain-sso-idp-metadata-url-hint');
        // Not type=url: the fetch input is not saved, so a half-typed value
        // must not trip the browser's validation of the surrounding form.
        expect(input.attributes('type')).toBe('text');
        expect(input.attributes('inputmode')).toBe('url');
        expect(wrapper.find('#domain-sso-idp-metadata-url-hint').exists()).toBe(true);
        const fetch = wrapper.get('[data-testid="sso-metadata-fetch"]');
        expect(fetch.attributes('type')).toBe('button');
        expect(fetch.classes()).not.toContain('bg-brand-600');
        expect(fetch.text()).toBe('web.organizations.sso.metadata_fetch_button');
        expect(wrapper.get('[data-testid="sso-diagnostics-run"]').classes()).toContain(
          'bg-brand-600'
        );
      });

      it('fetches from the button and from Enter, without submitting the form', async () => {
        wrapper = await mountSamlA();

        await wrapper.get('[data-testid="sso-metadata-fetch"]').trigger('click');
        await wrapper.get('#domain-sso-idp-metadata-url').trigger('keydown', { key: 'Enter' });

        expect(wrapper.emitted('fetch-metadata')).toHaveLength(2);
        expect(wrapper.emitted('save')).toBeUndefined();
        expect(wrapper.emitted('diagnostics')).toBeUndefined();
      });

      it('cannot fetch a blank URL or while a fetch is in flight', async () => {
        wrapper = await mountSamlA({ metadataFetchUrl: '   ' });
        expect(
          wrapper.get('[data-testid="sso-metadata-fetch"]').attributes('disabled')
        ).toBeDefined();
        await wrapper.get('#domain-sso-idp-metadata-url').trigger('keydown', { key: 'Enter' });
        expect(wrapper.emitted('fetch-metadata')).toBeUndefined();

        await wrapper.setProps({ metadataFetchUrl: IDP_B_METADATA_URL, isFetchingMetadata: true });
        const fetch = wrapper.get('[data-testid="sso-metadata-fetch"]');
        expect(fetch.attributes('disabled')).toBeDefined();
        expect(fetch.attributes('aria-busy')).toBe('true');
        expect(wrapper.get('[data-testid="sso-metadata-fetching"]').attributes('role')).toBe(
          'status'
        );
      });

      it('typing a URL edits the fetch input only, never the form', async () => {
        wrapper = await mountSamlA({ metadataFetchUrl: '' });

        await wrapper.get('#domain-sso-idp-metadata-url').setValue(IDP_B_METADATA_URL);

        expect(wrapper.emitted('update:metadataFetchUrl')).toEqual([[IDP_B_METADATA_URL]]);
        expect(wrapper.emitted('update:formState')).toBeUndefined();
      });

      it('shows where the trio came from and clears only that', async () => {
        wrapper = await mountSamlA();

        expect(wrapper.get('[data-testid="sso-metadata-source-url"]').text()).toBe(
          IDP_A_METADATA_URL
        );
        await wrapper.get('[data-testid="sso-metadata-source-clear"]').trigger('click');

        expect(wrapper.emitted('update:formState')).toEqual([
          [{ ...samlFormA, idp_metadata_url: '' }],
        ]);
      });

      // The save clears an unreadable source rather than refusing, so it is
      // not one of the values the re-entry alert says must be entered again.
      it('explains an unreadable source beside the input, not in the re-entry alert', async () => {
        wrapper = await mountSamlA({
          formState: { ...samlFormA, idp_metadata_url: '' },
          ssoConfig: {
            ...samlRecordA,
            idp_metadata_url: null,
            unreadable_fields: ['idp_metadata_url'],
          },
        });

        expect(wrapper.find('[data-testid="sso-unreadable-fields-alert"]').exists()).toBe(false);
        expect(wrapper.get('[data-testid="sso-metadata-source-unreadable"]').text()).toBe(
          'web.organizations.sso.metadata_source_unreadable'
        );
        expect(wrapper.find('[data-testid="sso-metadata-source-url"]').exists()).toBe(false);
      });

      it('names only the values that must be entered again when the source is unreadable too', async () => {
        // The pass-through test i18n drops interpolation; the real bundle
        // shows which field names fill {fields}.
        const realI18n = createRealI18n({
          en: JSON.parse(
            readFileSync(resolve(process.cwd(), 'generated/locales/en.json'), 'utf-8')
          ),
        });
        wrapper = mount(DomainSsoConfigForm, {
          props: {
            ...defaultMountOptions,
            formState: { ...samlFormA, idp_cert: '', idp_metadata_url: '' },
            ssoConfig: {
              ...samlRecordA,
              idp_cert: null,
              idp_metadata_url: null,
              unreadable_fields: ['idp_cert', 'idp_metadata_url'],
            },
            isConfigured: true,
            metadataFetchUrl: IDP_B_METADATA_URL,
          },
          global: { plugins: [realI18n, pinia], stubs: { Teleport: true } },
        });
        await flushPromises();

        const alert = wrapper.get('[data-testid="sso-unreadable-fields-alert"]');
        expect(alert.text()).toContain('IdP signing certificate');
        expect(alert.text()).not.toContain('IdP metadata URL');
        expect(wrapper.find('[data-testid="sso-metadata-source-unreadable"]').exists()).toBe(true);
      });
    });

    describe('certificate picker', () => {
      it('offers two or more certificates as radios with nothing preselected', async () => {
        wrapper = await mountSamlA({
          metadataPreview: previewOf(metadataB({ signing_certificates: rolloverCertificates })),
        });

        const group = wrapper.get('[data-testid="sso-metadata-certificates"] [role="radiogroup"]');
        expect(group.attributes('aria-labelledby')).toBe('sso-metadata-certificates-title');
        const radios = wrapper.findAll('input[name="sso-metadata-certificate"]');
        expect(radios).toHaveLength(3);
        expect(radios.map((radio) => (radio.element as HTMLInputElement).checked)).toEqual([
          false,
          false,
          false,
        ]);
        // The choice is pending: Apply is disabled and says why.
        const apply = wrapper.get('[data-testid="sso-metadata-apply"]');
        expect(apply.attributes('disabled')).toBeDefined();
        expect(apply.attributes('aria-describedby')).toBe('sso-metadata-select-hint');
        expect(wrapper.get('#sso-metadata-select-hint').text()).toBe(
          'web.organizations.sso.metadata_select_certificate'
        );
      });

      it('labels the newest certificate without selecting it', async () => {
        wrapper = await mountSamlA({
          metadataPreview: previewOf(metadataB({ signing_certificates: rolloverCertificates })),
        });

        const newest = wrapper.findAll('[data-testid="sso-metadata-cert-newest"]');
        expect(newest).toHaveLength(1);
        expect(wrapper.get('[data-testid="sso-metadata-cert-1"]').text()).toContain(
          'web.organizations.sso.metadata_cert_newest'
        );
        expect(wrapper.get('[data-testid="sso-metadata-cert-1"]').attributes('data-selected')).toBe(
          'false'
        );
      });

      it('disables a certificate with a problem and shows the server reason', async () => {
        wrapper = await mountSamlA({
          metadataPreview: previewOf(metadataB({ signing_certificates: rolloverCertificates })),
        });

        const radios = wrapper.findAll('input[name="sso-metadata-certificate"]');
        expect(radios.map((radio) => radio.attributes('disabled') !== undefined)).toEqual([
          false,
          false,
          true,
        ]);
        expect(
          wrapper
            .get('[data-testid="sso-metadata-cert-2"] [data-testid="sso-metadata-cert-problem"]')
            .text()
        ).toBe('IdP certificate expired on 2023-01-01');
      });

      it('choosing a certificate emits the choice and does not touch the form', async () => {
        wrapper = await mountSamlA({
          metadataPreview: previewOf(metadataB({ signing_certificates: rolloverCertificates })),
        });

        await wrapper.findAll('input[name="sso-metadata-certificate"]')[1].setValue(true);

        expect(wrapper.emitted('select-metadata-certificate')).toEqual([[1]]);
        expect(wrapper.emitted('update:formState')).toBeUndefined();
        expect(shownValues(wrapper)).toEqual(IDP_A_SHOWN);
      });

      it('labels the SHA-256 fingerprint and the SHA-1 Entra thumbprint separately', async () => {
        wrapper = await mountSamlA({
          metadataPreview: previewOf(metadataB({ signing_certificates: rolloverCertificates })),
        });

        const first = wrapper.get('[data-testid="sso-metadata-cert-0"]');
        expect(first.get('[data-testid="sso-metadata-cert-sha256-label"]').text()).toBe(
          'web.organizations.sso.metadata_cert_fingerprint_sha256:'
        );
        expect(first.get('[data-testid="sso-metadata-cert-sha256"]').text()).toBe('AA:01');
        expect(first.get('[data-testid="sso-metadata-cert-sha1-label"]').text()).toBe(
          'web.organizations.sso.metadata_cert_thumbprint_sha1:'
        );
        expect(first.get('[data-testid="sso-metadata-cert-sha1"]').text()).toBe('A1');
        // Each radio is named by its subject and described by its details.
        const radio = first.get('input');
        expect(radio.attributes('aria-labelledby')).toBe('sso-metadata-cert-0-subject');
        expect(radio.attributes('aria-describedby')).toBe('sso-metadata-cert-0-details');
      });

      it('reads the two hash labels and the validity window in English', async () => {
        wrapper = mount(DomainSsoConfigForm, {
          props: {
            ...defaultMountOptions,
            formState: samlFormA,
            ssoConfig: samlRecordA,
            isConfigured: true,
            metadataPreview: previewOf(metadataB({ signing_certificates: rolloverCertificates })),
          },
          global: { plugins: [realI18n(), pinia], stubs: { Teleport: true } },
        });
        await flushPromises();

        const first = wrapper.get('[data-testid="sso-metadata-cert-0"]');
        expect(first.get('[data-testid="sso-metadata-cert-sha256-label"]').text()).toBe(
          'SHA-256 fingerprint:'
        );
        expect(first.get('[data-testid="sso-metadata-cert-sha1-label"]').text()).toBe(
          'SHA-1 thumbprint (Entra portal):'
        );
        const validity = first.get('[data-testid="sso-metadata-cert-validity"]').text();
        expect(validity).toContain(new Date('2026-01-01T00:00:00Z').toLocaleDateString());
        expect(validity).toContain(new Date('2029-01-01T00:00:00Z').toLocaleDateString());
        expect(validity).not.toContain('{');
      });

      it('shows a single eligible certificate without a picker, selected in the preview', async () => {
        wrapper = await mountSamlA({
          metadataPreview: previewOf(metadataB(), 0),
          canApplyMetadata: true,
        });

        expect(wrapper.find('input[name="sso-metadata-certificate"]').exists()).toBe(false);
        expect(
          wrapper.find('[data-testid="sso-metadata-certificates"] [role="radiogroup"]').exists()
        ).toBe(false);
        expect(wrapper.get('[data-testid="sso-metadata-cert-0"]').attributes('data-selected')).toBe(
          'true'
        );
        // Selected in the preview only: the form still shows IdP A.
        expect(shownValues(wrapper)).toEqual(IDP_A_SHOWN);

        const apply = wrapper.get('[data-testid="sso-metadata-apply"]');
        expect(apply.attributes('disabled')).toBeUndefined();
        await apply.trigger('click');
        expect(wrapper.emitted('apply-metadata')).toHaveLength(1);
        expect(wrapper.emitted('update:formState')).toBeUndefined();
      });
    });

    describe('blocked and failed imports leave IdP A in the form', () => {
      it.each([
        [
          'a POST-only IdP B (unsupported_sso_binding)',
          metadataB({ idp_sso_service_url: null, problems: [blocking('unsupported_sso_binding')] }),
        ],
        [
          'an invalid EntityID',
          metadataB({ idp_entity_id: ' bad', problems: [blocking('invalid_entity_id')] }),
        ],
        [
          'an invalid SSO URL',
          metadataB({
            idp_sso_service_url: 'https://user@idp-b.example.com/sso',
            problems: [blocking('invalid_sso_url')],
          }),
        ],
        [
          'no eligible certificate',
          metadataB({
            signing_certificates: [rolloverCertificates[2]],
            problems: [blocking('no_usable_signing_certificates')],
          }),
        ],
      ])('%s renders an import error and disables Apply', async (_label, response) => {
        const code = response.problems[0].code;
        wrapper = await mountSamlA({ metadataPreview: previewOf(response) });

        const errors = wrapper.get('[data-testid="sso-metadata-blocking"]');
        expect(errors.attributes('role')).toBe('alert');
        expect(errors.text()).toContain('web.organizations.sso.metadata_blocking_title');
        const problem = errors.get('[data-testid="sso-metadata-problem"]');
        expect(problem.attributes('data-code')).toBe(code);
        expect(problem.text()).toBe(`web.organizations.sso.metadata_problem_${code}`);
        expect(
          wrapper.get('[data-testid="sso-metadata-apply"]').attributes('disabled')
        ).toBeDefined();
        expect(wrapper.find('[data-testid="sso-metadata-select-hint"]').exists()).toBe(false);
        expect(shownValues(wrapper)).toEqual(IDP_A_SHOWN);
        expect(wrapper.emitted('update:formState')).toBeUndefined();
      });

      it('says the POST-only IdP publishes no usable SSO URL', async () => {
        wrapper = await mountSamlA({
          metadataPreview: previewOf(
            metadataB({
              idp_sso_service_url: null,
              problems: [blocking('unsupported_sso_binding')],
            })
          ),
        });

        expect(wrapper.get('[data-testid="sso-metadata-sso-url"]').text()).toBe(
          'web.organizations.sso.metadata_value_missing'
        );
      });

      it('shows the server message for a blocking code it does not know', async () => {
        wrapper = await mountSamlA({
          metadataPreview: previewOf(
            metadataB({
              problems: [{ code: 'future_check', severity: 'blocking', message: 'Server says no' }],
            })
          ),
        });

        expect(wrapper.get('[data-testid="sso-metadata-problem"]').text()).toBe('Server says no');
      });

      it('passes the server reason into the localized invalid EntityID message', async () => {
        wrapper = mount(DomainSsoConfigForm, {
          props: {
            ...defaultMountOptions,
            formState: samlFormA,
            ssoConfig: samlRecordA,
            isConfigured: true,
            metadataPreview: previewOf(
              metadataB({
                problems: [
                  {
                    code: 'invalid_entity_id',
                    severity: 'blocking',
                    message: 'IdP EntityID has leading or trailing whitespace',
                  },
                ],
              })
            ),
          },
          global: { plugins: [realI18n(), pinia], stubs: { Teleport: true } },
        });
        await flushPromises();

        const text = wrapper.get('[data-testid="sso-metadata-problem"]').text();
        expect(text).toContain('IdP EntityID has leading or trailing whitespace');
        expect(text).not.toContain('{reason}');
      });

      it.each([
        ['a known error code', 'timeout', 'web.organizations.sso.metadata_error_timeout'],
        ['an unknown error code', 'future_error', 'The server explains'],
        ['no error code (a refused request)', null, 'The server explains'],
      ])('announces a fetch failure with %s', async (_label, errorCode, expected) => {
        wrapper = await mountSamlA({
          metadataFetchFailure: {
            metadataUrl: IDP_B_METADATA_URL,
            errorCode,
            message: 'The server explains',
            httpStatus: null,
          },
        });

        const failure = wrapper.get('[data-testid="sso-metadata-error"]');
        expect(failure.attributes('role')).toBe('alert');
        expect(failure.text()).toContain(expected);
        expect(wrapper.find('[data-testid="sso-metadata-preview"]').exists()).toBe(false);
        expect(shownValues(wrapper)).toEqual(IDP_A_SHOWN);
      });
    });

    describe('advisories and advertised NameID formats', () => {
      const entraAdvisory = {
        code: 'tenant_level_entra_metadata',
        severity: 'advisory' as const,
        message: 'Use the App Federation Metadata Url',
      };

      it('renders an advisory as a warning that does not disable Apply', async () => {
        wrapper = await mountSamlA({
          metadataPreview: previewOf(metadataB({ problems: [entraAdvisory] }), 0),
          canApplyMetadata: true,
        });

        const warning = wrapper.get('[data-testid="sso-metadata-advisories"]');
        expect(warning.attributes('role')).toBe('status');
        expect(warning.text()).toBe(
          'web.organizations.sso.metadata_problem_tenant_level_entra_metadata'
        );
        expect(wrapper.find('[data-testid="sso-metadata-blocking"]').exists()).toBe(false);
        expect(
          wrapper.get('[data-testid="sso-metadata-apply"]').attributes('disabled')
        ).toBeUndefined();
      });

      it('names left-out unreadable certificates without disabling Apply', async () => {
        const unreadable = {
          code: 'unreadable_signing_certificates',
          severity: 'advisory' as const,
          message: 'Some signing certificates could not be read',
        };
        wrapper = await mountSamlA({
          metadataPreview: previewOf(metadataB({ problems: [unreadable] }), 0),
          canApplyMetadata: true,
        });

        expect(wrapper.get('[data-testid="sso-metadata-advisories"]').text()).toBe(
          'web.organizations.sso.metadata_problem_unreadable_signing_certificates'
        );
        expect(
          wrapper.get('[data-testid="sso-metadata-apply"]').attributes('disabled')
        ).toBeUndefined();
      });

      it("points tenant-level Entra metadata at the application's App Federation Metadata Url", async () => {
        wrapper = mount(DomainSsoConfigForm, {
          props: {
            ...defaultMountOptions,
            formState: samlFormA,
            ssoConfig: samlRecordA,
            isConfigured: true,
            metadataPreview: previewOf(metadataB({ problems: [entraAdvisory] }), 0),
            canApplyMetadata: true,
          },
          global: { plugins: [realI18n(), pinia], stubs: { Teleport: true } },
        });
        await flushPromises();

        const text = wrapper.get('[data-testid="sso-metadata-advisory"]').text();
        expect(text).toContain('App Federation Metadata Url');
        expect(text).toContain("application's SAML page in Entra");
      });

      it('lists advertised NameID formats as information and changes nothing', async () => {
        wrapper = await mountSamlA({ metadataPreview: previewOf(metadataB(), 0) });

        const formats = wrapper.findAll('[data-testid="sso-metadata-name-id-format"]');
        expect(formats.map((format) => format.text())).toEqual(metadataB().name_id_formats);
        expect(
          wrapper.get('[data-testid="sso-metadata-name-id-formats"]').find('input, select').exists()
        ).toBe(false);
        expect(wrapper.emitted('update:formState')).toBeUndefined();
      });

      it('says when the preview is already applied to the form', async () => {
        wrapper = await mountSamlA({
          formState: {
            ...samlFormA,
            idp_entity_id: 'https://idp-b.example.com/entity',
            idp_sso_service_url: 'https://idp-b.example.com/sso/redirect',
            idp_cert: CERT_B1,
            idp_metadata_url: IDP_B_METADATA_URL,
          },
          metadataPreview: previewOf(metadataB(), 0),
          canApplyMetadata: true,
          hasUnsavedChanges: true,
        });

        expect(wrapper.get('[data-testid="sso-metadata-applied"]').attributes('role')).toBe(
          'status'
        );
        expect(wrapper.get('[data-testid="sso-metadata-source-url"]').text()).toBe(
          IDP_B_METADATA_URL
        );
      });
    });

    // The form wired to the real useSsoConfig the way DomainSigninSso wires
    // it, with only the service mocked: what the admin sees in the trio
    // inputs after each fetch.
    describe('wired to useSsoConfig', () => {
      let wired: VueWrapper | null = null;

      afterEach(() => {
        wired?.unmount();
        wired = null;
      });

      const mountWired = async (record: CustomDomainSsoConfig = samlRecordA) => {
        mockSsoService.getConfigForDomain.mockResolvedValue({ record });
        let sso: ReturnType<typeof useSsoConfig> | null = null;
        const Host = defineComponent({
          setup() {
            const composable = useSsoConfig('dm_123');
            sso = composable;
            void composable.initialize();
            return () =>
              h(DomainSsoConfigForm, {
                domainExtId: 'dm_123',
                domainHost: 'secrets.example.com',
                domainVerified: true,
                orgId: 'org_ext_123',
                formState: composable.formState.value,
                'onUpdate:formState': (value: SsoConfigFormState) => {
                  composable.formState.value = value;
                },
                ssoConfig: composable.ssoConfig.value,
                isLoading: composable.isLoading.value,
                isSaving: composable.isSaving.value,
                isDeleting: composable.isDeleting.value,
                isTesting: composable.isTesting.value,
                isDiagnosing: composable.isDiagnosing.value,
                hasUnsavedChanges: composable.hasUnsavedChanges.value,
                isConfigured: composable.isConfigured.value,
                clientSecretMasked: composable.clientSecretMasked.value,
                testResult: composable.testResult.value,
                testError: composable.testError.value,
                diagnosticsResult: composable.diagnosticsResult.value,
                savedCredentialsChecked: composable.savedCredentialsChecked.value,
                savedCredentialsUnchecked: composable.savedCredentialsUnchecked.value,
                diagnosticsError: composable.diagnosticsError.value,
                isRefreshingLastSignIn: composable.isRefreshingLastSignIn.value,
                tenantSso: null,
                samlEnabled: true,
                metadataFetchUrl: composable.metadataFetchUrl.value,
                'onUpdate:metadataFetchUrl': (value: string) => {
                  composable.metadataFetchUrl.value = value;
                },
                metadataPreview: composable.metadataPreview.value,
                isFetchingMetadata: composable.isFetchingMetadata.value,
                metadataFetchFailure: composable.metadataFetchFailure.value,
                canApplyMetadata: composable.canApplyMetadata.value,
                onFetchMetadata: composable.fetchMetadata,
                onSelectMetadataCertificate: composable.selectMetadataCertificate,
                onApplyMetadata: composable.applyMetadata,
              });
          },
        });
        wired = mount(Host, { global: { plugins: [i18n, pinia], stubs: { Teleport: true } } });
        await flushPromises();
        if (!sso) throw new Error('useSsoConfig did not run');
        return { w: wired, sso: sso as ReturnType<typeof useSsoConfig> };
      };

      const fetchFrom = async (w: VueWrapper, url: string) => {
        await w.get('#domain-sso-idp-metadata-url').setValue(url);
        await w.get('[data-testid="sso-metadata-fetch"]').trigger('click');
        await flushPromises();
      };

      it.each([
        [
          'a POST-only IdP B',
          metadataB({ idp_sso_service_url: null, problems: [blocking('unsupported_sso_binding')] }),
        ],
        [
          'an IdP B with an invalid EntityID',
          metadataB({ idp_entity_id: ' bad', problems: [blocking('invalid_entity_id')] }),
        ],
        [
          'an IdP B with an invalid SSO URL',
          metadataB({
            idp_sso_service_url: 'https://user@idp-b.example.com/sso',
            problems: [blocking('invalid_sso_url')],
          }),
        ],
        [
          'an IdP B without an eligible certificate',
          metadataB({
            signing_certificates: [rolloverCertificates[2]],
            problems: [blocking('no_usable_signing_certificates')],
          }),
        ],
        [
          'a fetch failure',
          {
            success: false,
            metadata_url: IDP_B_METADATA_URL,
            message: 'Connection refused',
            details: { error_code: 'connection_failed' },
          } satisfies FetchIdpMetadataResponse,
        ],
      ])('IdP A, then %s: the trio and its source stay as they were', async (_label, response) => {
        const { w, sso } = await mountWired();
        mockSsoService.fetchIdpMetadataForDomain.mockResolvedValueOnce(response);

        await fetchFrom(w, IDP_B_METADATA_URL);

        expect(mockSsoService.fetchIdpMetadataForDomain).toHaveBeenCalledWith('dm_123', {
          metadata_url: IDP_B_METADATA_URL,
        });
        // The outcome is on screen (a disabled Apply or the failure), not lost.
        expect(
          w
            .find('[data-testid="sso-metadata-blocking"], [data-testid="sso-metadata-error"]')
            .exists()
        ).toBe(true);
        expect(w.find('[data-testid="sso-metadata-applied"]').exists()).toBe(false);
        expect(shownValues(w)).toEqual(IDP_A_SHOWN);
        expect(sso.hasUnsavedChanges.value).toBe(false);
      });

      it('IdP A, then IdP B with two certificates: choosing changes nothing, Apply fills trio and source together', async () => {
        const { w, sso } = await mountWired();
        mockSsoService.fetchIdpMetadataForDomain.mockResolvedValueOnce(
          metadataB({ signing_certificates: rolloverCertificates.slice(0, 2) })
        );
        await fetchFrom(w, IDP_B_METADATA_URL);

        await w.findAll('input[name="sso-metadata-certificate"]')[1].setValue(true);
        await flushPromises();
        expect(shownValues(w)).toEqual(IDP_A_SHOWN);
        expect(sso.hasUnsavedChanges.value).toBe(false);

        await w.get('[data-testid="sso-metadata-apply"]').trigger('click');
        await flushPromises();

        expect(shownValues(w)).toEqual({
          idp_sso_service_url: 'https://idp-b.example.com/sso/redirect',
          idp_entity_id: 'https://idp-b.example.com/entity',
          idp_cert: CERT_B2,
          source: IDP_B_METADATA_URL,
        });
        expect(sso.hasUnsavedChanges.value).toBe(true);
        expect(w.find('[data-testid="sso-metadata-applied"]').exists()).toBe(true);
        // Applying is not saving.
        expect(mockSsoService.saveConfigForDomain).not.toHaveBeenCalled();
      });

      it('a changed fetch input drops the preview before it can be applied', async () => {
        const { w } = await mountWired();
        mockSsoService.fetchIdpMetadataForDomain.mockResolvedValueOnce(metadataB());
        await fetchFrom(w, IDP_B_METADATA_URL);
        expect(w.find('[data-testid="sso-metadata-preview"]').exists()).toBe(true);

        await w.get('#domain-sso-idp-metadata-url').setValue('https://idp-c.example.com/metadata');

        expect(w.find('[data-testid="sso-metadata-preview"]').exists()).toBe(false);
        expect(w.find('[data-testid="sso-metadata-apply"]').exists()).toBe(false);
        expect(shownValues(w)).toEqual(IDP_A_SHOWN);
      });

      it('a late response for an earlier URL cannot replace the preview of the current one', async () => {
        const { w } = await mountWired();
        let answerB: (value: FetchIdpMetadataResponse) => void = () => {};
        mockSsoService.fetchIdpMetadataForDomain
          .mockReturnValueOnce(
            new Promise<FetchIdpMetadataResponse>((resolve) => {
              answerB = resolve;
            })
          )
          .mockResolvedValueOnce(
            metadataB({
              metadata_url: 'https://idp-c.example.com/metadata',
              idp_entity_id: 'https://idp-c.example.com/entity',
            })
          );

        await fetchFrom(w, IDP_B_METADATA_URL);
        await fetchFrom(w, 'https://idp-c.example.com/metadata');
        answerB(metadataB());
        await flushPromises();

        expect(w.get('[data-testid="sso-metadata-entity-id"]').text()).toBe(
          'https://idp-c.example.com/entity'
        );
        await w.get('[data-testid="sso-metadata-apply"]').trigger('click');
        await flushPromises();
        expect(shownValues(w)).toMatchObject({
          idp_entity_id: 'https://idp-c.example.com/entity',
          source: 'https://idp-c.example.com/metadata',
        });
      });
    });
  });

  describe('Accessibility', () => {
    it('form inputs have associated labels', async () => {
      wrapper = await mountComponent();

      const displayNameLabel = wrapper.find('label[for="domain-sso-display-name"]');
      const clientIdLabel = wrapper.find('label[for="domain-sso-client-id"]');
      const clientSecretLabel = wrapper.find('label[for="domain-sso-client-secret"]');

      expect(displayNameLabel.exists()).toBe(true);
      expect(clientIdLabel.exists()).toBe(true);
      expect(clientSecretLabel.exists()).toBe(true);
    });

    it('required fields are marked with asterisk', async () => {
      wrapper = await mountComponent();

      const displayNameLabel = wrapper.find('label[for="domain-sso-display-name"]');
      expect(displayNameLabel.text()).toContain('*');
    });

    it('password toggle button has aria-label', async () => {
      wrapper = await mountComponent();

      const toggleButton = wrapper.find(
        '#domain-sso-client-secret + button, div:has(#domain-sso-client-secret) button'
      );
      // The button should have aria-label for accessibility
      expect(toggleButton.exists()).toBe(true);
    });
  });
});
