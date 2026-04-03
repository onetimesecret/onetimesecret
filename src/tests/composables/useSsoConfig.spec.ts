// src/tests/composables/useSsoConfig.spec.ts
//
// Tests for useSsoConfig composable covering:
// 1. initialize(): returns null config on 404, populates formState from config
// 2. saveConfig(): builds payload without client_secret if not entered
// 3. deleteConfig(): resets to default state
// 4. hasUnsavedChanges: detects field modifications
// 5. discardChanges(): restores saved state
// 6. testConnection(): validates IdP connectivity
// 7. client_secret NEVER populated from API response (masked value gotcha)

import { useSsoConfig } from '@/shared/composables/useSsoConfig';
import { createPinia, setActivePinia } from 'pinia';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import type { CustomDomainSsoConfig } from '@/schemas/shapes/sso-config';
import type { TestSsoConnectionResponse } from '@/services/sso.service';

// -----------------------------------------------------------------------------
// Mock Setup
// -----------------------------------------------------------------------------

const mockGetConfigForDomain = vi.fn();
const mockSaveConfigForDomain = vi.fn();
const mockDeleteConfigForDomain = vi.fn();
const mockTestConnectionForDomain = vi.fn();
const mockNotificationsShow = vi.fn();
const mockRouterPush = vi.fn();

vi.mock('@/services/sso.service', () => ({
  SsoService: {
    getConfigForDomain: (...args: unknown[]) => mockGetConfigForDomain(...args),
    saveConfigForDomain: (...args: unknown[]) => mockSaveConfigForDomain(...args),
    deleteConfigForDomain: (...args: unknown[]) => mockDeleteConfigForDomain(...args),
    testConnectionForDomain: (...args: unknown[]) => mockTestConnectionForDomain(...args),
  },
}));

vi.mock('@/shared/stores', () => ({
  useNotificationsStore: () => ({
    show: mockNotificationsShow,
  }),
}));

vi.mock('vue-router', () => ({
  useRouter: () => ({
    push: mockRouterPush,
  }),
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key: string) => {
      const translations: Record<string, string> = {
        'web.domains.sso.update_success': 'SSO configuration updated',
        'web.domains.sso.delete_success': 'SSO configuration removed',
        'web.domains.sso.test_success': 'Connection test successful',
        'web.domains.sso.test_failed': 'Connection test failed',
        'web.COMMON.unexpected_error': 'An unexpected error occurred',
      };
      return translations[key] ?? key;
    },
  }),
}));

vi.mock('@/shared/composables/useAsyncHandler', () => ({
  useAsyncHandler: () => ({
    wrap: vi.fn(async (fn: () => Promise<unknown>) => {
      try {
        return await fn();
      } catch {
        return undefined;
      }
    }),
  }),
  createError: vi.fn(),
}));

// -----------------------------------------------------------------------------
// Test Fixtures
// -----------------------------------------------------------------------------

const mockSsoConfigData: CustomDomainSsoConfig = {
  domain_id: 'domain-123',
  provider_type: 'entra_id',
  enabled: true,
  display_name: 'Acme Corp SSO',
  client_id: 'client-id-12345',
  client_secret_masked: '****5678',
  tenant_id: 'tenant-id-abcdef',
  issuer: null,
  allowed_domains: ['acme.com', 'acme.org'],
  requires_domain_filter: false,
  idp_controls_access: true,
  created_at: new Date('2025-01-01T00:00:00Z'),
  updated_at: new Date('2025-01-15T10:00:00Z'),
};

const mockOidcConfigData: CustomDomainSsoConfig = {
  ...mockSsoConfigData,
  provider_type: 'oidc',
  tenant_id: null,
  issuer: 'https://idp.example.com',
  requires_domain_filter: true,
  idp_controls_access: false,
};

const mockDisabledConfig: CustomDomainSsoConfig = {
  ...mockSsoConfigData,
  enabled: false,
};

const mockTestSuccessResponse: TestSsoConnectionResponse = {
  user_id: 'user-123',
  success: true,
  provider_type: 'entra_id',
  message: 'Successfully connected to identity provider',
  details: {
    issuer: 'https://login.microsoftonline.com/tenant-id/v2.0',
    authorization_endpoint: 'https://login.microsoftonline.com/tenant-id/oauth2/v2.0/authorize',
    token_endpoint: 'https://login.microsoftonline.com/tenant-id/oauth2/v2.0/token',
  },
};

const mockTestFailureResponse: TestSsoConnectionResponse = {
  user_id: 'user-123',
  success: false,
  provider_type: 'entra_id',
  message: 'Failed to connect to identity provider',
  details: {
    error_code: 'invalid_client',
    description: 'Invalid client credentials',
  },
};

// -----------------------------------------------------------------------------
// Tests
// -----------------------------------------------------------------------------

describe('useSsoConfig', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();

    // Default: no existing config (unconfigured)
    mockGetConfigForDomain.mockResolvedValue({ record: null });
    mockSaveConfigForDomain.mockResolvedValue({ record: mockSsoConfigData });
    mockDeleteConfigForDomain.mockResolvedValue({ success: true });
    mockTestConnectionForDomain.mockResolvedValue(mockTestSuccessResponse);
  });

  // ---------------------------------------------------------------------------
  // initialize
  // ---------------------------------------------------------------------------

  describe('initialize', () => {
    it('sets ssoConfig to null when domain is unconfigured (404)', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: null });

      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.ssoConfig.value).toBeNull();
      expect(composable.isConfigured.value).toBe(false);
      expect(composable.isInitialized.value).toBe(true);
    });

    it('populates formState from existing config', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSsoConfigData });

      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.ssoConfig.value).toEqual(mockSsoConfigData);
      expect(composable.formState.value).toEqual({
        provider_type: 'entra_id',
        display_name: 'Acme Corp SSO',
        client_id: 'client-id-12345',
        client_secret: '', // NEVER populated from API response
        tenant_id: 'tenant-id-abcdef',
        issuer: '',
        allowed_domains: ['acme.com', 'acme.org'],
        enabled: true,
      });
      expect(composable.isConfigured.value).toBe(true);
    });

    it('sets default formState when domain is unconfigured', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: null });

      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.formState.value).toEqual({
        provider_type: 'entra_id',
        display_name: '',
        client_id: '',
        client_secret: '',
        tenant_id: '',
        issuer: '',
        allowed_domains: [],
        enabled: false,
      });
    });

    it('snapshots savedFormState on load', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSsoConfigData });

      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      // hasUnsavedChanges should be false immediately after load
      expect(composable.hasUnsavedChanges.value).toBe(false);
    });

    it('sets isInitialized to true after load', async () => {
      const composable = useSsoConfig('dm-ext-123');
      expect(composable.isInitialized.value).toBe(false);

      await composable.initialize();

      expect(composable.isInitialized.value).toBe(true);
    });

    it('NEVER populates client_secret from API response (security)', async () => {
      // This is critical: the API returns client_secret_masked, not the actual secret
      // The form should NEVER pre-populate client_secret field
      mockGetConfigForDomain.mockResolvedValue({ record: mockSsoConfigData });

      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      // client_secret should always be empty string, even when config exists
      expect(composable.formState.value.client_secret).toBe('');
      // But the masked value should be available for display
      expect(composable.ssoConfig.value?.client_secret_masked).toBe('****5678');
    });

    it('handles null tenant_id by converting to empty string', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockOidcConfigData });

      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.formState.value.tenant_id).toBe('');
    });

    it('handles null issuer by converting to empty string', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSsoConfigData });

      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.formState.value.issuer).toBe('');
    });

    it('calls SsoService.getConfigForDomain with correct extid', async () => {
      const composable = useSsoConfig('dm-ext-456');
      await composable.initialize();

      expect(mockGetConfigForDomain).toHaveBeenCalledWith('dm-ext-456');
    });
  });

  // ---------------------------------------------------------------------------
  // saveConfig
  // ---------------------------------------------------------------------------

  describe('saveConfig', () => {
    it('builds correct payload without client_secret if not entered', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSsoConfigData });
      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      // Modify form but leave client_secret empty (preserve existing secret)
      composable.formState.value = {
        ...composable.formState.value,
        display_name: 'Updated SSO Config',
      };

      await composable.saveConfig();

      // Should call save without client_secret (PATCH semantics in service)
      expect(mockSaveConfigForDomain).toHaveBeenCalledWith(
        'dm-ext-123',
        expect.not.objectContaining({ client_secret: expect.any(String) })
      );
    });

    it('includes client_secret in payload when provided', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: null });
      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      composable.formState.value = {
        provider_type: 'entra_id',
        display_name: 'New SSO Config',
        client_id: 'new-client-id',
        client_secret: 'new-secret-value',
        tenant_id: 'new-tenant-id',
        issuer: '',
        allowed_domains: [],
        enabled: true,
      };

      await composable.saveConfig();

      expect(mockSaveConfigForDomain).toHaveBeenCalledWith(
        'dm-ext-123',
        expect.objectContaining({
          client_secret: 'new-secret-value',
        })
      );
    });

    it('updates ssoConfig after successful save', async () => {
      const updatedConfig: CustomDomainSsoConfig = {
        ...mockSsoConfigData,
        display_name: 'Updated Corp SSO',
      };
      mockGetConfigForDomain.mockResolvedValue({ record: null });
      mockSaveConfigForDomain.mockResolvedValue({ record: updatedConfig });

      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      composable.formState.value = {
        provider_type: 'entra_id',
        display_name: 'Updated Corp SSO',
        client_id: 'client-id-12345',
        client_secret: 'secret-value',
        tenant_id: 'tenant-id-abcdef',
        issuer: '',
        allowed_domains: [],
        enabled: true,
      };

      await composable.saveConfig();

      expect(composable.ssoConfig.value).toEqual(updatedConfig);
    });

    it('updates savedFormState snapshot after successful save', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: null });
      mockSaveConfigForDomain.mockResolvedValue({ record: mockSsoConfigData });

      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      composable.formState.value = {
        provider_type: 'entra_id',
        display_name: 'Test SSO',
        client_id: 'test-client-id',
        client_secret: 'test-secret',
        tenant_id: 'test-tenant',
        issuer: '',
        allowed_domains: [],
        enabled: true,
      };

      expect(composable.hasUnsavedChanges.value).toBe(true);

      await composable.saveConfig();

      expect(composable.hasUnsavedChanges.value).toBe(false);
    });

    it('trims whitespace from text fields', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: null });
      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      composable.formState.value = {
        provider_type: 'entra_id',
        display_name: '  Test SSO Config  ',
        client_id: '  client-id-with-spaces  ',
        client_secret: '  secret-value  ',
        tenant_id: '  tenant-id  ',
        issuer: '',
        allowed_domains: [],
        enabled: true,
      };

      await composable.saveConfig();

      expect(mockSaveConfigForDomain).toHaveBeenCalledWith(
        'dm-ext-123',
        expect.objectContaining({
          display_name: 'Test SSO Config',
          client_id: 'client-id-with-spaces',
          client_secret: 'secret-value',
          tenant_id: 'tenant-id',
        })
      );
    });

    it('handles save errors gracefully', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: null });
      mockSaveConfigForDomain.mockRejectedValue(new Error('Network error'));

      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      composable.formState.value = {
        provider_type: 'entra_id',
        display_name: 'Test',
        client_id: 'test-id',
        client_secret: 'test-secret',
        tenant_id: 'test-tenant',
        issuer: '',
        allowed_domains: [],
        enabled: true,
      };

      // Should not throw
      await composable.saveConfig();

      expect(composable.isSaving.value).toBe(false);
    });

    it('sets isSaving during operation', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: null });
      let resolveSave: (value: unknown) => void;
      mockSaveConfigForDomain.mockImplementation(
        () =>
          new Promise((resolve) => {
            resolveSave = resolve;
          })
      );

      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      composable.formState.value = {
        provider_type: 'entra_id',
        display_name: 'Test',
        client_id: 'test-id',
        client_secret: 'test-secret',
        tenant_id: 'test-tenant',
        issuer: '',
        allowed_domains: [],
        enabled: true,
      };

      const savePromise = composable.saveConfig();
      expect(composable.isSaving.value).toBe(true);

      resolveSave!({ record: mockSsoConfigData });
      await savePromise;

      expect(composable.isSaving.value).toBe(false);
    });

    it('shows success notification after save', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: null });
      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      composable.formState.value = {
        provider_type: 'entra_id',
        display_name: 'Test',
        client_id: 'test-id',
        client_secret: 'test-secret',
        tenant_id: 'test-tenant',
        issuer: '',
        allowed_domains: [],
        enabled: true,
      };

      await composable.saveConfig();

      expect(mockNotificationsShow).toHaveBeenCalledWith(
        'SSO configuration updated',
        'success',
        'top'
      );
    });
  });

  // ---------------------------------------------------------------------------
  // deleteConfig
  // ---------------------------------------------------------------------------

  describe('deleteConfig', () => {
    it('resets ssoConfig to null after deletion', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSsoConfigData });
      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.isConfigured.value).toBe(true);

      await composable.deleteConfig();

      expect(composable.ssoConfig.value).toBeNull();
      expect(composable.isConfigured.value).toBe(false);
    });

    it('resets formState to defaults after deletion', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSsoConfigData });
      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      await composable.deleteConfig();

      expect(composable.formState.value).toEqual({
        provider_type: 'entra_id',
        display_name: '',
        client_id: '',
        client_secret: '',
        tenant_id: '',
        issuer: '',
        allowed_domains: [],
        enabled: false,
      });
    });

    it('resets savedFormState so hasUnsavedChanges is false', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSsoConfigData });
      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      await composable.deleteConfig();

      expect(composable.hasUnsavedChanges.value).toBe(false);
    });

    it('calls SsoService.deleteConfigForDomain with correct extid', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSsoConfigData });
      const composable = useSsoConfig('dm-ext-456');
      await composable.initialize();

      await composable.deleteConfig();

      expect(mockDeleteConfigForDomain).toHaveBeenCalledWith('dm-ext-456');
    });

    it('shows success notification after deletion', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSsoConfigData });
      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      await composable.deleteConfig();

      expect(mockNotificationsShow).toHaveBeenCalledWith(
        'SSO configuration removed',
        'success',
        'top'
      );
    });

    it('sets isDeleting during operation', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSsoConfigData });
      let resolveDelete: (value: unknown) => void;
      mockDeleteConfigForDomain.mockImplementation(
        () =>
          new Promise((resolve) => {
            resolveDelete = resolve;
          })
      );

      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      const deletePromise = composable.deleteConfig();
      expect(composable.isDeleting.value).toBe(true);

      resolveDelete!({ success: true });
      await deletePromise;

      expect(composable.isDeleting.value).toBe(false);
    });
  });

  // ---------------------------------------------------------------------------
  // hasUnsavedChanges
  // ---------------------------------------------------------------------------

  describe('hasUnsavedChanges', () => {
    it('returns false immediately after initialization', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSsoConfigData });
      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.hasUnsavedChanges.value).toBe(false);
    });

    it('returns true when display_name is modified', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSsoConfigData });
      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      composable.formState.value = {
        ...composable.formState.value,
        display_name: 'Changed Name',
      };

      expect(composable.hasUnsavedChanges.value).toBe(true);
    });

    it('returns true when client_id is modified', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSsoConfigData });
      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      composable.formState.value = {
        ...composable.formState.value,
        client_id: 'new-client-id',
      };

      expect(composable.hasUnsavedChanges.value).toBe(true);
    });

    it('returns true when client_secret is entered (from empty)', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSsoConfigData });
      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      // client_secret starts empty (never populated from API)
      expect(composable.formState.value.client_secret).toBe('');

      composable.formState.value = {
        ...composable.formState.value,
        client_secret: 'new-secret',
      };

      expect(composable.hasUnsavedChanges.value).toBe(true);
    });

    it('returns true when enabled is toggled', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSsoConfigData });
      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      composable.formState.value = {
        ...composable.formState.value,
        enabled: false,
      };

      expect(composable.hasUnsavedChanges.value).toBe(true);
    });

    it('returns true when provider_type is changed', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSsoConfigData });
      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      composable.formState.value = {
        ...composable.formState.value,
        provider_type: 'oidc',
      };

      expect(composable.hasUnsavedChanges.value).toBe(true);
    });

    it('returns true when allowed_domains is modified', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSsoConfigData });
      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      composable.formState.value = {
        ...composable.formState.value,
        allowed_domains: ['newdomain.com'],
      };

      expect(composable.hasUnsavedChanges.value).toBe(true);
    });

    it('returns false when changes are reverted to original values', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSsoConfigData });
      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      const originalDisplayName = composable.formState.value.display_name;

      // Modify
      composable.formState.value = {
        ...composable.formState.value,
        display_name: 'Changed',
      };
      expect(composable.hasUnsavedChanges.value).toBe(true);

      // Revert
      composable.formState.value = {
        ...composable.formState.value,
        display_name: originalDisplayName,
      };
      expect(composable.hasUnsavedChanges.value).toBe(false);
    });

    it('returns false before initialization (no savedFormState)', () => {
      const composable = useSsoConfig('dm-ext-123');
      expect(composable.hasUnsavedChanges.value).toBe(false);
    });

    it('returns false after discardChanges', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSsoConfigData });
      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      composable.formState.value = {
        ...composable.formState.value,
        display_name: 'Changed',
      };
      expect(composable.hasUnsavedChanges.value).toBe(true);

      composable.discardChanges();

      expect(composable.hasUnsavedChanges.value).toBe(false);
    });
  });

  // ---------------------------------------------------------------------------
  // discardChanges
  // ---------------------------------------------------------------------------

  describe('discardChanges', () => {
    it('restores all fields from savedFormState', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSsoConfigData });
      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      const originalFormData = { ...composable.formState.value };

      // Modify multiple fields
      composable.formState.value = {
        provider_type: 'oidc',
        display_name: 'Changed Corp',
        client_id: 'changed-client-id',
        client_secret: 'new-secret',
        tenant_id: '',
        issuer: 'https://changed.example.com',
        allowed_domains: ['changed.com'],
        enabled: false,
      };

      expect(composable.hasUnsavedChanges.value).toBe(true);

      composable.discardChanges();

      expect(composable.formState.value).toEqual(originalFormData);
      expect(composable.hasUnsavedChanges.value).toBe(false);
    });

    it('is a no-op when savedFormState is null (before init)', () => {
      const composable = useSsoConfig('dm-ext-123');

      // Should not throw
      composable.discardChanges();

      // formState should remain at defaults
      expect(composable.formState.value).toEqual({
        provider_type: 'entra_id',
        display_name: '',
        client_id: '',
        client_secret: '',
        tenant_id: '',
        issuer: '',
        allowed_domains: [],
        enabled: false,
      });
    });
  });

  // ---------------------------------------------------------------------------
  // testConnection
  // ---------------------------------------------------------------------------

  describe('testConnection', () => {
    it('calls SsoService.testConnectionForDomain with correct payload', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSsoConfigData });
      const composable = useSsoConfig('dm-ext-789');
      await composable.initialize();

      await composable.testConnection();

      expect(mockTestConnectionForDomain).toHaveBeenCalledWith('dm-ext-789', {
        provider_type: 'entra_id',
        client_id: 'client-id-12345',
        tenant_id: 'tenant-id-abcdef',
      });
    });

    it('includes issuer for OIDC provider type', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockOidcConfigData });
      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      await composable.testConnection();

      expect(mockTestConnectionForDomain).toHaveBeenCalledWith('dm-ext-123', {
        provider_type: 'oidc',
        client_id: 'client-id-12345',
        issuer: 'https://idp.example.com',
      });
    });

    it('stores successful result in testResult', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSsoConfigData });
      mockTestConnectionForDomain.mockResolvedValue(mockTestSuccessResponse);

      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      await composable.testConnection();

      expect(composable.testResult.value).toEqual(mockTestSuccessResponse);
      expect(composable.testError.value).toBe('');
    });

    it('handles API rejection gracefully (error swallowed by wrap)', async () => {
      // Note: The useAsyncHandler mock catches exceptions and returns undefined.
      // This tests that the composable doesn't crash when wrap returns undefined.
      // For proper error handling tests, see the failure response test below.
      mockGetConfigForDomain.mockResolvedValue({ record: mockSsoConfigData });
      mockTestConnectionForDomain.mockRejectedValue(new Error('Connection timeout'));

      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      // Should not throw
      await composable.testConnection();

      // testResult should be null since wrap returned undefined
      expect(composable.testResult.value).toBeNull();
      // isTesting should be reset to false
      expect(composable.isTesting.value).toBe(false);
    });

    it('stores failure response in testResult when success is false', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSsoConfigData });
      mockTestConnectionForDomain.mockResolvedValue(mockTestFailureResponse);

      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      await composable.testConnection();

      expect(composable.testResult.value).toEqual(mockTestFailureResponse);
      expect(composable.testResult.value?.success).toBe(false);
    });

    it('sets isTesting during operation', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSsoConfigData });
      let resolveTest: (value: unknown) => void;
      mockTestConnectionForDomain.mockImplementation(
        () =>
          new Promise((resolve) => {
            resolveTest = resolve;
          })
      );

      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      const testPromise = composable.testConnection();
      expect(composable.isTesting.value).toBe(true);

      resolveTest!(mockTestSuccessResponse);
      await testPromise;

      expect(composable.isTesting.value).toBe(false);
    });

    it('resets isTesting even when test fails', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSsoConfigData });
      mockTestConnectionForDomain.mockRejectedValue(new Error('Network error'));

      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      await composable.testConnection();

      expect(composable.isTesting.value).toBe(false);
    });

    it('uses current form values for test (not saved config)', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSsoConfigData });
      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      // Modify form values
      composable.formState.value = {
        ...composable.formState.value,
        client_id: 'new-unsaved-client-id',
        tenant_id: 'new-unsaved-tenant-id',
      };

      await composable.testConnection();

      expect(mockTestConnectionForDomain).toHaveBeenCalledWith(
        'dm-ext-123',
        expect.objectContaining({
          client_id: 'new-unsaved-client-id',
          tenant_id: 'new-unsaved-tenant-id',
        })
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Initial state
  // ---------------------------------------------------------------------------

  describe('initial state', () => {
    it('starts with isLoading true', () => {
      const composable = useSsoConfig('dm-ext-123');
      expect(composable.isLoading.value).toBe(true);
    });

    it('starts with isInitialized false', () => {
      const composable = useSsoConfig('dm-ext-123');
      expect(composable.isInitialized.value).toBe(false);
    });

    it('starts with isSaving false', () => {
      const composable = useSsoConfig('dm-ext-123');
      expect(composable.isSaving.value).toBe(false);
    });

    it('starts with isDeleting false', () => {
      const composable = useSsoConfig('dm-ext-123');
      expect(composable.isDeleting.value).toBe(false);
    });

    it('starts with isTesting false', () => {
      const composable = useSsoConfig('dm-ext-123');
      expect(composable.isTesting.value).toBe(false);
    });

    it('starts with error null', () => {
      const composable = useSsoConfig('dm-ext-123');
      expect(composable.error.value).toBeNull();
    });

    it('starts with ssoConfig null', () => {
      const composable = useSsoConfig('dm-ext-123');
      expect(composable.ssoConfig.value).toBeNull();
    });

    it('starts with testResult null', () => {
      const composable = useSsoConfig('dm-ext-123');
      expect(composable.testResult.value).toBeNull();
    });

    it('starts with testError as empty string', () => {
      const composable = useSsoConfig('dm-ext-123');
      expect(composable.testError.value).toBe('');
    });
  });

  // ---------------------------------------------------------------------------
  // Computed properties
  // ---------------------------------------------------------------------------

  describe('computed properties', () => {
    it('isConfigured returns true when ssoConfig is not null', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSsoConfigData });
      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.isConfigured.value).toBe(true);
    });

    it('isConfigured returns false when ssoConfig is null', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: null });
      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.isConfigured.value).toBe(false);
    });

    it('isEnabled returns true when configured and enabled', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSsoConfigData });
      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.isEnabled.value).toBe(true);
    });

    it('isEnabled returns false when configured but disabled', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockDisabledConfig });
      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.isEnabled.value).toBe(false);
    });

    it('isEnabled returns false when not configured', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: null });
      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.isEnabled.value).toBe(false);
    });

    it('clientSecretMasked returns masked value from config', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSsoConfigData });
      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.clientSecretMasked.value).toBe('****5678');
    });

    it('clientSecretMasked returns null when not configured', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: null });
      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.clientSecretMasked.value).toBeNull();
    });
  });
});
