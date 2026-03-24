// src/tests/apps/workspace/components/organizations/SsoConfigForm.spec.ts
//
// Tests for SsoConfigForm.vue covering:
// 1. Form submission uses correct HTTP method based on client_secret presence
// 2. Form validation for required fields
// 3. Provider-specific field rendering (tenant_id for Entra ID, issuer for OIDC)

import { mount, VueWrapper, flushPromises } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createTestingPinia } from '@pinia/testing';
import { createI18n } from 'vue-i18n';
import SsoConfigForm from '@/apps/workspace/components/organizations/SsoConfigForm.vue';

// ─────────────────────────────────────────────────────────────────────────────
// Mocks
// ─────────────────────────────────────────────────────────────────────────────

// Mock OIcon component
vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="o-icon" />',
    props: ['collection', 'name', 'class'],
  },
}));

// Mock BasicFormAlerts component
vi.mock('@/shared/components/forms/BasicFormAlerts.vue', () => ({
  default: {
    name: 'BasicFormAlerts',
    template: '<div class="form-alerts" :data-error="error" :data-success="success" />',
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

// Mock SsoService with spies for PUT/PATCH behavior testing
const mockSaveConfig = vi.fn();
const mockGetConfig = vi.fn();
const mockDeleteConfig = vi.fn();
const mockTestConnection = vi.fn();

// Track which HTTP method was used
let lastSavePayload: unknown = null;

vi.mock('@/services/sso.service', () => ({
  SsoService: {
    getConfig: (...args: unknown[]) => mockGetConfig(...args),
    saveConfig: async (orgExtId: string, payload: unknown) => {
      lastSavePayload = payload;
      return mockSaveConfig(orgExtId, payload);
    },
    deleteConfig: (...args: unknown[]) => mockDeleteConfig(...args),
    testConnection: (...args: unknown[]) => mockTestConnection(...args),
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
            testing: 'Testing...',
            test_error: 'Connection test failed',
          },
        },
        COMMON: {
          loading: 'Loading...',
          show_password: 'Show password',
          hide_password: 'Hide password',
        },
      },
    },
  },
});

// ─────────────────────────────────────────────────────────────────────────────
// Test Fixtures
// ─────────────────────────────────────────────────────────────────────────────

const mockExistingConfig = {
  org_id: 'org_123',
  provider_type: 'entra_id' as const,
  enabled: true,
  display_name: 'Test SSO',
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

describe('SsoConfigForm', () => {
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
    mockGetConfig.mockResolvedValue({ record: null });
    mockSaveConfig.mockResolvedValue({ record: mockExistingConfig });
    mockDeleteConfig.mockResolvedValue({ success: true });
  });

  afterEach(() => {
    if (wrapper) {
      wrapper.unmount();
    }
  });

  const mountComponent = async (props: { orgExtId?: string } = {}) => {
    const component = mount(SsoConfigForm, {
      props: {
        orgExtId: props.orgExtId ?? 'org_123',
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
  // Form Submission: PUT vs PATCH based on client_secret
  // ─────────────────────────────────────────────────────────────────────────────

  describe('Form submission request type', () => {
    it('includes client_secret in payload when provided (triggers PUT)', async () => {
      // Mount with no existing config (new config mode)
      mockGetConfig.mockResolvedValue({ record: null });
      wrapper = await mountComponent();

      // Fill required fields (including tenant_id since default is entra_id)
      const displayNameInput = wrapper.find('#sso-display-name');
      const clientIdInput = wrapper.find('#sso-client-id');
      const clientSecretInput = wrapper.find('#sso-client-secret');
      const tenantIdInput = wrapper.find('#sso-tenant-id');

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
      expect(mockSaveConfig).toHaveBeenCalled();
      expect(lastSavePayload).toMatchObject({
        client_secret: 'secret-456',
      });
    });

    it('omits client_secret from payload when empty (triggers PATCH)', async () => {
      // Mount with existing config (edit mode)
      mockGetConfig.mockResolvedValue({ record: mockExistingConfig });
      wrapper = await mountComponent();

      // Form should be pre-populated, client_secret should be empty
      const displayNameInput = wrapper.find('#sso-display-name');
      expect((displayNameInput.element as HTMLInputElement).value).toBe('Test SSO');

      // Change display name but leave client_secret empty
      await displayNameInput.setValue('Updated SSO Name');
      await flushPromises();

      // Submit form
      const form = wrapper.find('form');
      await form.trigger('submit.prevent');
      await flushPromises();

      // Verify payload does NOT include client_secret
      expect(mockSaveConfig).toHaveBeenCalled();
      expect(lastSavePayload).not.toHaveProperty('client_secret');
    });

    it('includes client_secret when updating existing config with new secret', async () => {
      // Mount with existing config
      mockGetConfig.mockResolvedValue({ record: mockExistingConfig });
      wrapper = await mountComponent();

      // Enter new client secret
      const clientSecretInput = wrapper.find('#sso-client-secret');
      await clientSecretInput.setValue('new-secret-789');
      await flushPromises();

      // Submit form
      const form = wrapper.find('form');
      await form.trigger('submit.prevent');
      await flushPromises();

      // Verify payload includes the new client_secret
      expect(mockSaveConfig).toHaveBeenCalled();
      expect(lastSavePayload).toMatchObject({
        client_secret: 'new-secret-789',
      });
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // Form Validation
  // ─────────────────────────────────────────────────────────────────────────────

  describe('Form validation', () => {
    it('requires display_name for form to be valid', async () => {
      mockGetConfig.mockResolvedValue({ record: null });
      wrapper = await mountComponent();

      // Fill all fields except display_name
      const clientIdInput = wrapper.find('#sso-client-id');
      const clientSecretInput = wrapper.find('#sso-client-secret');

      await clientIdInput.setValue('client-123');
      await clientSecretInput.setValue('secret-456');
      await flushPromises();

      // Submit button should still be present but form invalid
      // The submit should not trigger save
      const form = wrapper.find('form');
      await form.trigger('submit.prevent');
      await flushPromises();

      // Save should NOT have been called (form validation failed)
      expect(mockSaveConfig).not.toHaveBeenCalled();
    });

    it('requires client_id for form to be valid', async () => {
      mockGetConfig.mockResolvedValue({ record: null });
      wrapper = await mountComponent();

      // Fill all fields except client_id
      const displayNameInput = wrapper.find('#sso-display-name');
      const clientSecretInput = wrapper.find('#sso-client-secret');

      await displayNameInput.setValue('Test SSO');
      await clientSecretInput.setValue('secret-456');
      await flushPromises();

      // Submit form
      const form = wrapper.find('form');
      await form.trigger('submit.prevent');
      await flushPromises();

      // Save should NOT have been called
      expect(mockSaveConfig).not.toHaveBeenCalled();
    });

    it('requires client_secret for new config (not editing)', async () => {
      mockGetConfig.mockResolvedValue({ record: null });
      wrapper = await mountComponent();

      // Fill all fields except client_secret
      const displayNameInput = wrapper.find('#sso-display-name');
      const clientIdInput = wrapper.find('#sso-client-id');

      await displayNameInput.setValue('Test SSO');
      await clientIdInput.setValue('client-123');
      // Intentionally leave client_secret empty
      await flushPromises();

      // Submit form
      const form = wrapper.find('form');
      await form.trigger('submit.prevent');
      await flushPromises();

      // Save should NOT have been called
      expect(mockSaveConfig).not.toHaveBeenCalled();
    });

    it('allows empty client_secret when editing existing config', async () => {
      mockGetConfig.mockResolvedValue({ record: mockExistingConfig });
      wrapper = await mountComponent();

      // Form should be pre-populated from existing config
      // client_secret is empty in form (never populated from response)
      // This should still be valid for editing

      // Submit form without changing client_secret
      const form = wrapper.find('form');
      await form.trigger('submit.prevent');
      await flushPromises();

      // Save SHOULD have been called
      expect(mockSaveConfig).toHaveBeenCalled();
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // Provider-specific field rendering
  // ─────────────────────────────────────────────────────────────────────────────

  describe('Provider-specific field rendering', () => {
    it('shows tenant_id field when Entra ID is selected', async () => {
      mockGetConfig.mockResolvedValue({ record: null });
      wrapper = await mountComponent();

      // Default provider is entra_id
      const tenantIdInput = wrapper.find('#sso-tenant-id');
      expect(tenantIdInput.exists()).toBe(true);
    });

    it('hides tenant_id field when Google is selected', async () => {
      mockGetConfig.mockResolvedValue({ record: null });
      wrapper = await mountComponent();

      // Select Google provider
      const googleRadio = wrapper.find('#provider-google');
      await googleRadio.setValue(true);
      await flushPromises();

      // Tenant ID should not be visible
      const tenantIdInput = wrapper.find('#sso-tenant-id');
      expect(tenantIdInput.exists()).toBe(false);
    });

    it('shows issuer field when OIDC is selected', async () => {
      mockGetConfig.mockResolvedValue({ record: null });
      wrapper = await mountComponent();

      // Select OIDC provider
      const oidcRadio = wrapper.find('#provider-oidc');
      await oidcRadio.setValue(true);
      await flushPromises();

      // Issuer should be visible
      const issuerInput = wrapper.find('#sso-issuer');
      expect(issuerInput.exists()).toBe(true);
    });

    it('hides issuer field when Entra ID is selected', async () => {
      mockGetConfig.mockResolvedValue({ record: null });
      wrapper = await mountComponent();

      // Default is entra_id - issuer should not be visible
      const issuerInput = wrapper.find('#sso-issuer');
      expect(issuerInput.exists()).toBe(false);
    });

    it('hides both tenant_id and issuer for GitHub provider', async () => {
      mockGetConfig.mockResolvedValue({ record: null });
      wrapper = await mountComponent();

      // Select GitHub provider
      const githubRadio = wrapper.find('#provider-github');
      await githubRadio.setValue(true);
      await flushPromises();

      // Neither tenant_id nor issuer should be visible
      const tenantIdInput = wrapper.find('#sso-tenant-id');
      const issuerInput = wrapper.find('#sso-issuer');

      expect(tenantIdInput.exists()).toBe(false);
      expect(issuerInput.exists()).toBe(false);
    });

    it('requires tenant_id when Entra ID is selected for valid form', async () => {
      mockGetConfig.mockResolvedValue({ record: null });
      wrapper = await mountComponent();

      // Fill base fields but not tenant_id
      const displayNameInput = wrapper.find('#sso-display-name');
      const clientIdInput = wrapper.find('#sso-client-id');
      const clientSecretInput = wrapper.find('#sso-client-secret');

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
      expect(mockSaveConfig).not.toHaveBeenCalled();
    });

    it('requires issuer when OIDC is selected for valid form', async () => {
      mockGetConfig.mockResolvedValue({ record: null });
      wrapper = await mountComponent();

      // Select OIDC provider
      const oidcRadio = wrapper.find('#provider-oidc');
      await oidcRadio.setValue(true);
      await flushPromises();

      // Fill base fields but not issuer
      const displayNameInput = wrapper.find('#sso-display-name');
      const clientIdInput = wrapper.find('#sso-client-id');
      const clientSecretInput = wrapper.find('#sso-client-secret');

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
      expect(mockSaveConfig).not.toHaveBeenCalled();
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // Provider-specific payload fields
  // ─────────────────────────────────────────────────────────────────────────────

  describe('Provider-specific payload construction', () => {
    it('includes tenant_id in payload for Entra ID provider', async () => {
      mockGetConfig.mockResolvedValue({ record: null });
      wrapper = await mountComponent();

      // Fill all required fields including tenant_id
      const displayNameInput = wrapper.find('#sso-display-name');
      const clientIdInput = wrapper.find('#sso-client-id');
      const clientSecretInput = wrapper.find('#sso-client-secret');
      const tenantIdInput = wrapper.find('#sso-tenant-id');

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
      expect(mockSaveConfig).toHaveBeenCalled();
      expect(lastSavePayload).toMatchObject({
        provider_type: 'entra_id',
        tenant_id: 'tenant-uuid',
      });
    });

    it('includes issuer in payload for OIDC provider', async () => {
      mockGetConfig.mockResolvedValue({ record: null });
      wrapper = await mountComponent();

      // Select OIDC provider
      const oidcRadio = wrapper.find('#provider-oidc');
      await oidcRadio.setValue(true);
      await flushPromises();

      // Fill all required fields including issuer
      const displayNameInput = wrapper.find('#sso-display-name');
      const clientIdInput = wrapper.find('#sso-client-id');
      const clientSecretInput = wrapper.find('#sso-client-secret');
      const issuerInput = wrapper.find('#sso-issuer');

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
      expect(mockSaveConfig).toHaveBeenCalled();
      expect(lastSavePayload).toMatchObject({
        provider_type: 'oidc',
        issuer: 'https://issuer.example.com',
      });
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // Loading and error states
  // ─────────────────────────────────────────────────────────────────────────────

  describe('Loading and error states', () => {
    it('shows loading state while fetching config', async () => {
      // Set up a never-resolving promise to keep loading state
      mockGetConfig.mockImplementation(() => new Promise(() => {}));

      const component = mount(SsoConfigForm, {
        props: { orgExtId: 'org_123' },
        global: {
          plugins: [i18n, pinia],
          stubs: { Teleport: true },
        },
      });

      // Should show loading state (sr-only text)
      const loadingText = component.find('.sr-only');
      expect(loadingText.exists()).toBe(true);
      expect(loadingText.text()).toContain('Loading');

      component.unmount();
    });

    it('emits saved event after successful save', async () => {
      mockGetConfig.mockResolvedValue({ record: mockExistingConfig });
      wrapper = await mountComponent();

      // Update a field
      const displayNameInput = wrapper.find('#sso-display-name');
      await displayNameInput.setValue('Updated SSO');
      await flushPromises();

      // Submit form
      const form = wrapper.find('form');
      await form.trigger('submit.prevent');
      await flushPromises();

      // Check emitted events
      expect(wrapper.emitted('saved')).toBeTruthy();
    });
  });
});
