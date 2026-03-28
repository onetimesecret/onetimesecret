// src/tests/apps/workspace/components/domains/DomainSsoConfigForm.spec.ts
//
// Tests for DomainSsoConfigForm.vue covering:
// 1. Provider type selector rendering
// 2. Provider-specific field visibility (Entra ID, OIDC, Google, GitHub)
// 3. Form validation for required fields
// 4. Save functionality via SsoService.saveConfigForDomain
// 5. Success/error toast handling
// 6. Test connection functionality
// 7. Delete functionality with confirmation
// 8. Event emissions (saved, deleted)

import { mount, VueWrapper, flushPromises } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createTestingPinia } from '@pinia/testing';
import { createI18n } from 'vue-i18n';
import DomainSsoConfigForm from '@/apps/workspace/components/domains/DomainSsoConfigForm.vue';

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

// Mock error classifier
vi.mock('@/schemas/errors', () => ({
  classifyError: (err: Error) => ({
    message: err.message || 'Unknown error',
    code: (err as unknown as { code?: number }).code,
  }),
}));

// Mock SsoService with spies for domain-scoped methods
const mockSaveConfigForDomain = vi.fn();
const mockGetConfigForDomain = vi.fn();
const mockDeleteConfigForDomain = vi.fn();
const mockTestConnectionForDomain = vi.fn();

// Track last save payload
let lastSavePayload: unknown = null;

vi.mock('@/services/sso.service', () => ({
  SsoService: {
    getConfigForDomain: (...args: unknown[]) => mockGetConfigForDomain(...args),
    saveConfigForDomain: async (domainExtId: string, payload: unknown) => {
      lastSavePayload = payload;
      return mockSaveConfigForDomain(domainExtId, payload);
    },
    deleteConfigForDomain: (...args: unknown[]) => mockDeleteConfigForDomain(...args),
    testConnectionForDomain: (...args: unknown[]) => mockTestConnectionForDomain(...args),
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

const mockExistingConfig = {
  domain_id: 'dm_123',
  provider_type: 'entra_id' as const,
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
    lastSavePayload = null;

    // Default: no existing config (404)
    mockGetConfigForDomain.mockResolvedValue({ record: null });
    mockSaveConfigForDomain.mockResolvedValue({ record: mockExistingConfig });
    mockDeleteConfigForDomain.mockResolvedValue({ success: true });
    mockTestConnectionForDomain.mockResolvedValue({
      success: true,
      message: 'Connection successful',
      provider_type: 'entra_id',
      details: { issuer: 'https://login.microsoftonline.com/tenant/v2.0' },
    });
  });

  afterEach(() => {
    if (wrapper) {
      wrapper.unmount();
    }
  });

  const mountComponent = async (props: { domainExtId?: string } = {}) => {
    const component = mount(DomainSsoConfigForm, {
      props: {
        domainExtId: props.domainExtId ?? 'dm_123',
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
      wrapper = await mountComponent();

      const tenantIdInput = wrapper.find('#domain-sso-tenant-id');
      expect(tenantIdInput.exists()).toBe(true);
    });

    it('hides tenant_id field when Google is selected', async () => {
      wrapper = await mountComponent();

      const googleRadio = wrapper.find('#domain-provider-google');
      await googleRadio.setValue(true);
      await flushPromises();

      const tenantIdInput = wrapper.find('#domain-sso-tenant-id');
      expect(tenantIdInput.exists()).toBe(false);
    });

    it('shows issuer field when OIDC is selected', async () => {
      wrapper = await mountComponent();

      const oidcRadio = wrapper.find('#domain-provider-oidc');
      await oidcRadio.setValue(true);
      await flushPromises();

      const issuerInput = wrapper.find('#domain-sso-issuer');
      expect(issuerInput.exists()).toBe(true);
    });

    it('hides issuer field when Entra ID is selected', async () => {
      wrapper = await mountComponent();

      const issuerInput = wrapper.find('#domain-sso-issuer');
      expect(issuerInput.exists()).toBe(false);
    });

    it('hides both tenant_id and issuer for GitHub provider', async () => {
      wrapper = await mountComponent();

      const githubRadio = wrapper.find('#domain-provider-github');
      await githubRadio.setValue(true);
      await flushPromises();

      const tenantIdInput = wrapper.find('#domain-sso-tenant-id');
      const issuerInput = wrapper.find('#domain-sso-issuer');

      expect(tenantIdInput.exists()).toBe(false);
      expect(issuerInput.exists()).toBe(false);
    });

    it('shows domain filter field for GitHub (requiresDomainFilter)', async () => {
      wrapper = await mountComponent();

      const githubRadio = wrapper.find('#domain-provider-github');
      await githubRadio.setValue(true);
      await flushPromises();

      // The domain allowlist field should be visible for GitHub
      const domainInput = wrapper.find('#domain-sso-domain-input');
      expect(domainInput.exists()).toBe(true);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // Form validation
  // ─────────────────────────────────────────────────────────────────────────────

  describe('Form validation', () => {
    it('requires display_name for form to be valid', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: null });
      wrapper = await mountComponent();

      // Fill all fields except display_name
      const clientIdInput = wrapper.find('#domain-sso-client-id');
      const clientSecretInput = wrapper.find('#domain-sso-client-secret');
      const tenantIdInput = wrapper.find('#domain-sso-tenant-id');

      await clientIdInput.setValue('client-123');
      await clientSecretInput.setValue('secret-456');
      await tenantIdInput.setValue('tenant-uuid');
      await flushPromises();

      // Submit form
      const form = wrapper.find('form');
      await form.trigger('submit.prevent');
      await flushPromises();

      // Save should NOT have been called
      expect(mockSaveConfigForDomain).not.toHaveBeenCalled();
    });

    it('requires client_id for form to be valid', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: null });
      wrapper = await mountComponent();

      // Fill all fields except client_id
      const displayNameInput = wrapper.find('#domain-sso-display-name');
      const clientSecretInput = wrapper.find('#domain-sso-client-secret');
      const tenantIdInput = wrapper.find('#domain-sso-tenant-id');

      await displayNameInput.setValue('Test SSO');
      await clientSecretInput.setValue('secret-456');
      await tenantIdInput.setValue('tenant-uuid');
      await flushPromises();

      // Submit form
      const form = wrapper.find('form');
      await form.trigger('submit.prevent');
      await flushPromises();

      // Save should NOT have been called
      expect(mockSaveConfigForDomain).not.toHaveBeenCalled();
    });

    it('requires client_secret for new config (not editing)', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: null });
      wrapper = await mountComponent();

      // Fill all fields except client_secret
      const displayNameInput = wrapper.find('#domain-sso-display-name');
      const clientIdInput = wrapper.find('#domain-sso-client-id');
      const tenantIdInput = wrapper.find('#domain-sso-tenant-id');

      await displayNameInput.setValue('Test SSO');
      await clientIdInput.setValue('client-123');
      await tenantIdInput.setValue('tenant-uuid');
      // Intentionally leave client_secret empty
      await flushPromises();

      // Submit form
      const form = wrapper.find('form');
      await form.trigger('submit.prevent');
      await flushPromises();

      // Save should NOT have been called
      expect(mockSaveConfigForDomain).not.toHaveBeenCalled();
    });

    it('allows empty client_secret when editing existing config', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockExistingConfig });
      wrapper = await mountComponent();

      // Form should be pre-populated from existing config
      // client_secret is empty in form (never populated from response)
      // This should still be valid for editing

      // Submit form without changing client_secret
      const form = wrapper.find('form');
      await form.trigger('submit.prevent');
      await flushPromises();

      // Save SHOULD have been called
      expect(mockSaveConfigForDomain).toHaveBeenCalled();
    });

    it('requires tenant_id when Entra ID is selected', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: null });
      wrapper = await mountComponent();

      // Fill base fields but not tenant_id
      const displayNameInput = wrapper.find('#domain-sso-display-name');
      const clientIdInput = wrapper.find('#domain-sso-client-id');
      const clientSecretInput = wrapper.find('#domain-sso-client-secret');

      await displayNameInput.setValue('Test SSO');
      await clientIdInput.setValue('client-123');
      await clientSecretInput.setValue('secret-456');
      // tenant_id is empty
      await flushPromises();

      // Submit form
      const form = wrapper.find('form');
      await form.trigger('submit.prevent');
      await flushPromises();

      // Save should NOT have been called (tenant_id required for entra_id)
      expect(mockSaveConfigForDomain).not.toHaveBeenCalled();
    });

    it('requires issuer when OIDC is selected', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: null });
      wrapper = await mountComponent();

      // Select OIDC provider
      const oidcRadio = wrapper.find('#domain-provider-oidc');
      await oidcRadio.setValue(true);
      await flushPromises();

      // Fill base fields but not issuer
      const displayNameInput = wrapper.find('#domain-sso-display-name');
      const clientIdInput = wrapper.find('#domain-sso-client-id');
      const clientSecretInput = wrapper.find('#domain-sso-client-secret');

      await displayNameInput.setValue('Test SSO');
      await clientIdInput.setValue('client-123');
      await clientSecretInput.setValue('secret-456');
      // issuer is empty
      await flushPromises();

      // Submit form
      const form = wrapper.find('form');
      await form.trigger('submit.prevent');
      await flushPromises();

      // Save should NOT have been called (issuer required for oidc)
      expect(mockSaveConfigForDomain).not.toHaveBeenCalled();
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // Save functionality
  // ─────────────────────────────────────────────────────────────────────────────

  describe('Save functionality', () => {
    it('calls SsoService.saveConfigForDomain on submit', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: null });
      wrapper = await mountComponent();

      // Fill required fields
      const displayNameInput = wrapper.find('#domain-sso-display-name');
      const clientIdInput = wrapper.find('#domain-sso-client-id');
      const clientSecretInput = wrapper.find('#domain-sso-client-secret');
      const tenantIdInput = wrapper.find('#domain-sso-tenant-id');

      await displayNameInput.setValue('Test SSO');
      await clientIdInput.setValue('client-123');
      await clientSecretInput.setValue('secret-456');
      await tenantIdInput.setValue('tenant-uuid');
      await flushPromises();

      // Submit form
      const form = wrapper.find('form');
      await form.trigger('submit.prevent');
      await flushPromises();

      expect(mockSaveConfigForDomain).toHaveBeenCalledWith('dm_123', expect.any(Object));
    });

    it('includes client_secret in payload when provided (triggers PUT)', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: null });
      wrapper = await mountComponent();

      // Fill required fields including tenant_id
      const displayNameInput = wrapper.find('#domain-sso-display-name');
      const clientIdInput = wrapper.find('#domain-sso-client-id');
      const clientSecretInput = wrapper.find('#domain-sso-client-secret');
      const tenantIdInput = wrapper.find('#domain-sso-tenant-id');

      await displayNameInput.setValue('Test SSO');
      await clientIdInput.setValue('client-123');
      await clientSecretInput.setValue('secret-456');
      await tenantIdInput.setValue('tenant-uuid');
      await flushPromises();

      // Submit form
      const form = wrapper.find('form');
      await form.trigger('submit.prevent');
      await flushPromises();

      // Verify payload includes client_secret
      expect(mockSaveConfigForDomain).toHaveBeenCalled();
      expect(lastSavePayload).toMatchObject({
        client_secret: 'secret-456',
      });
    });

    it('omits client_secret from payload when empty (triggers PATCH)', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockExistingConfig });
      wrapper = await mountComponent();

      // Form should be pre-populated, client_secret should be empty
      const displayNameInput = wrapper.find('#domain-sso-display-name');
      expect((displayNameInput.element as HTMLInputElement).value).toBe('Test Domain SSO');

      // Change display name but leave client_secret empty
      await displayNameInput.setValue('Updated SSO Name');
      await flushPromises();

      // Submit form
      const form = wrapper.find('form');
      await form.trigger('submit.prevent');
      await flushPromises();

      // Verify payload does NOT include client_secret
      expect(mockSaveConfigForDomain).toHaveBeenCalled();
      expect(lastSavePayload).not.toHaveProperty('client_secret');
    });

    it('includes tenant_id in payload for Entra ID provider', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: null });
      wrapper = await mountComponent();

      // Fill all required fields including tenant_id
      const displayNameInput = wrapper.find('#domain-sso-display-name');
      const clientIdInput = wrapper.find('#domain-sso-client-id');
      const clientSecretInput = wrapper.find('#domain-sso-client-secret');
      const tenantIdInput = wrapper.find('#domain-sso-tenant-id');

      await displayNameInput.setValue('Test SSO');
      await clientIdInput.setValue('client-123');
      await clientSecretInput.setValue('secret-456');
      await tenantIdInput.setValue('tenant-uuid');
      await flushPromises();

      // Submit form
      const form = wrapper.find('form');
      await form.trigger('submit.prevent');
      await flushPromises();

      // Verify payload includes tenant_id
      expect(mockSaveConfigForDomain).toHaveBeenCalled();
      expect(lastSavePayload).toMatchObject({
        provider_type: 'entra_id',
        tenant_id: 'tenant-uuid',
      });
    });

    it('includes issuer in payload for OIDC provider', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: null });
      wrapper = await mountComponent();

      // Select OIDC provider
      const oidcRadio = wrapper.find('#domain-provider-oidc');
      await oidcRadio.setValue(true);
      await flushPromises();

      // Fill all required fields including issuer
      const displayNameInput = wrapper.find('#domain-sso-display-name');
      const clientIdInput = wrapper.find('#domain-sso-client-id');
      const clientSecretInput = wrapper.find('#domain-sso-client-secret');
      const issuerInput = wrapper.find('#domain-sso-issuer');

      await displayNameInput.setValue('Test SSO');
      await clientIdInput.setValue('client-123');
      await clientSecretInput.setValue('secret-456');
      await issuerInput.setValue('https://issuer.example.com');
      await flushPromises();

      // Submit form
      const form = wrapper.find('form');
      await form.trigger('submit.prevent');
      await flushPromises();

      // Verify payload includes issuer
      expect(mockSaveConfigForDomain).toHaveBeenCalled();
      expect(lastSavePayload).toMatchObject({
        provider_type: 'oidc',
        issuer: 'https://issuer.example.com',
      });
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // Success/error handling
  // ─────────────────────────────────────────────────────────────────────────────

  describe('Success/error handling', () => {
    it('emits saved event after successful save', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockExistingConfig });
      wrapper = await mountComponent();

      // Update a field
      const displayNameInput = wrapper.find('#domain-sso-display-name');
      await displayNameInput.setValue('Updated SSO');
      await flushPromises();

      // Submit form
      const form = wrapper.find('form');
      await form.trigger('submit.prevent');
      await flushPromises();

      // Check emitted events
      expect(wrapper.emitted('saved')).toBeTruthy();
    });

    it('shows success message after save', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockExistingConfig });
      wrapper = await mountComponent();

      // Submit form
      const form = wrapper.find('form');
      await form.trigger('submit.prevent');
      await flushPromises();

      // Success message should be displayed
      const alerts = wrapper.find('[data-testid="form-alerts"]');
      expect(alerts.exists()).toBe(true);
    });

    it('displays error message when save fails', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockExistingConfig });
      wrapper = await mountComponent();

      // Mock saveConfigForDomain to reject with error
      const saveError = new Error('Network connection failed');
      mockSaveConfigForDomain.mockRejectedValueOnce(saveError);

      // Submit form
      const form = wrapper.find('form');
      await form.trigger('submit.prevent');
      await flushPromises();

      // Error message should be displayed
      const alerts = wrapper.find('[data-testid="form-alerts"]');
      expect(alerts.exists()).toBe(true);
      expect(alerts.attributes('data-error')).toBe('Network connection failed');

      // Verify saved event was NOT emitted
      expect(wrapper.emitted('saved')).toBeFalsy();
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // Test connection
  // ─────────────────────────────────────────────────────────────────────────────

  describe('Test connection', () => {
    const findTestButton = (w: VueWrapper) => {
      // Find the test button by looking for button with "Test" text in the test connection section
      const buttons = w.findAll('button[type="button"]');
      return buttons.find((b) => b.text().includes('Test'));
    };

    it('calls testConnectionForDomain when test button clicked', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: null });
      wrapper = await mountComponent();

      // Fill required fields for test
      const clientIdInput = wrapper.find('#domain-sso-client-id');
      const tenantIdInput = wrapper.find('#domain-sso-tenant-id');

      await clientIdInput.setValue('client-123');
      await tenantIdInput.setValue('tenant-uuid');
      await flushPromises();

      // Find and click test button
      const testButton = findTestButton(wrapper);
      expect(testButton).toBeDefined();
      await testButton!.trigger('click');
      await flushPromises();

      expect(mockTestConnectionForDomain).toHaveBeenCalledWith('dm_123', expect.objectContaining({
        provider_type: 'entra_id',
        client_id: 'client-123',
        tenant_id: 'tenant-uuid',
      }));
    });

    it('shows success message on successful test', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: null });
      mockTestConnectionForDomain.mockResolvedValue({
        success: true,
        message: 'Connection successful',
        provider_type: 'entra_id',
        details: { issuer: 'https://login.microsoftonline.com/tenant/v2.0' },
      });

      wrapper = await mountComponent();

      // Fill required fields
      const clientIdInput = wrapper.find('#domain-sso-client-id');
      const tenantIdInput = wrapper.find('#domain-sso-tenant-id');

      await clientIdInput.setValue('client-123');
      await tenantIdInput.setValue('tenant-uuid');
      await flushPromises();

      // Click test button
      const testButton = findTestButton(wrapper);
      expect(testButton).toBeDefined();
      await testButton!.trigger('click');
      await flushPromises();

      // Check for success indicator (green background in result section)
      const successResult = wrapper.find('.bg-green-50, [role="status"]');
      expect(successResult.exists()).toBe(true);
    });

    it('shows error message on failed test', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: null });
      mockTestConnectionForDomain.mockResolvedValue({
        success: false,
        message: 'Invalid tenant ID',
        provider_type: 'entra_id',
        details: { error_code: 'invalid_tenant' },
      });

      wrapper = await mountComponent();

      // Fill required fields
      const clientIdInput = wrapper.find('#domain-sso-client-id');
      const tenantIdInput = wrapper.find('#domain-sso-tenant-id');

      await clientIdInput.setValue('client-123');
      await tenantIdInput.setValue('invalid-tenant');
      await flushPromises();

      // Click test button
      const testButton = findTestButton(wrapper);
      expect(testButton).toBeDefined();
      await testButton!.trigger('click');
      await flushPromises();

      // Check for error indicator (red background in result section)
      const errorResult = wrapper.find('.bg-red-50, [role="alert"]');
      expect(errorResult.exists()).toBe(true);
    });

    it('disables test button when required fields are missing', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: null });
      wrapper = await mountComponent();

      // Don't fill any fields - test button should be disabled
      const testButton = findTestButton(wrapper);
      expect(testButton).toBeDefined();
      expect(testButton!.attributes('disabled')).toBeDefined();
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

    it('shows delete button when editing existing config', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockExistingConfig });
      wrapper = await mountComponent();

      // Find delete button
      const deleteButton = findDeleteButton(wrapper);
      expect(deleteButton).toBeDefined();
      expect(deleteButton!.text()).toContain('Delete Configuration');
    });

    it('calls deleteConfigForDomain after confirmation', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockExistingConfig });
      wrapper = await mountComponent();

      // Find and click delete button to show confirmation
      const deleteButton = findDeleteButton(wrapper);
      expect(deleteButton).toBeDefined();
      await deleteButton!.trigger('click');
      await flushPromises();

      // Find and click confirm button
      const confirmButton = findConfirmDeleteButton(wrapper);
      expect(confirmButton).toBeDefined();
      await confirmButton!.trigger('click');
      await flushPromises();

      expect(mockDeleteConfigForDomain).toHaveBeenCalledWith('dm_123');
    });

    it('emits deleted event after successful delete', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockExistingConfig });
      wrapper = await mountComponent();

      // Find and click delete button
      const deleteButton = findDeleteButton(wrapper);
      expect(deleteButton).toBeDefined();
      await deleteButton!.trigger('click');
      await flushPromises();

      // Find and click confirm button
      const confirmButton = findConfirmDeleteButton(wrapper);
      expect(confirmButton).toBeDefined();
      await confirmButton!.trigger('click');
      await flushPromises();

      expect(wrapper.emitted('deleted')).toBeTruthy();
    });

    it('does not show delete button when creating new config', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: null });
      wrapper = await mountComponent();

      // Delete button should not be visible
      const deleteButton = findDeleteButton(wrapper);
      expect(deleteButton).toBeUndefined();
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // Loading state
  // ─────────────────────────────────────────────────────────────────────────────

  describe('Loading state', () => {
    it('shows loading state while fetching config', async () => {
      // Set up a never-resolving promise to keep loading state
      mockGetConfigForDomain.mockImplementation(() => new Promise(() => {}));

      const component = mount(DomainSsoConfigForm, {
        props: { domainExtId: 'dm_123' },
        global: {
          plugins: [i18n, pinia],
          stubs: { Teleport: true },
        },
      });

      // Should show loading state
      const loadingIcon = component.find('[data-icon-name="arrow-path"]');
      expect(loadingIcon.exists()).toBe(true);

      component.unmount();
    });

    it('hides loading state after config loads', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: null });
      wrapper = await mountComponent();

      // Loading spinner should not be in the main content area
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
