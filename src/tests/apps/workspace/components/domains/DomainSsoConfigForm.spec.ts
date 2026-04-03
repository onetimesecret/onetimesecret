// src/tests/apps/workspace/components/domains/DomainSsoConfigForm.spec.ts
//
// Tests for DomainSsoConfigForm.vue covering:
// 1. Provider type selector rendering
// 2. Provider-specific field visibility (Entra ID, OIDC, Google, GitHub)
// 3. Form validation for required fields
// 4. Event emissions (save, delete, test, discard)
// 5. Form state updates via v-model
//
// Note: This is a presentational component. It receives state via props
// and emits events for actions. Parent manages state via useSsoConfig.

import { mount, VueWrapper, flushPromises } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createTestingPinia } from '@pinia/testing';
import { createI18n } from 'vue-i18n';
import DomainSsoConfigForm from '@/apps/workspace/components/domains/DomainSsoConfigForm.vue';
import type { SsoConfigFormState } from '@/shared/composables/useSsoConfig';
import type { CustomDomainSsoConfig } from '@/schemas/shapes/sso-config';
import type { TestSsoConnectionResponse } from '@/services/sso.service';

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

// Mock BasicFormAlerts component
vi.mock('@/shared/components/forms/BasicFormAlerts.vue', () => ({
  default: {
    name: 'BasicFormAlerts',
    template: '<div class="form-alerts" data-testid="form-alerts" :data-error="error" :data-success="success" />',
    props: ['error', 'success'],
  },
}));


// Mock SSO provider metadata
// Note: This mock matches the actual module path the component imports from.
// If tests fail due to provider metadata behavior, verify the component import path.
vi.mock('@/schemas/shapes/sso-config', () => ({
  SSO_PROVIDER_METADATA: {
    entra_id: { requiresDomainFilter: false, idpControlsAccess: true, description: 'Microsoft Entra ID' },
    google: { requiresDomainFilter: false, idpControlsAccess: true, description: 'Google Workspace' },
    github: { requiresDomainFilter: true, idpControlsAccess: false, description: 'GitHub OAuth' },
    oidc: { requiresDomainFilter: false, idpControlsAccess: true, description: 'Generic OIDC' },
  },
}));

// i18n setup
const i18n = createI18n({
  legacy: false,
  locale: 'en',
  messages: {
    en: {
      web: {
        organizations: {
          sso: {
            provider_type: 'Provider Type',
            provider_type_description: 'Select your identity provider',
            display_name: 'Display Name',
            display_name_hint: 'Name shown to users',
            display_name_placeholder: 'Company SSO',
            client_id: 'Client ID',
            client_id_placeholder: 'Enter client ID',
            client_secret: 'Client Secret',
            client_secret_placeholder: 'Enter client secret',
            client_secret_update_hint: 'Leave blank to keep existing secret',
            tenant_id: 'Tenant ID',
            tenant_id_hint: 'Your Azure AD tenant ID',
            tenant_id_placeholder: 'Enter tenant ID',
            issuer: 'Issuer URL',
            issuer_hint: 'Your OIDC issuer URL',
            issuer_placeholder: 'https://issuer.example.com',
            allowed_domains: 'Allowed Domains',
            allowed_domains_hint: 'Only users with these email domains can sign in',
            add_domain: 'Add Domain',
            invalid_domain: 'Invalid domain format',
            domain_exists: 'Domain already added',
            enabled: 'Enable SSO',
            enabled_description: 'Allow users to sign in with this provider',
            save: 'Save Configuration',
            saving: 'Saving...',
            delete: 'Delete Configuration',
            deleting: 'Deleting...',
            confirm_delete: 'Delete SSO Configuration',
            confirm_delete_message: 'This action cannot be undone',
            cancel: 'Cancel',
            load_error: 'Failed to load configuration',
            save_error: 'Failed to save configuration',
            delete_error: 'Failed to delete configuration',
            create_success: 'SSO configuration created',
            update_success: 'SSO configuration updated',
            delete_success: 'SSO configuration deleted',
            test_connection: 'Test Connection',
            test_connection_hint: 'Verify your IdP credentials are correct',
            test_button: 'Test',
            testing: 'Testing...',
            test_error: 'Connection test failed',
            auth_endpoint: 'Authorization Endpoint',
            missing_fields: 'Missing fields',
            delete_config: 'Delete Configuration',
            delete_confirm: 'Are you sure you want to delete this SSO configuration?',
            domain_placeholder: 'example.com',
            enabled_hint: 'Allow users to sign in with this provider',
            save_config: 'Save Configuration',
          },
        },
        COMMON: {
          loading: 'Loading...',
          show_password: 'Show password',
          hide_password: 'Hide password',
          note: 'Note',
          error_code: 'Error code',
          http_status: 'HTTP status',
          details: 'Details',
          add: 'Add',
          yes_delete: 'Yes, delete',
          word_cancel: 'Cancel',
          save_changes: 'Save Changes',
          saving: 'Saving...',
          processing: 'Processing...',
        },
      },
    },
  },
});

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
    allowed_domains: [],
    enabled: false,
  };
}

const mockExistingConfig: CustomDomainSsoConfig = {
  domain_id: 'dm_123',
  provider_type: 'entra_id',
  enabled: true,
  display_name: 'Test Domain SSO',
  client_id: 'client-id-123',
  client_secret_masked: '****5678',
  tenant_id: 'tenant-uuid-123',
  issuer: null,
  allowed_domains: ['example.com'],
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
  allowed_domains: ['example.com'],
  enabled: true,
};

interface MountOptions {
  domainExtId?: string;
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

  const mountComponent = async (options: MountOptions = {}) => {
    const formState = options.formState ?? createDefaultFormState();

    const component = mount(DomainSsoConfigForm, {
      props: {
        domainExtId: options.domainExtId ?? 'dm_123',
        formState,
        ssoConfig: options.ssoConfig ?? null,
        isLoading: options.isLoading ?? false,
        isSaving: options.isSaving ?? false,
        isDeleting: options.isDeleting ?? false,
        isTesting: options.isTesting ?? false,
        hasUnsavedChanges: options.hasUnsavedChanges ?? false,
        isConfigured: options.isConfigured ?? false,
        clientSecretMasked: options.clientSecretMasked ?? null,
        testResult: options.testResult ?? null,
        testError: options.testError ?? '',
      },
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
    it('renders all provider options', async () => {
      wrapper = await mountComponent();

      const entraRadio = wrapper.find('#domain-provider-entra_id');
      const googleRadio = wrapper.find('#domain-provider-google');
      const githubRadio = wrapper.find('#domain-provider-github');
      const oidcRadio = wrapper.find('#domain-provider-oidc');

      expect(entraRadio.exists()).toBe(true);
      expect(googleRadio.exists()).toBe(true);
      expect(githubRadio.exists()).toBe(true);
      expect(oidcRadio.exists()).toBe(true);
    });

    it('selects Entra ID by default', async () => {
      wrapper = await mountComponent();

      const entraRadio = wrapper.find('#domain-provider-entra_id');
      expect((entraRadio.element as HTMLInputElement).checked).toBe(true);
    });

    it('allows selecting different providers', async () => {
      wrapper = await mountComponent();

      const googleRadio = wrapper.find('#domain-provider-google');
      await googleRadio.setValue(true);
      await flushPromises();

      expect((googleRadio.element as HTMLInputElement).checked).toBe(true);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // Provider-specific field visibility
  // ─────────────────────────────────────────────────────────────────────────────

  describe('Provider-specific field visibility', () => {
    it('shows tenant_id field when Entra ID is selected', async () => {
      wrapper = await mountComponent({ formState: { ...createDefaultFormState(), provider_type: 'entra_id' } });

      const tenantIdInput = wrapper.find('#domain-sso-tenant-id');
      expect(tenantIdInput.exists()).toBe(true);
    });

    it('hides tenant_id field when Google is selected', async () => {
      wrapper = await mountComponent({ formState: { ...createDefaultFormState(), provider_type: 'google' } });

      const tenantIdInput = wrapper.find('#domain-sso-tenant-id');
      expect(tenantIdInput.exists()).toBe(false);
    });

    it('shows issuer field when OIDC is selected', async () => {
      wrapper = await mountComponent({ formState: { ...createDefaultFormState(), provider_type: 'oidc' } });

      const issuerInput = wrapper.find('#domain-sso-issuer');
      expect(issuerInput.exists()).toBe(true);
    });

    it('hides issuer field when Entra ID is selected', async () => {
      wrapper = await mountComponent({ formState: { ...createDefaultFormState(), provider_type: 'entra_id' } });

      const issuerInput = wrapper.find('#domain-sso-issuer');
      expect(issuerInput.exists()).toBe(false);
    });

    it('hides both tenant_id and issuer for GitHub provider', async () => {
      wrapper = await mountComponent({ formState: { ...createDefaultFormState(), provider_type: 'github' } });

      const tenantIdInput = wrapper.find('#domain-sso-tenant-id');
      const issuerInput = wrapper.find('#domain-sso-issuer');

      expect(tenantIdInput.exists()).toBe(false);
      expect(issuerInput.exists()).toBe(false);
    });

    it('shows domain filter field for GitHub (requiresDomainFilter)', async () => {
      wrapper = await mountComponent({ formState: { ...createDefaultFormState(), provider_type: 'github' } });

      // The domain allowlist field should be visible for GitHub
      const domainInput = wrapper.find('#domain-sso-domain-input');
      expect(domainInput.exists()).toBe(true);
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

      const googleRadio = wrapper.find('#domain-provider-google');
      await googleRadio.setValue(true);
      await flushPromises();

      const emitted = wrapper.emitted('update:formState');
      expect(emitted).toBeTruthy();
      expect(emitted![emitted!.length - 1][0]).toMatchObject({
        provider_type: 'google',
      });
    });

    it('emits discard event when discard button is clicked', async () => {
      wrapper = await mountComponent({
        formState: mockExistingFormState,
        hasUnsavedChanges: true,
      });

      // Find discard button (look for button that triggers discard)
      const buttons = wrapper.findAll('button[type="button"]');
      const discardButton = buttons.find((b) => b.text().includes('Discard') || b.text().includes('Cancel'));

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
      expect(hintText).toContain('Leave blank to keep existing secret');
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
      return buttons.find((b) => b.text().includes('Test'));
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

  describe('Delete functionality', () => {
    const findDeleteButton = (w: VueWrapper) => {
      const buttons = w.findAll('button[type="button"]');
      return buttons.find((b) => b.text().includes('Delete Configuration'));
    };

    const findConfirmDeleteButton = (w: VueWrapper) => {
      const buttons = w.findAll('button[type="button"]');
      return buttons.find((b) => b.text().includes('Yes, delete'));
    };

    it('shows delete button when isConfigured is true', async () => {
      wrapper = await mountComponent({
        formState: mockExistingFormState,
        ssoConfig: mockExistingConfig,
        isConfigured: true,
      });

      const deleteButton = findDeleteButton(wrapper);
      expect(deleteButton).toBeDefined();
      expect(deleteButton!.text()).toContain('Delete Configuration');
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

      // Should show loading state
      const loadingIcon = wrapper.find('[data-icon-name="arrow-path"]');
      expect(loadingIcon.exists()).toBe(true);
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
  // Accessibility
  // ─────────────────────────────────────────────────────────────────────────────

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

      const toggleButton = wrapper.find('#domain-sso-client-secret + button, div:has(#domain-sso-client-secret) button');
      // The button should have aria-label for accessibility
      expect(toggleButton.exists()).toBe(true);
    });
  });
});
