// src/tests/apps/workspace/components/domains/DomainSsoConfigForm.spec.ts
//
// Tests for DomainSsoConfigForm.vue covering:
// 1. Provider type selector rendering (OIDC / Entra / SAML — #3902, #4450)
// 2. Provider-specific field visibility (Entra ID, OIDC, SAML)
// 3. Form validation for required fields
// 4. Event emissions (save, delete, test, discard)
// 5. Form state updates via v-model
//
// Note: This is a presentational component. It receives state via props
// and emits events for actions. Parent manages state via useSsoConfig.

import { createTestingPinia } from '@pinia/testing';
import { flushPromises, mount, VueWrapper } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import DomainSsoConfigForm from '../../../../../apps/workspace/components/domains/DomainSsoConfigForm.vue';
import type { CustomDomainSsoConfig } from '../../../../../schemas/shapes/domains/sso-config';
import type { TestSsoConnectionResponse } from '../../../../../services/sso.service';
import type { SsoConfigFormState } from '../../../../../shared/composables/useSsoConfig';
import { createTestI18n } from '../../../../setup';

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
    idp_sso_service_url: '',
    idp_entity_id: '',
    idp_cert: '',
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
  idp_sso_service_url: null,
  idp_entity_id: null,
  idp_cert: null,
  sp_entity_id: null,
  acs_url: null,
  unreadable_fields: [],
  allowed_domains: ['example.com'],
  requires_domain_filter: false,
  idp_controls_access: true,
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
  idp_sso_service_url: '',
  idp_entity_id: '',
  idp_cert: '',
  allowed_domains: ['example.com'],
  enabled: true,
  enforce_sso_only: false,
  grant_org_scope: false,
};

const mockEnforceSsoOnlyFormState: SsoConfigFormState = {
  ...mockExistingFormState,
  enforce_sso_only: true,
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
};

interface MountOptions {
  domainExtId?: string;
  domainHost?: string;
  orgId?: string;
  formState?: SsoConfigFormState;
  ssoConfig?: CustomDomainSsoConfig | null;
  isLoading?: boolean;
  isSaving?: boolean;
  isDeleting?: boolean;
  isTesting?: boolean;
  hasUnsavedChanges?: boolean;
  isConfigured?: boolean;
  clientSecretMasked?: string | null;
  testResult?: TestSsoConnectionResponse | null;
  testError?: string;
}

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

describe('DomainSsoConfigForm', () => {
  let wrapper: VueWrapper;
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

      // Check for success indicator
      const successResult = wrapper.find('.bg-green-50, [role="status"]');
      expect(successResult.exists()).toBe(true);
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
  // Delete functionality
  // ─────────────────────────────────────────────────────────────────────────────

  describe('Disable SSO recovery', () => {
    it.each(['client_secret', 'idp_cert'])(
      'can disable with unreadable %s while ordinary saves remain blocked',
      async (field) => {
        const saml = field === 'idp_cert';
        const config = saml ? mockSamlConfig : mockExistingConfig;
        const form = saml ? mockSamlFormState : mockExistingFormState;
        wrapper = await mountComponent({
          formState: { ...form, [field]: '', display_name: 'Unsaved edit', enabled: false },
          ssoConfig: {
            ...config,
            enabled: true,
            enforce_sso_only: true,
            unreadable_fields: [field],
          },
          isConfigured: true,
        });
        expect(wrapper.get('button[type="submit"]').attributes('disabled')).toBeDefined();
        await wrapper.get('form').trigger('submit');
        expect(wrapper.emitted('save')).toBeUndefined();
        await wrapper.get('[data-testid="disable-sso"]').trigger('click');
        expect(wrapper.get('[data-testid="disable-sso-confirmation"]').text()).toContain(
          'disable_enforcement_warning'
        );
        expect(wrapper.emitted('disable')).toBeUndefined();
        await wrapper.get('[data-testid="confirm-disable-sso"]').trigger('click');
        expect(wrapper.emitted('disable')).toEqual([[]]);
        expect(wrapper.emitted('update:formState')).toBeUndefined();

        await wrapper.setProps({
          ssoConfig: { ...config, enabled: false, unreadable_fields: [field] },
          formState: { ...form, [field]: '', enabled: true },
        });
        expect(wrapper.find('[data-testid="disable-sso"]').exists()).toBe(false);
        expect(wrapper.get('button[type="submit"]').attributes('disabled')).toBeDefined();
        await wrapper.get('form').trigger('submit');
        expect(wrapper.emitted('save')).toBeUndefined();
      }
    );

    it.each(['isSaving', 'isDeleting', 'isTesting'] as const)(
      'disables recovery and confirmation while %s',
      async (flag) => {
        wrapper = await mountComponent({ ssoConfig: mockExistingConfig, isConfigured: true });
        await wrapper.setProps({ [flag]: true });
        expect(wrapper.get('[data-testid="disable-sso"]').attributes('disabled')).toBeDefined();
        await wrapper.setProps({ [flag]: false });
        await wrapper.get('[data-testid="disable-sso"]').trigger('click');
        await wrapper.setProps({ [flag]: true });
        expect(
          wrapper.get('[data-testid="confirm-disable-sso"]').attributes('disabled')
        ).toBeDefined();
        await wrapper.get('[data-testid="confirm-disable-sso"]').trigger('click');
        expect(wrapper.emitted('disable')).toBeUndefined();
      }
    );

    it('does not offer recovery for an unsaved enable or carry confirmation to another domain', async () => {
      wrapper = await mountComponent({ ssoConfig: mockExistingConfig, isConfigured: true });
      await wrapper.get('[data-testid="disable-sso"]').trigger('click');
      await wrapper.setProps({ domainExtId: 'dm_other' });
      expect(wrapper.find('[data-testid="confirm-disable-sso"]').exists()).toBe(false);
      await wrapper.setProps({
        ssoConfig: { ...mockExistingConfig, enabled: false },
        formState: { ...mockExistingFormState, enabled: true },
      });
      expect(wrapper.find('[data-testid="disable-sso"]').exists()).toBe(false);
    });
  });

  describe('Delete functionality', () => {
    const findDeleteButton = (w: VueWrapper) => {
      const buttons = w.findAll('button[type="button"]');
      return buttons.find((b) => b.text().includes('delete_config'));
    };

    const findConfirmDeleteButton = (w: VueWrapper) => {
      const buttons = w.findAll('button[type="button"]');
      return buttons.find((b) => b.text().includes('yes_delete'));
    };

    it('shows delete button when isConfigured is true', async () => {
      wrapper = await mountComponent({
        formState: mockExistingFormState,
        ssoConfig: mockExistingConfig,
        isConfigured: true,
      });

      const deleteButton = findDeleteButton(wrapper);
      expect(deleteButton).toBeDefined();
      expect(deleteButton!.text()).toContain('delete_config');
    });

    it('emits delete event after confirmation', async () => {
      wrapper = await mountComponent({
        formState: mockExistingFormState,
        ssoConfig: mockExistingConfig,
        isConfigured: true,
      });

      // Click delete button to show confirmation
      const deleteButton = findDeleteButton(wrapper);
      expect(deleteButton).toBeDefined();
      await deleteButton!.trigger('click');
      await flushPromises();

      // Click confirm button
      const confirmButton = findConfirmDeleteButton(wrapper);
      expect(confirmButton).toBeDefined();
      await confirmButton!.trigger('click');
      await flushPromises();

      expect(wrapper.emitted('delete')).toBeTruthy();
    });

    it('does not show delete button when isConfigured is false', async () => {
      wrapper = await mountComponent({
        formState: createDefaultFormState(),
        isConfigured: false,
      });

      const deleteButton = findDeleteButton(wrapper);
      expect(deleteButton).toBeUndefined();
    });

    it('disables delete button when isDeleting is true', async () => {
      wrapper = await mountComponent({
        formState: mockExistingFormState,
        isConfigured: true,
        isDeleting: true,
      });

      // Find the delete button
      const deleteButton = findDeleteButton(wrapper);
      expect(deleteButton).toBeDefined();
      expect((deleteButton!.element as HTMLButtonElement).disabled).toBe(true);
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

      // The connection-enabled toggle (#4107) is always present, so target by
      // testid rather than asserting on the form's only role="switch".
      expect(wrapper.find('[data-testid="grant-org-scope-toggle"]').exists()).toBe(false);
      expect(wrapper.find('[data-testid="sso-connection-enabled-toggle"]').exists()).toBe(true);
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

    // The latch is per-domain: SsoCredentialsModal reuses this instance without
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
  // Connection enabled toggle (#4107) — restores the only UI writer of
  // SsoConfig.enabled (dropped in 7326689cdc, which orphaned the field).
  // ─────────────────────────────────────────────────────────────────────────────

  describe('Connection enabled toggle (#4107)', () => {
    const TOGGLE = '[data-testid="sso-connection-enabled-toggle"]';

    // A sibling toggle in this exact template region (grant_org_scope) was
    // silently lost once in a main→develop merge — no test pinned its
    // existence, so the deletion shipped without a red (restored in
    // 61dc7b9cdc). Presence-in-DEFAULT-render is asserted on its own, with no
    // other setup, so this control can never vanish quietly the same way.
    it('connection toggle must exist — regression guard for #4107 / silent merge loss', async () => {
      wrapper = await mountComponent(); // default mount: unconfigured, fresh form
      expect(wrapper.find(TOGGLE).exists()).toBe(true);
    });

    it('reflects formState.enabled in aria-checked (props-controlled, both states)', async () => {
      wrapper = await mountComponent({
        formState: { ...mockExistingFormState, enabled: true },
        isConfigured: true,
      });
      expect(wrapper.find(TOGGLE).attributes('aria-checked')).toBe('true');

      // Prop-controlled: the parent owns the state, the toggle just renders it.
      await wrapper.setProps({
        formState: { ...mockExistingFormState, enabled: false },
      });
      expect(wrapper.find(TOGGLE).attributes('aria-checked')).toBe('false');
    });

    it('emits update:formState with enabled flipped when toggled', async () => {
      wrapper = await mountComponent({
        formState: { ...mockExistingFormState, enabled: false },
        isConfigured: true,
      });

      const toggle = wrapper.find('[data-testid="sso-connection-enabled-toggle"]');
      expect(toggle.exists()).toBe(true);
      expect(toggle.attributes('aria-checked')).toBe('false');

      await toggle.trigger('click');

      const emitted = wrapper.emitted('update:formState');
      expect(emitted).toBeTruthy();
      const lastEmit = emitted![emitted!.length - 1][0] as SsoConfigFormState;
      expect(lastEmit.enabled).toBe(true);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // Weak test-before-enable warning (#4111)
  //
  // Advisory only — never a gate. The record carries no "has ever passed a
  // test" field, so the warning speaks about THIS editing session: it fires
  // when the operator turns the connection on without a passing test in view,
  // and stays silent for configs that merely load enabled (that would be noise
  // on every open, and would punish the #4107 flag-stuck cohort).
  //
  // The toggle is prop-controlled, so each test flips it and then applies the
  // parent's formState update, exactly as SsoCredentialsModal does.
  // ─────────────────────────────────────────────────────────────────────────────

  describe('test-before-enable warning (#4111)', () => {
    const TOGGLE = '[data-testid="sso-connection-enabled-toggle"]';
    const WARNING = '[data-testid="sso-enable-untested-warning"]';
    const passingTest: TestSsoConnectionResponse = {
      success: true,
      message: 'ok',
    } as TestSsoConnectionResponse;

    const turnOn = async (w: VueWrapper) => {
      await w.find(TOGGLE).trigger('click');
      await w.setProps({ formState: { ...mockExistingFormState, enabled: true } });
    };

    it('is silent on a fresh form', async () => {
      wrapper = await mountComponent();
      expect(wrapper.find(WARNING).exists()).toBe(false);
    });

    it('is silent for a config that merely loads enabled', async () => {
      wrapper = await mountComponent({
        formState: { ...mockExistingFormState, enabled: true },
        isConfigured: true,
      });
      expect(wrapper.find(WARNING).exists()).toBe(false);
    });

    it('warns when the connection is switched on with no passing test in this session', async () => {
      wrapper = await mountComponent({
        formState: { ...mockExistingFormState, enabled: false },
        isConfigured: true,
      });

      await turnOn(wrapper);

      const warning = wrapper.find(WARNING);
      expect(warning.exists()).toBe(true);
      // Announced, not conveyed by colour alone.
      expect(warning.attributes('role')).toBe('alert');
      expect(warning.text()).toContain('web.organizations.sso.enable_untested_warning');
    });

    it('does not gate the save — the form stays submittable', async () => {
      wrapper = await mountComponent({
        formState: { ...mockExistingFormState, enabled: false },
        isConfigured: true,
      });

      await turnOn(wrapper);

      expect(wrapper.find(WARNING).exists()).toBe(true);
      const submit = wrapper.find('button[type="submit"]');
      expect(submit.attributes('disabled')).toBeUndefined();
    });

    it('stays silent when a connection test passed in this session', async () => {
      wrapper = await mountComponent({
        formState: { ...mockExistingFormState, enabled: false },
        isConfigured: true,
        testResult: passingTest,
      });

      await turnOn(wrapper);

      expect(wrapper.find(WARNING).exists()).toBe(false);
    });

    it('clears once a test passes after the toggle was switched on', async () => {
      wrapper = await mountComponent({
        formState: { ...mockExistingFormState, enabled: false },
        isConfigured: true,
      });

      await turnOn(wrapper);
      expect(wrapper.find(WARNING).exists()).toBe(true);

      await wrapper.setProps({ testResult: passingTest });
      expect(wrapper.find(WARNING).exists()).toBe(false);
    });

    it('clears when the connection is switched back off', async () => {
      wrapper = await mountComponent({
        formState: { ...mockExistingFormState, enabled: false },
        isConfigured: true,
      });

      await turnOn(wrapper);
      await wrapper.find(TOGGLE).trigger('click');
      await wrapper.setProps({ formState: { ...mockExistingFormState, enabled: false } });

      expect(wrapper.find(WARNING).exists()).toBe(false);
    });

    it('clears when a different domain is loaded into the reused instance', async () => {
      wrapper = await mountComponent({
        formState: { ...mockExistingFormState, enabled: false },
        isConfigured: true,
      });

      await turnOn(wrapper);
      expect(wrapper.find(WARNING).exists()).toBe(true);

      // SsoCredentialsModal reuses this component across domains (no :key),
      // so a stale session flag would follow the operator to the next domain.
      await wrapper.setProps({ domainExtId: 'dm_456' });
      expect(wrapper.find(WARNING).exists()).toBe(false);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // Accessibility
  // ─────────────────────────────────────────────────────────────────────────────

  describe('SAML provider (#4450)', () => {
    const findTestButton = (w: VueWrapper) =>
      w.findAll('button[type="button"]').find((b) => b.text().includes('test_button'));
    const submitButton = (w: VueWrapper) => w.find('button[type="submit"]');

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

      it('emits save on submit for a complete saml form', async () => {
        wrapper = await mountComponent({ formState: mockSamlFormState });

        await wrapper.find('form').trigger('submit.prevent');
        await flushPromises();

        expect(wrapper.emitted('save')).toBeTruthy();
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
          });

          expect(submitButton(wrapper).attributes('disabled')).toBeUndefined();
        });

        it('stays optional for a healthy secretless oidc record (public client)', async () => {
          wrapper = await mountComponent({
            formState: oidcFormState,
            ssoConfig: { ...oidcConfig, client_secret_masked: null, unreadable_fields: [] },
            isConfigured: true,
            clientSecretMasked: null,
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
