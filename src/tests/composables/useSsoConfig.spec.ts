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
// 8. runDiagnostics(): activation of a record that is off, and the stored
//    `enabled` the next save re-sends
// 9. saveAndRunDiagnostics(), refreshLastSignIn(), savedCredentialsUnchecked

import { createPinia, setActivePinia } from 'pinia';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { useSsoConfig } from '../../shared/composables/useSsoConfig';

import type { CustomDomainSsoConfig } from '../../schemas/shapes/domains/sso-config';
import type { SsoDiagnosticsResponse, TestSsoConnectionResponse } from '../../services/sso.service';

// -----------------------------------------------------------------------------
// Mock Setup
// -----------------------------------------------------------------------------

const mockGetConfigForDomain = vi.fn();
const mockSaveConfigForDomain = vi.fn();
const mockPatchConfigForDomain = vi.fn();
const mockDeleteConfigForDomain = vi.fn();
const mockTestConnectionForDomain = vi.fn();
const mockRunDiagnosticsForDomain = vi.fn();
const mockNotificationsShow = vi.fn();
const mockRouterPush = vi.fn();

vi.mock('@/services/sso.service', () => ({
  SsoService: {
    getConfigForDomain: (...args: unknown[]) => mockGetConfigForDomain(...args),
    saveConfigForDomain: (...args: unknown[]) => mockSaveConfigForDomain(...args),
    patchConfigForDomain: (...args: unknown[]) => mockPatchConfigForDomain(...args),
    deleteConfigForDomain: (...args: unknown[]) => mockDeleteConfigForDomain(...args),
    testConnectionForDomain: (...args: unknown[]) => mockTestConnectionForDomain(...args),
    runDiagnosticsForDomain: (...args: unknown[]) => mockRunDiagnosticsForDomain(...args),
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
        'web.domains.sso.diagnostics_passed': 'Saved configuration check passed',
        'web.domains.sso.diagnostics_failed': 'Saved configuration check found a problem',
        'web.domains.sso.diagnostics_inconclusive':
          'Saved configuration check could not reach a verdict',
        'web.domains.sso.diagnostics_error': 'Failed to check the saved configuration',
        'web.COMMON.unexpected_error': 'An unexpected error occurred',
      };
      return translations[key] ?? key;
    },
  }),
}));

// Swallows like the real handler and hands the rejection to onError as-is:
// tests that need a classified error reject with an ApplicationError-shaped
// object (see "429" below).
vi.mock('@/shared/composables/useAsyncHandler', () => ({
  useAsyncHandler: (options: {
    setLoading?: (loading: boolean) => void;
    onError?: (error: unknown) => void;
  }) => ({
    wrap: vi.fn(async (fn: () => Promise<unknown>) => {
      options.setLoading?.(true);
      try {
        return await fn();
      } catch (error) {
        options.onError?.(error);
        return undefined;
      } finally {
        options.setLoading?.(false);
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
  token_endpoint_auth_method: null,
  idp_sso_service_url: null,
  idp_entity_id: null,
  idp_cert: null,
  sp_entity_id: null,
  acs_url: null,
  unreadable_fields: [],
  allowed_domains: ['acme.com', 'acme.org'],
  requires_domain_filter: false,
  idp_controls_access: true,
  last_sign_in: null,
  enforce_sso_only: false,
  grant_org_scope: false,
  created_at: new Date('2025-01-01T00:00:00Z'),
  updated_at: new Date('2025-01-15T10:00:00Z'),
};

// SAML (#4450): no client credential; the IdP trio is plaintext on the wire.
const SAML_CERT = '-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----';

const mockSamlConfigData: CustomDomainSsoConfig = {
  ...mockSsoConfigData,
  provider_type: 'saml',
  client_id: '',
  client_secret_masked: null,
  tenant_id: null,
  idp_sso_service_url: 'https://idp.example.com/sso',
  idp_entity_id: 'https://idp.example.com/entity',
  idp_cert: SAML_CERT,
  sp_entity_id: 'https://secrets.example.com/auth/sso/saml/metadata',
  acs_url: 'https://secrets.example.com/auth/sso/saml/callback',
  requires_domain_filter: true,
  idp_controls_access: false,
  last_sign_in: null,
};

const mockOidcConfigData: CustomDomainSsoConfig = {
  ...mockSsoConfigData,
  provider_type: 'oidc',
  tenant_id: null,
  issuer: 'https://idp.example.com',
  requires_domain_filter: true,
  idp_controls_access: false,
  last_sign_in: null,
  enforce_sso_only: false,
};

const mockEnforceSsoOnlyConfig: CustomDomainSsoConfig = {
  ...mockSsoConfigData,
  enforce_sso_only: true,
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

const mockDiagnosticsPassed: SsoDiagnosticsResponse = {
  user_id: 'user-123',
  provider_type: 'entra_id',
  checked_at: '2026-10-12T10:00:00Z',
  // The loaded record's updated_at in whole seconds: the run is about it.
  configuration_revision: String(mockSsoConfigData.updated_at.getTime() / 1000),
  overall: 'passed',
  enabled: true,
  activation: 'not_requested',
  checks: [
    {
      check: 'stored_configuration',
      status: 'passed',
      message: 'The stored configuration is complete.',
      details: {},
    },
    {
      check: 'credential',
      status: 'passed',
      message: 'The identity provider accepted the saved client secret.',
      details: { note: 'This does not test a full sign-in.' },
    },
  ],
};

const mockDiagnosticsFailed: SsoDiagnosticsResponse = {
  ...mockDiagnosticsPassed,
  overall: 'failed',
  checks: [
    mockDiagnosticsPassed.checks[0],
    {
      check: 'credential',
      status: 'failed',
      message: 'The identity provider rejected the saved client secret.',
      details: { error_code: 'invalid_client_secret', http_status: 401 },
    },
  ],
};

const mockDiagnosticsInconclusive: SsoDiagnosticsResponse = {
  ...mockDiagnosticsPassed,
  overall: 'inconclusive',
  checks: [
    mockDiagnosticsPassed.checks[0],
    {
      check: 'credential',
      status: 'inconclusive',
      message: 'The identity provider could not be reached.',
      details: { error_code: 'timeout' },
    },
  ],
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
    mockRunDiagnosticsForDomain.mockResolvedValue(mockDiagnosticsPassed);
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
        token_endpoint_auth_method: '',
        idp_sso_service_url: '',
        idp_entity_id: '',
        idp_cert: '',
        allowed_domains: ['acme.com', 'acme.org'],
        enabled: true,
        enforce_sso_only: false,
        grant_org_scope: false,
      });
      expect(composable.isConfigured.value).toBe(true);
    });

    it('maps enforce_sso_only from config to formState', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockEnforceSsoOnlyConfig });

      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.formState.value.enforce_sso_only).toBe(true);
    });

    it('maps enforce_sso_only: false from config to formState', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSsoConfigData });

      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.formState.value.enforce_sso_only).toBe(false);
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
        token_endpoint_auth_method: '',
        idp_sso_service_url: '',
        idp_entity_id: '',
        idp_cert: '',
        allowed_domains: [],
        enabled: false,
        enforce_sso_only: false,
        grant_org_scope: false,
      });
    });

    it('sets default formState with enforce_sso_only: false', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: null });

      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.formState.value.enforce_sso_only).toBe(false);
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
    it('does not save a dirty SAML configuration while deletion is pending', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSamlConfigData });
      let resolveDelete!: (value: unknown) => void;
      mockDeleteConfigForDomain.mockReturnValue(
        new Promise((resolve) => {
          resolveDelete = resolve;
        })
      );
      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();
      composable.formState.value.display_name = 'Edited SAML';

      const pendingDelete = composable.deleteConfig();
      expect(composable.isDeleting.value).toBe(true);
      await composable.saveConfig();
      expect(mockSaveConfigForDomain).not.toHaveBeenCalled();
      expect(composable.isSaving.value).toBe(false);

      resolveDelete({ success: true });
      await pendingDelete;
      expect(composable.ssoConfig.value).toBeNull();
    });

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
        token_endpoint_auth_method: '',
        idp_sso_service_url: '',
        idp_entity_id: '',
        idp_cert: '',
        allowed_domains: [],
        enabled: true,
        enforce_sso_only: false,
        grant_org_scope: false,
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
        token_endpoint_auth_method: '',
        idp_sso_service_url: '',
        idp_entity_id: '',
        idp_cert: '',
        allowed_domains: [],
        enabled: true,
        enforce_sso_only: false,
        grant_org_scope: false,
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
        token_endpoint_auth_method: '',
        idp_sso_service_url: '',
        idp_entity_id: '',
        idp_cert: '',
        allowed_domains: [],
        enabled: true,
        enforce_sso_only: false,
        grant_org_scope: false,
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
        token_endpoint_auth_method: '',
        idp_sso_service_url: '',
        idp_entity_id: '',
        idp_cert: '',
        allowed_domains: [],
        enabled: true,
        enforce_sso_only: false,
        grant_org_scope: false,
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
        token_endpoint_auth_method: '',
        idp_sso_service_url: '',
        idp_entity_id: '',
        idp_cert: '',
        allowed_domains: [],
        enabled: true,
        enforce_sso_only: false,
        grant_org_scope: false,
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
        token_endpoint_auth_method: '',
        idp_sso_service_url: '',
        idp_entity_id: '',
        idp_cert: '',
        allowed_domains: [],
        enabled: true,
        enforce_sso_only: false,
        grant_org_scope: false,
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
        token_endpoint_auth_method: '',
        idp_sso_service_url: '',
        idp_entity_id: '',
        idp_cert: '',
        allowed_domains: [],
        enabled: true,
        enforce_sso_only: false,
        grant_org_scope: false,
      };

      await composable.saveConfig();

      expect(mockNotificationsShow).toHaveBeenCalledWith(
        'SSO configuration updated',
        'success',
        'top'
      );
    });

    it('includes enforce_sso_only in save payload when true', async () => {
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
        token_endpoint_auth_method: '',
        idp_sso_service_url: '',
        idp_entity_id: '',
        idp_cert: '',
        allowed_domains: [],
        enabled: true,
        enforce_sso_only: true,
        grant_org_scope: false,
      };

      await composable.saveConfig();

      expect(mockSaveConfigForDomain).toHaveBeenCalledWith(
        'dm-ext-123',
        expect.objectContaining({
          enforce_sso_only: true,
        })
      );
    });

    it('includes enforce_sso_only in save payload when false', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockEnforceSsoOnlyConfig });
      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      // Change from true to false
      composable.formState.value = {
        ...composable.formState.value,
        enforce_sso_only: false,
      };

      await composable.saveConfig();

      expect(mockSaveConfigForDomain).toHaveBeenCalledWith(
        'dm-ext-123',
        expect.objectContaining({
          enforce_sso_only: false,
        })
      );
    });

    // The dialog has no control for `enabled`: a save re-sends the stored
    // record's value (false for a new record) and never a form value, so it
    // can neither switch the connection on nor turn an active one off. PUT
    // (a new secret) defaults an absent `enabled` to false, so it is sent.
    it('creates a new record off, whatever formState.enabled holds', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: null });
      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      composable.formState.value = {
        ...composable.formState.value,
        display_name: 'New SSO',
        client_id: 'client-id',
        client_secret: 'secret-value',
        tenant_id: 'tenant-id',
        enabled: true,
      };

      expect(await composable.saveConfig()).toBe(true);

      expect(mockSaveConfigForDomain).toHaveBeenCalledWith(
        'dm-ext-123',
        expect.objectContaining({ enabled: false })
      );
    });

    it.each([
      ['on', mockSsoConfigData, true],
      ['off', mockDisabledConfig, false],
    ] as const)(
      're-sends the stored enabled of a record that is %s, whatever the form holds',
      async (_state, record, enabled) => {
        mockGetConfigForDomain.mockResolvedValue({ record });
        const composable = useSsoConfig('dm-ext-123');
        await composable.initialize();

        composable.formState.value = {
          ...composable.formState.value,
          client_secret: 'rotated-secret',
          enabled: !enabled,
        };
        await composable.saveConfig();

        // The literal false must ride along too: PUT defaults an absent one to false.
        expect(mockSaveConfigForDomain).toHaveBeenCalledWith(
          'dm-ext-123',
          expect.objectContaining({ enabled, client_secret: 'rotated-secret' })
        );
      }
    );

    it('returns false when the save fails or is refused', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSsoConfigData });
      mockSaveConfigForDomain.mockRejectedValueOnce(new Error('Failed'));
      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      expect(await composable.saveConfig()).toBe(false);
    });
  });

  // ---------------------------------------------------------------------------
  // SAML (#4450)
  // ---------------------------------------------------------------------------

  describe('SAML provider (#4450)', () => {
    it('seeds the IdP trio from the record (plaintext on the wire, not write-only)', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSamlConfigData });
      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.formState.value).toMatchObject({
        provider_type: 'saml',
        idp_sso_service_url: 'https://idp.example.com/sso',
        idp_entity_id: 'https://idp.example.com/entity',
        idp_cert: SAML_CERT,
        client_id: '',
        client_secret: '',
      });
      expect(composable.hasUnsavedChanges.value).toBe(false);
    });

    it('seeds an unreadable trio field EMPTY and exposes it via unreadableFields', async () => {
      mockGetConfigForDomain.mockResolvedValue({
        record: { ...mockSamlConfigData, idp_cert: null, unreadable_fields: ['idp_cert'] },
      });
      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.formState.value.idp_cert).toBe('');
      expect(composable.unreadableFields.value).toEqual(['idp_cert']);
    });

    it('unreadableFields is empty for a healthy record and when unconfigured', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSamlConfigData });
      const configured = useSsoConfig('dm-ext-123');
      await configured.initialize();
      expect(configured.unreadableFields.value).toEqual([]);

      mockGetConfigForDomain.mockResolvedValue({ record: null });
      const unconfigured = useSsoConfig('dm-ext-456');
      await unconfigured.initialize();
      expect(unconfigured.unreadableFields.value).toEqual([]);
    });

    it('save sends the trimmed trio and NO client credential fields', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: null });
      mockSaveConfigForDomain.mockResolvedValue({ record: mockSamlConfigData });
      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      composable.formState.value = {
        ...composable.formState.value,
        provider_type: 'saml',
        display_name: 'Acme SAML',
        // Stale values from a provider switch must not travel with a saml save.
        client_id: 'stale-client-id',
        client_secret: 'stale-secret',
        tenant_id: 'stale-tenant',
        issuer: 'https://stale.example.com',
        idp_sso_service_url: '  https://idp.example.com/sso  ',
        idp_entity_id: '  https://idp.example.com/entity  ',
        idp_cert: `  ${SAML_CERT}  `,
      };

      await composable.saveConfig();

      expect(mockSaveConfigForDomain).toHaveBeenCalledTimes(1);
      const [, payload] = mockSaveConfigForDomain.mock.calls[0] as [
        string,
        Record<string, unknown>,
      ];
      expect(payload).toMatchObject({
        provider_type: 'saml',
        display_name: 'Acme SAML',
        idp_sso_service_url: 'https://idp.example.com/sso',
        idp_entity_id: 'https://idp.example.com/entity',
        idp_cert: SAML_CERT,
      });
      expect(payload).not.toHaveProperty('client_secret');
      expect(payload.client_id).toBeUndefined();
      expect(payload.tenant_id).toBeUndefined();
      expect(payload.issuer).toBeUndefined();
    });

    it('leaves API-managed NameID and callback-origin policies untouched on form save', async () => {
      const record = {
        ...mockSamlConfigData,
        name_id_format: 'omit',
        callback_origins: ['https://login.corp.example'],
      };
      mockGetConfigForDomain.mockResolvedValue({ record });
      mockSaveConfigForDomain.mockResolvedValue({ record });
      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();
      composable.formState.value.display_name = 'Renamed SAML';

      await composable.saveConfig();

      expect(mockSaveConfigForDomain).toHaveBeenCalledTimes(1);
      const [, payload] = mockSaveConfigForDomain.mock.calls[0];
      // The service selects PATCH when no client_secret is submitted.
      expect(payload).not.toHaveProperty('client_secret');
      expect(payload).not.toHaveProperty('name_id_format');
      expect(payload).not.toHaveProperty('callback_origins');
      expect(composable.ssoConfig.value?.name_id_format).toBe('omit');
      expect(composable.ssoConfig.value?.callback_origins).toEqual(record.callback_origins);
    });

    it('save omits a blank trio field (PATCH preserves the stored value) rather than sending ""', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSamlConfigData });
      mockSaveConfigForDomain.mockResolvedValue({ record: mockSamlConfigData });
      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      composable.formState.value = { ...composable.formState.value, idp_cert: '   ' };

      await composable.saveConfig();

      const [, payload] = mockSaveConfigForDomain.mock.calls[0] as [
        string,
        Record<string, unknown>,
      ];
      expect(payload.idp_cert).toBeUndefined();
      expect(payload).toMatchObject({ idp_entity_id: 'https://idp.example.com/entity' });
    });

    it('a non-saml save sends NO trio fields', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSamlConfigData });
      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      // Switching away from saml: the trio still sits in form state.
      composable.formState.value = {
        ...composable.formState.value,
        provider_type: 'oidc',
        client_id: 'new-client',
        issuer: 'https://idp.example.com',
      };

      await composable.saveConfig();

      const [, payload] = mockSaveConfigForDomain.mock.calls[0] as [
        string,
        Record<string, unknown>,
      ];
      expect(payload).toMatchObject({ provider_type: 'oidc', client_id: 'new-client' });
      expect(payload.idp_sso_service_url).toBeUndefined();
      expect(payload.idp_entity_id).toBeUndefined();
      expect(payload.idp_cert).toBeUndefined();
    });

    it('testConnection sends the trio and no client_id for saml', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSamlConfigData });
      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      await composable.testConnection();

      const [extid, payload] = mockTestConnectionForDomain.mock.calls[0] as [
        string,
        Record<string, unknown>,
      ];
      expect(extid).toBe('dm-ext-123');
      expect(payload).toMatchObject({
        provider_type: 'saml',
        idp_sso_service_url: 'https://idp.example.com/sso',
        idp_entity_id: 'https://idp.example.com/entity',
        idp_cert: SAML_CERT,
      });
      expect(payload.client_id).toBeUndefined();
    });

    it.each(['idp_sso_service_url', 'idp_entity_id', 'idp_cert'] as const)(
      'hasUnsavedChanges tracks %s',
      async (field) => {
        mockGetConfigForDomain.mockResolvedValue({ record: mockSamlConfigData });
        const composable = useSsoConfig('dm-ext-123');
        await composable.initialize();
        expect(composable.hasUnsavedChanges.value).toBe(false);

        composable.formState.value = { ...composable.formState.value, [field]: 'changed' };
        expect(composable.hasUnsavedChanges.value).toBe(true);

        composable.discardChanges();
        expect(composable.hasUnsavedChanges.value).toBe(false);
      }
    );
  });

  // ---------------------------------------------------------------------------
  // deleteConfig
  // ---------------------------------------------------------------------------

  // ---------------------------------------------------------------------------
  // token_endpoint_auth_method (#4764)
  // ---------------------------------------------------------------------------

  describe('token_endpoint_auth_method (#4764)', () => {
    const savedPayload = (): Record<string, unknown> => {
      expect(mockSaveConfigForDomain).toHaveBeenCalledTimes(1);
      const [, payload] = mockSaveConfigForDomain.mock.calls[0] as [
        string,
        Record<string, unknown>,
      ];
      return payload;
    };

    it("defaults to '' (Automatic) on a fresh form", async () => {
      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.formState.value.token_endpoint_auth_method).toBe('');
    });

    it("seeds the stored method from the record and maps null to ''", async () => {
      mockGetConfigForDomain.mockResolvedValue({
        record: { ...mockOidcConfigData, token_endpoint_auth_method: 'client_secret_post' },
      });
      const stored = useSsoConfig('dm-ext-123');
      await stored.initialize();
      expect(stored.formState.value.token_endpoint_auth_method).toBe('client_secret_post');
      expect(stored.hasUnsavedChanges.value).toBe(false);

      mockGetConfigForDomain.mockResolvedValue({ record: mockOidcConfigData });
      const unset = useSsoConfig('dm-ext-456');
      await unset.initialize();
      expect(unset.formState.value.token_endpoint_auth_method).toBe('');
    });

    it("sends the key with '' for Automatic on an oidc save (a present blank CLEARS on PATCH)", async () => {
      mockGetConfigForDomain.mockResolvedValue({
        record: { ...mockOidcConfigData, token_endpoint_auth_method: 'client_secret_post' },
      });
      mockSaveConfigForDomain.mockResolvedValue({ record: mockOidcConfigData });
      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      composable.formState.value = {
        ...composable.formState.value,
        token_endpoint_auth_method: '',
      };
      expect(composable.hasUnsavedChanges.value).toBe(true);

      await composable.saveConfig();

      const payload = savedPayload();
      expect(payload).toHaveProperty('token_endpoint_auth_method', '');
    });

    it('sends the selected method on an oidc save', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockOidcConfigData });
      mockSaveConfigForDomain.mockResolvedValue({
        record: { ...mockOidcConfigData, token_endpoint_auth_method: 'client_secret_post' },
      });
      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      composable.formState.value = {
        ...composable.formState.value,
        token_endpoint_auth_method: 'client_secret_post',
      };

      await composable.saveConfig();

      expect(savedPayload()).toMatchObject({ token_endpoint_auth_method: 'client_secret_post' });
      expect(composable.formState.value.token_endpoint_auth_method).toBe('client_secret_post');
      expect(composable.hasUnsavedChanges.value).toBe(false);
    });

    it.each(['entra_id', 'saml'] as const)(
      'does not send the key for %s, even with a stale value on the form',
      async (providerType) => {
        mockGetConfigForDomain.mockResolvedValue({ record: null });
        const composable = useSsoConfig('dm-ext-123');
        await composable.initialize();

        composable.formState.value = {
          ...composable.formState.value,
          provider_type: providerType,
          display_name: 'Stale',
          client_id: 'client-123',
          client_secret: 'secret-456',
          tenant_id: 'tenant-789',
          idp_sso_service_url: 'https://idp.example.com/sso',
          idp_entity_id: 'https://idp.example.com/entity',
          idp_cert: SAML_CERT,
          // A value left over from an oidc selection before the switch.
          token_endpoint_auth_method: 'client_secret_post',
        };

        await composable.saveConfig();
        expect(savedPayload()).not.toHaveProperty('token_endpoint_auth_method');

        await composable.testConnection();
        const [, testPayload] = mockTestConnectionForDomain.mock.calls[0] as [
          string,
          Record<string, unknown>,
        ];
        expect(testPayload).not.toHaveProperty('token_endpoint_auth_method');
      }
    );

    it('sends the selected method with the oidc test payload', async () => {
      mockGetConfigForDomain.mockResolvedValue({
        record: { ...mockOidcConfigData, token_endpoint_auth_method: 'client_secret_post' },
      });
      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      await composable.testConnection();

      expect(mockTestConnectionForDomain).toHaveBeenCalledWith('dm-ext-123', {
        provider_type: 'oidc',
        client_id: 'client-id-12345',
        issuer: 'https://idp.example.com',
        token_endpoint_auth_method: 'client_secret_post',
      });
    });
  });

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
        token_endpoint_auth_method: '',
        idp_sso_service_url: '',
        idp_entity_id: '',
        idp_cert: '',
        allowed_domains: [],
        enabled: false,
        enforce_sso_only: false,
        grant_org_scope: false,
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

    it('returns true when enforce_sso_only is toggled on', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSsoConfigData });
      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      // Initially false per fixture
      expect(composable.formState.value.enforce_sso_only).toBe(false);

      composable.formState.value = {
        ...composable.formState.value,
        enforce_sso_only: true,
      };

      expect(composable.hasUnsavedChanges.value).toBe(true);
    });

    it('returns true when enforce_sso_only is toggled off', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockEnforceSsoOnlyConfig });
      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      // Initially true per fixture
      expect(composable.formState.value.enforce_sso_only).toBe(true);

      composable.formState.value = {
        ...composable.formState.value,
        enforce_sso_only: false,
      };

      expect(composable.hasUnsavedChanges.value).toBe(true);
    });

    it('returns false when enforce_sso_only is unchanged', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockEnforceSsoOnlyConfig });
      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      // Set to same value
      composable.formState.value = {
        ...composable.formState.value,
        enforce_sso_only: true,
      };

      expect(composable.hasUnsavedChanges.value).toBe(false);
    });

    it('returns false when allowed_domains has same items in different order', async () => {
      mockGetConfigForDomain.mockResolvedValue({
        record: { ...mockSsoConfigData, allowed_domains: ['acme.com', 'acme.org'] },
      });
      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      // Reorder without changing content (simulates remove + re-add)
      composable.formState.value = {
        ...composable.formState.value,
        allowed_domains: ['acme.org', 'acme.com'],
      };

      expect(composable.hasUnsavedChanges.value).toBe(false);
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
        token_endpoint_auth_method: '',
        idp_sso_service_url: '',
        idp_entity_id: '',
        idp_cert: '',
        allowed_domains: ['changed.com'],
        enabled: false,
        enforce_sso_only: false,
        grant_org_scope: false,
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
        token_endpoint_auth_method: '',
        idp_sso_service_url: '',
        idp_entity_id: '',
        idp_cert: '',
        allowed_domains: [],
        enabled: false,
        enforce_sso_only: false,
        grant_org_scope: false,
      });
    });

    it('restores enforce_sso_only from savedFormState', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockEnforceSsoOnlyConfig });
      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      // Modify enforce_sso_only
      composable.formState.value = {
        ...composable.formState.value,
        enforce_sso_only: false,
      };
      expect(composable.hasUnsavedChanges.value).toBe(true);

      composable.discardChanges();

      expect(composable.formState.value.enforce_sso_only).toBe(true);
      expect(composable.hasUnsavedChanges.value).toBe(false);
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
        token_endpoint_auth_method: '',
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
  // runDiagnostics: checks the SAVED record, never the form
  // ---------------------------------------------------------------------------

  describe('runDiagnostics', () => {
    it.each([
      mockDisabledConfig,
      { ...mockOidcConfigData, enabled: false },
      { ...mockSamlConfigData, enabled: false },
    ])(
      'retains passing credential checks through activation and a later save for $provider_type',
      async (record) => {
        mockGetConfigForDomain.mockResolvedValue({ record });
        mockRunDiagnosticsForDomain.mockResolvedValue({
          ...mockDiagnosticsPassed,
          provider_type: record.provider_type,
          activation: 'activated',
          enabled: true,
        });
        mockSaveConfigForDomain.mockImplementation(async (_id, payload) => ({
          record: { ...record, enabled: true, display_name: payload.display_name },
        }));
        const composable = useSsoConfig('dm-ext-123');
        await composable.initialize();
        expect(composable.savedCredentialsChecked.value).toBe(false);

        await composable.runDiagnostics();
        expect(composable.savedCredentialsChecked.value).toBe(true);
        composable.formState.value.display_name = 'Renamed';
        await composable.saveConfig();

        // A PATCH leaves `enabled` to the server, which holds it on.
        const [, payload] = mockSaveConfigForDomain.mock.calls.at(-1)!;
        expect(payload).not.toHaveProperty('enabled');
        expect(composable.diagnosticsResult.value).toBeNull();
        expect(composable.savedCredentialsChecked.value).toBe(true);
        expect(composable.hasUnsavedChanges.value).toBe(false);
      }
    );

    it.each([
      [mockSsoConfigData, 'client_id', 'replacement-client'],
      [mockSsoConfigData, 'tenant_id', 'replacement-tenant'],
      [mockSsoConfigData, 'client_secret', 'replacement-secret'],
      [mockOidcConfigData, 'issuer', 'https://other-idp.example.com'],
      [mockOidcConfigData, 'token_endpoint_auth_method', 'client_secret_post'],
      [mockSamlConfigData, 'idp_sso_service_url', 'https://other-idp.example.com/sso'],
      [mockSamlConfigData, 'idp_entity_id', 'https://other-idp.example.com/entity'],
      [mockSamlConfigData, 'idp_cert', 'replacement-certificate'],
    ] as const)('invalidates passing checks when %s %s is saved', async (record, field, value) => {
      mockGetConfigForDomain.mockResolvedValue({ record });
      mockRunDiagnosticsForDomain.mockResolvedValue({
        ...mockDiagnosticsPassed,
        provider_type: record.provider_type,
      });
      // A secret rotation can leave the displayed mask unchanged.
      mockSaveConfigForDomain.mockResolvedValue({
        record: { ...record, ...(field === 'client_secret' ? {} : { [field]: value }) },
      });
      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();
      await composable.runDiagnostics();
      expect(composable.savedCredentialsChecked.value).toBe(true);
      composable.formState.value = { ...composable.formState.value, [field]: value };

      await composable.saveConfig();

      expect(composable.savedCredentialsChecked.value).toBe(false);
    });

    it('invalidates passing checks when the server returns different credentials after a name-only save', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockDisabledConfig });
      mockSaveConfigForDomain.mockResolvedValue({
        record: { ...mockSsoConfigData, client_id: 'server-changed-client' },
      });
      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();
      await composable.runDiagnostics();
      composable.formState.value.display_name = 'Renamed';

      await composable.saveConfig();

      expect(composable.savedCredentialsChecked.value).toBe(false);
    });

    // Another tab saved the record after this page loaded it: the API checked
    // that newer record, so the pass says nothing about the loaded fields.
    it.each([
      ['a later revision', { configuration_revision: '1736935201' }],
      ['an empty revision', { configuration_revision: '' }],
      ['another provider', { provider_type: 'oidc' as const }],
    ])('takes no passing evidence from a run about %s', async (_label, mismatch) => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockDisabledConfig });
      mockRunDiagnosticsForDomain.mockResolvedValue({ ...mockDiagnosticsPassed, ...mismatch });
      mockSaveConfigForDomain.mockResolvedValue({ record: { ...mockDisabledConfig, enabled: true } });
      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      await composable.runDiagnostics();

      expect(composable.diagnosticsResult.value?.overall).toBe('passed');
      expect(composable.savedCredentialsChecked.value).toBe(false);

      // An activation save from the stale page does not turn it into evidence.
      composable.formState.value.enabled = true;
      await composable.saveConfig();

      expect(composable.savedCredentialsChecked.value).toBe(false);
    });

    it.each([mockDiagnosticsFailed, mockDiagnosticsInconclusive])(
      'revokes earlier passing evidence after a $overall recheck',
      async (result) => {
        mockGetConfigForDomain.mockResolvedValue({ record: mockSsoConfigData });
        const composable = useSsoConfig('dm-ext-123');
        await composable.initialize();
        await composable.runDiagnostics();
        mockRunDiagnosticsForDomain.mockResolvedValue(result);

        await composable.runDiagnostics();

        expect(composable.savedCredentialsChecked.value).toBe(false);
      }
    );

    it('revokes earlier passing evidence after a transport failure', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSsoConfigData });
      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();
      await composable.runDiagnostics();
      mockRunDiagnosticsForDomain.mockRejectedValue(new Error('Network error'));

      await composable.runDiagnostics();

      expect(composable.savedCredentialsChecked.value).toBe(false);
    });

    it.each(['initialize', 'deleteConfig'] as const)(
      'clears passing evidence on %s',
      async (action) => {
        mockGetConfigForDomain.mockResolvedValue({ record: mockSsoConfigData });
        const composable = useSsoConfig('dm-ext-123');
        await composable.initialize();
        await composable.runDiagnostics();

        await composable[action]();

        expect(composable.savedCredentialsChecked.value).toBe(false);
      }
    );

    it('calls SsoService.runDiagnosticsForDomain with the domain id and no payload when the record is on', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSsoConfigData });
      const composable = useSsoConfig('dm-ext-789');
      await composable.initialize();

      // Unsaved edits must not leak into the request: nothing from the form is sent.
      composable.formState.value = { ...composable.formState.value, client_id: 'unsaved' };
      await composable.runDiagnostics();

      expect(mockRunDiagnosticsForDomain).toHaveBeenCalledTimes(1);
      expect(mockRunDiagnosticsForDomain).toHaveBeenCalledWith('dm-ext-789');
    });

    it('asks for activation, and nothing else, when the record is off', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockDisabledConfig });
      const composable = useSsoConfig('dm-ext-789');
      await composable.initialize();

      composable.formState.value = { ...composable.formState.value, client_id: 'unsaved' };
      await composable.runDiagnostics();

      expect(mockRunDiagnosticsForDomain).toHaveBeenCalledExactlyOnceWith('dm-ext-789', {
        activate: true,
      });
    });

    describe('activation', () => {
      it('mirrors an activated record onto the record and both form snapshots', async () => {
        mockGetConfigForDomain.mockResolvedValue({ record: mockDisabledConfig });
        mockRunDiagnosticsForDomain.mockResolvedValue({
          ...mockDiagnosticsPassed,
          activation: 'activated',
          enabled: true,
        });
        const composable = useSsoConfig('dm-ext-123');
        await composable.initialize();

        await composable.runDiagnostics();

        expect(composable.ssoConfig.value?.enabled).toBe(true);
        expect(composable.isEnabled.value).toBe(true);
        expect(composable.formState.value.enabled).toBe(true);
        // Not an unsaved edit: the saved snapshot moved with it.
        expect(composable.hasUnsavedChanges.value).toBe(false);
      });

      it('keeps an activated connection on through the next save', async () => {
        mockGetConfigForDomain.mockResolvedValue({ record: mockDisabledConfig });
        mockRunDiagnosticsForDomain.mockResolvedValue({
          ...mockDiagnosticsPassed,
          activation: 'activated',
          enabled: true,
        });
        const composable = useSsoConfig('dm-ext-123');
        await composable.initialize();
        await composable.runDiagnostics();

        composable.formState.value = { ...composable.formState.value, display_name: 'Renamed' };
        await composable.saveConfig();

        // PATCH: the server keeps the `enabled` it holds.
        const [, patchPayload] = mockSaveConfigForDomain.mock.calls.at(-1)!;
        expect(patchPayload).toMatchObject({ display_name: 'Renamed' });
        expect(patchPayload).not.toHaveProperty('enabled');

        // PUT (a new secret) replaces the record, so it carries the activated state.
        composable.formState.value = { ...composable.formState.value, client_secret: 'rotated-secret' };
        await composable.saveConfig();

        expect(mockSaveConfigForDomain).toHaveBeenLastCalledWith(
          'dm-ext-123',
          expect.objectContaining({ enabled: true, client_secret: 'rotated-secret' })
        );
      });

      it('keeps unsaved edits made while the run was in flight', async () => {
        mockGetConfigForDomain.mockResolvedValue({ record: mockDisabledConfig });
        let settle!: (value: unknown) => void;
        mockRunDiagnosticsForDomain.mockReturnValue(
          new Promise((resolve) => {
            settle = resolve;
          })
        );
        const composable = useSsoConfig('dm-ext-123');
        await composable.initialize();

        const pending = composable.runDiagnostics();
        composable.formState.value = { ...composable.formState.value, display_name: 'Typing' };
        settle({ ...mockDiagnosticsPassed, activation: 'activated', enabled: true });
        await pending;

        expect(composable.formState.value.display_name).toBe('Typing');
        expect(composable.formState.value.enabled).toBe(true);
        expect(composable.hasUnsavedChanges.value).toBe(true);
      });

      it.each(['not_passed', 'not_permitted', 'configuration_changed'] as const)(
        'leaves the record off for %s',
        async (activation) => {
          mockGetConfigForDomain.mockResolvedValue({ record: mockDisabledConfig });
          mockRunDiagnosticsForDomain.mockResolvedValue({
            ...(activation === 'not_passed' ? mockDiagnosticsFailed : mockDiagnosticsPassed),
            activation,
            enabled: false,
          });
          const composable = useSsoConfig('dm-ext-123');
          await composable.initialize();

          await composable.runDiagnostics();

          expect(composable.diagnosticsResult.value?.activation).toBe(activation);
          expect(composable.ssoConfig.value?.enabled).toBe(false);
          expect(composable.formState.value.enabled).toBe(false);
        }
      );

      it('leaves the record off after a 429, with the wait in the message', async () => {
        mockGetConfigForDomain.mockResolvedValue({ record: mockDisabledConfig });
        mockRunDiagnosticsForDomain.mockRejectedValue({
          code: 429,
          details: { retry_after: 300 },
        });
        const composable = useSsoConfig('dm-ext-123');
        await composable.initialize();

        await composable.runDiagnostics();

        expect(composable.diagnosticsResult.value).toBeNull();
        expect(composable.diagnosticsError.value).toBe(
          'web.domains.sso.diagnostics_rate_limited_retry'
        );
        expect(composable.ssoConfig.value?.enabled).toBe(false);
      });
    });

    describe('saveAndRunDiagnostics', () => {
      it('saves a new record off, then asks to turn it on', async () => {
        mockGetConfigForDomain.mockResolvedValue({ record: null });
        mockSaveConfigForDomain.mockResolvedValue({ record: mockDisabledConfig });
        const composable = useSsoConfig('dm-ext-123');
        await composable.initialize();
        composable.formState.value = {
          ...composable.formState.value,
          display_name: 'New SSO',
          client_id: 'client-id',
          client_secret: 'secret-value',
          tenant_id: 'tenant-id',
        };

        await composable.saveAndRunDiagnostics();

        expect(mockSaveConfigForDomain).toHaveBeenCalledWith(
          'dm-ext-123',
          expect.objectContaining({ enabled: false })
        );
        expect(mockRunDiagnosticsForDomain).toHaveBeenCalledExactlyOnceWith('dm-ext-123', {
          activate: true,
        });
        expect(mockSaveConfigForDomain.mock.invocationCallOrder[0]).toBeLessThan(
          mockRunDiagnosticsForDomain.mock.invocationCallOrder[0]
        );
      });

      it('saves unsaved edits first', async () => {
        mockGetConfigForDomain.mockResolvedValue({ record: mockSsoConfigData });
        const composable = useSsoConfig('dm-ext-123');
        await composable.initialize();
        composable.formState.value = { ...composable.formState.value, display_name: 'Edited' };

        await composable.saveAndRunDiagnostics();

        expect(mockSaveConfigForDomain).toHaveBeenCalledTimes(1);
        expect(mockRunDiagnosticsForDomain).toHaveBeenCalledExactlyOnceWith('dm-ext-123');
      });

      it('only checks a saved record with no unsaved edits', async () => {
        mockGetConfigForDomain.mockResolvedValue({ record: mockDisabledConfig });
        const composable = useSsoConfig('dm-ext-123');
        await composable.initialize();

        await composable.saveAndRunDiagnostics();

        expect(mockSaveConfigForDomain).not.toHaveBeenCalled();
        expect(mockRunDiagnosticsForDomain).toHaveBeenCalledExactlyOnceWith('dm-ext-123', {
          activate: true,
        });
      });

      it('does not check when the save fails', async () => {
        mockGetConfigForDomain.mockResolvedValue({ record: null });
        mockSaveConfigForDomain.mockRejectedValueOnce(new Error('Failed'));
        const composable = useSsoConfig('dm-ext-123');
        await composable.initialize();

        await composable.saveAndRunDiagnostics();

        expect(mockRunDiagnosticsForDomain).not.toHaveBeenCalled();
        expect(composable.ssoConfig.value).toBeNull();
      });
    });

    describe('savedCredentialsUnchecked', () => {
      it.each([
        ['a new secret', { client_secret: 'rotated-secret' }, {}],
        ['a different client ID', { client_id: 'other-client' }, { client_id: 'other-client' }],
      ])('is set by a save of %s', async (_change, edit, saved) => {
        mockGetConfigForDomain.mockResolvedValue({ record: mockSsoConfigData });
        mockSaveConfigForDomain.mockResolvedValue({ record: { ...mockSsoConfigData, ...saved } });
        const composable = useSsoConfig('dm-ext-123');
        await composable.initialize();
        expect(composable.savedCredentialsUnchecked.value).toBe(false);

        composable.formState.value = { ...composable.formState.value, ...edit };
        await composable.saveConfig();

        expect(composable.savedCredentialsUnchecked.value).toBe(true);
      });

      it('is not set by a save that keeps the credentials', async () => {
        mockGetConfigForDomain.mockResolvedValue({ record: mockSsoConfigData });
        const composable = useSsoConfig('dm-ext-123');
        await composable.initialize();

        composable.formState.value = { ...composable.formState.value, display_name: 'Renamed' };
        await composable.saveConfig();

        expect(composable.savedCredentialsUnchecked.value).toBe(false);
      });

      it('survives a failed run and clears on a passing one', async () => {
        mockGetConfigForDomain.mockResolvedValue({ record: mockSsoConfigData });
        const composable = useSsoConfig('dm-ext-123');
        await composable.initialize();
        composable.formState.value = { ...composable.formState.value, client_secret: 'new' };
        await composable.saveConfig();

        mockRunDiagnosticsForDomain.mockResolvedValueOnce(mockDiagnosticsFailed);
        await composable.runDiagnostics();
        expect(composable.savedCredentialsUnchecked.value).toBe(true);

        await composable.runDiagnostics();
        expect(composable.savedCredentialsUnchecked.value).toBe(false);
      });

      it('survives a passing run about a record saved elsewhere', async () => {
        mockGetConfigForDomain.mockResolvedValue({ record: mockSsoConfigData });
        const composable = useSsoConfig('dm-ext-123');
        await composable.initialize();
        composable.formState.value = { ...composable.formState.value, client_secret: 'new' };
        await composable.saveConfig();
        mockRunDiagnosticsForDomain.mockResolvedValueOnce({
          ...mockDiagnosticsPassed,
          configuration_revision: '1736935201',
        });

        await composable.runDiagnostics();

        expect(composable.diagnosticsResult.value?.overall).toBe('passed');
        expect(composable.savedCredentialsUnchecked.value).toBe(true);
      });

      it.each(['initialize', 'deleteConfig'] as const)('clears on %s', async (action) => {
        mockGetConfigForDomain.mockResolvedValue({ record: mockSsoConfigData });
        const composable = useSsoConfig('dm-ext-123');
        await composable.initialize();
        composable.formState.value = { ...composable.formState.value, client_secret: 'new' };
        await composable.saveConfig();

        await composable[action]();

        expect(composable.savedCredentialsUnchecked.value).toBe(false);
      });
    });

    it('stores a passed result and notifies success', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSsoConfigData });
      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      await composable.runDiagnostics();

      expect(composable.diagnosticsResult.value).toEqual(mockDiagnosticsPassed);
      expect(composable.diagnosticsError.value).toBe('');
      expect(mockNotificationsShow).toHaveBeenCalledWith(
        'Saved configuration check passed',
        'success',
        'top'
      );
    });

    it('stores a failed result (a verdict, not an error) and notifies error', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSsoConfigData });
      mockRunDiagnosticsForDomain.mockResolvedValue(mockDiagnosticsFailed);
      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      await composable.runDiagnostics();

      expect(composable.diagnosticsResult.value).toEqual(mockDiagnosticsFailed);
      expect(composable.diagnosticsError.value).toBe('');
      expect(mockNotificationsShow).toHaveBeenCalledWith(
        'Saved configuration check found a problem',
        'error',
        'top'
      );
    });

    it('stores an inconclusive result and notifies warning', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSsoConfigData });
      mockRunDiagnosticsForDomain.mockResolvedValue(mockDiagnosticsInconclusive);
      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      await composable.runDiagnostics();

      expect(composable.diagnosticsResult.value?.overall).toBe('inconclusive');
      expect(mockNotificationsShow).toHaveBeenCalledWith(
        'Saved configuration check could not reach a verdict',
        'warning',
        'top'
      );
    });

    it('sets diagnosticsError and no result when the request fails', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSsoConfigData });
      mockRunDiagnosticsForDomain.mockRejectedValue(new Error('Network error'));
      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      await composable.runDiagnostics();

      expect(composable.diagnosticsResult.value).toBeNull();
      expect(composable.diagnosticsError.value).toBe('Failed to check the saved configuration');
      expect(composable.isDiagnosing.value).toBe(false);
    });

    // The API caps runs per customer (SsoDiagnosticsRateLimiter) and answers
    // 429 with a LimitExceeded body; the classifier turns that into an
    // ApplicationError with code 429 and the body as details.
    const rateLimited = (retry_after?: number) => ({
      name: 'ApplicationError',
      message: 'Too many saved-configuration checks. Please try again later.',
      type: 'human',
      severity: 'error',
      code: 429,
      details: {
        error: 'Too many saved-configuration checks.',
        error_type: 'LimitExceeded',
        retry_after,
      },
    });

    it('reports a 429 as the run limit, with the wait rounded up to minutes', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSsoConfigData });
      mockRunDiagnosticsForDomain.mockRejectedValue(rateLimited(1234));
      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      await composable.runDiagnostics();

      expect(composable.diagnosticsResult.value).toBeNull();
      expect(composable.diagnosticsError.value).toBe(
        'web.domains.sso.diagnostics_rate_limited_retry'
      );
      expect(mockRunDiagnosticsForDomain).toHaveBeenCalledTimes(1);
    });

    it('reports a 429 without retry_after as the run limit with no wait', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSsoConfigData });
      mockRunDiagnosticsForDomain.mockRejectedValue(rateLimited());
      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      await composable.runDiagnostics();

      expect(composable.diagnosticsError.value).toBe('web.domains.sso.diagnostics_rate_limited');
    });

    it("does not read an earlier failure as this run's", async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSsoConfigData });
      mockRunDiagnosticsForDomain.mockRejectedValueOnce(rateLimited(60));
      mockRunDiagnosticsForDomain.mockRejectedValueOnce(new Error('Network error'));
      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      await composable.runDiagnostics();
      expect(composable.diagnosticsError.value).toBe(
        'web.domains.sso.diagnostics_rate_limited_retry'
      );

      await composable.runDiagnostics();
      expect(composable.diagnosticsError.value).toBe('Failed to check the saved configuration');
    });

    it('sets isDiagnosing during the request and resets it after', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSsoConfigData });
      let resolveRun: (value: unknown) => void;
      mockRunDiagnosticsForDomain.mockImplementation(
        () =>
          new Promise((resolve) => {
            resolveRun = resolve;
          })
      );
      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      const pending = composable.runDiagnostics();
      expect(composable.isDiagnosing.value).toBe(true);

      resolveRun!(mockDiagnosticsPassed);
      await pending;

      expect(composable.isDiagnosing.value).toBe(false);
    });

    it('clears the previous result and error when a new run starts', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSsoConfigData });
      mockRunDiagnosticsForDomain.mockRejectedValueOnce(new Error('boom'));
      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      await composable.runDiagnostics();
      expect(composable.diagnosticsError.value).not.toBe('');

      await composable.runDiagnostics();
      expect(composable.diagnosticsError.value).toBe('');
      expect(composable.diagnosticsResult.value).toEqual(mockDiagnosticsPassed);
    });

    it('survives an unsaved form edit (the result is about the saved record)', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSsoConfigData });
      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();
      await composable.runDiagnostics();

      composable.formState.value = { ...composable.formState.value, tenant_id: 'edited' };

      expect(composable.diagnosticsResult.value).toEqual(mockDiagnosticsPassed);
    });

    it('is cleared by a save (the saved record changed)', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSsoConfigData });
      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();
      await composable.runDiagnostics();
      expect(composable.diagnosticsResult.value).not.toBeNull();

      await composable.saveConfig();

      expect(composable.diagnosticsResult.value).toBeNull();
      expect(composable.diagnosticsError.value).toBe('');
    });

    it('is cleared by deleteConfig', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSsoConfigData });
      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();
      await composable.runDiagnostics();

      await composable.deleteConfig();

      expect(composable.diagnosticsResult.value).toBeNull();
      expect(composable.diagnosticsError.value).toBe('');
    });

    // Save and delete are not blocked while a run is in flight (Copilot,
    // PR #4773): a late response must not repopulate a result for a record
    // that was replaced or removed while the probe ran.
    describe('a response that lands after the saved record changed', () => {
      const deferredRun = () => {
        let settle!: { resolve: (value: unknown) => void; reject: (reason: unknown) => void };
        mockRunDiagnosticsForDomain.mockImplementation(
          () =>
            new Promise((resolve, reject) => {
              settle = { resolve, reject };
            })
        );
        return () => settle;
      };

      it('is dropped when the record was saved while the run was in flight', async () => {
        mockGetConfigForDomain.mockResolvedValue({ record: mockSsoConfigData });
        const settle = deferredRun();
        const composable = useSsoConfig('dm-ext-123');
        await composable.initialize();

        const pending = composable.runDiagnostics();
        await composable.saveConfig();
        mockNotificationsShow.mockClear();
        settle().resolve(mockDiagnosticsPassed);
        await pending;

        expect(composable.diagnosticsResult.value).toBeNull();
        expect(composable.diagnosticsError.value).toBe('');
        expect(composable.isDiagnosing.value).toBe(false);
        expect(composable.savedCredentialsChecked.value).toBe(false);
        expect(mockNotificationsShow).not.toHaveBeenCalled();
      });

      it('is dropped when the record was deleted while the run was in flight', async () => {
        mockGetConfigForDomain.mockResolvedValue({ record: mockSsoConfigData });
        const settle = deferredRun();
        const composable = useSsoConfig('dm-ext-123');
        await composable.initialize();

        const pending = composable.runDiagnostics();
        await composable.deleteConfig();
        settle().resolve(mockDiagnosticsFailed);
        await pending;

        expect(composable.diagnosticsResult.value).toBeNull();
        expect(composable.isConfigured.value).toBe(false);
        expect(composable.isDiagnosing.value).toBe(false);
      });

      it('drops a late transport failure too, so no error is shown for the old record', async () => {
        mockGetConfigForDomain.mockResolvedValue({ record: mockSsoConfigData });
        const settle = deferredRun();
        const composable = useSsoConfig('dm-ext-123');
        await composable.initialize();

        const pending = composable.runDiagnostics();
        await composable.saveConfig();
        settle().reject(new Error('Network error'));
        await pending;

        expect(composable.diagnosticsError.value).toBe('');
        expect(composable.diagnosticsResult.value).toBeNull();
        expect(composable.isDiagnosing.value).toBe(false);
      });

      it('keeps a response when nothing changed the record while the run was in flight', async () => {
        mockGetConfigForDomain.mockResolvedValue({ record: mockSsoConfigData });
        const settle = deferredRun();
        const composable = useSsoConfig('dm-ext-123');
        await composable.initialize();

        const pending = composable.runDiagnostics();
        composable.formState.value = { ...composable.formState.value, tenant_id: 'edited' };
        settle().resolve(mockDiagnosticsPassed);
        await pending;

        expect(composable.diagnosticsResult.value).toEqual(mockDiagnosticsPassed);
      });

      it('refuses a second run while one is in flight', async () => {
        mockGetConfigForDomain.mockResolvedValue({ record: mockSsoConfigData });
        const settle = deferredRun();
        const composable = useSsoConfig('dm-ext-123');
        await composable.initialize();

        const pending = composable.runDiagnostics();
        await composable.runDiagnostics();
        settle().resolve(mockDiagnosticsPassed);
        await pending;

        expect(mockRunDiagnosticsForDomain).toHaveBeenCalledTimes(1);
        expect(composable.diagnosticsResult.value).toEqual(mockDiagnosticsPassed);
      });
    });
  });

  // ---------------------------------------------------------------------------
  // refreshLastSignIn: the last sign-in outcome only, never the form
  // ---------------------------------------------------------------------------

  describe('refreshLastSignIn', () => {
    const signedIn = {
      result: 'succeeded' as const,
      at: 1760000000,
      succeeded_at: 1760000000,
      failed_at: null,
      failure_stage: null,
      failure_code: null,
      provider_type: 'entra_id' as const,
    };

    it('takes only last_sign_in from the response and keeps unsaved edits', async () => {
      mockGetConfigForDomain.mockResolvedValueOnce({ record: mockSsoConfigData });
      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();
      composable.formState.value = { ...composable.formState.value, display_name: 'Unsaved' };
      // Every other field differs, so a wholesale replace would show.
      mockGetConfigForDomain.mockResolvedValueOnce({
        record: {
          ...mockSsoConfigData,
          display_name: 'Changed elsewhere',
          client_id: 'changed-elsewhere',
          last_sign_in: signedIn,
        },
      });

      await composable.refreshLastSignIn();

      expect(composable.ssoConfig.value?.last_sign_in).toEqual(signedIn);
      expect(composable.ssoConfig.value?.display_name).toBe(mockSsoConfigData.display_name);
      expect(composable.ssoConfig.value?.client_id).toBe(mockSsoConfigData.client_id);
      expect(composable.formState.value.display_name).toBe('Unsaved');
      expect(composable.formState.value.client_id).toBe(mockSsoConfigData.client_id);
      expect(composable.hasUnsavedChanges.value).toBe(true);
      expect(composable.isLoading.value).toBe(false);
    });

    it('keeps a passing check and the displayed result', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSsoConfigData });
      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();
      await composable.runDiagnostics();

      await composable.refreshLastSignIn();

      expect(composable.savedCredentialsChecked.value).toBe(true);
      expect(composable.diagnosticsResult.value).toEqual(mockDiagnosticsPassed);
    });

    it('marks a focus or visibility refresh passive, and a click active', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSsoConfigData });
      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();
      mockGetConfigForDomain.mockClear();

      await composable.refreshLastSignIn({ passive: true });
      await composable.refreshLastSignIn();

      expect(mockGetConfigForDomain.mock.calls).toEqual([
        ['dm-ext-123', { passive: true }],
        ['dm-ext-123'],
      ]);
    });

    it('shares a refresh already in flight', async () => {
      mockGetConfigForDomain.mockResolvedValueOnce({ record: mockSsoConfigData });
      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();
      let settle!: (value: unknown) => void;
      mockGetConfigForDomain.mockReturnValueOnce(
        new Promise((resolve) => {
          settle = resolve;
        })
      );

      const first = composable.refreshLastSignIn({ passive: true });
      expect(composable.isRefreshingLastSignIn.value).toBe(true);
      const second = composable.refreshLastSignIn({ passive: true });
      settle({ record: { ...mockSsoConfigData, last_sign_in: signedIn } });
      await Promise.all([first, second]);

      expect(mockGetConfigForDomain).toHaveBeenCalledTimes(2); // initialize + one refresh
      expect(composable.isRefreshingLastSignIn.value).toBe(false);
      expect(composable.ssoConfig.value?.last_sign_in).toEqual(signedIn);
    });

    it('does nothing before a record is saved', async () => {
      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();
      mockGetConfigForDomain.mockClear();

      await composable.refreshLastSignIn();

      expect(mockGetConfigForDomain).not.toHaveBeenCalled();
    });

    it('drops a response that lands after the record was reloaded', async () => {
      mockGetConfigForDomain.mockResolvedValueOnce({ record: mockSsoConfigData });
      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();
      let settle!: (value: unknown) => void;
      mockGetConfigForDomain.mockReturnValueOnce(
        new Promise((resolve) => {
          settle = resolve;
        })
      );
      const pending = composable.refreshLastSignIn();

      mockGetConfigForDomain.mockResolvedValueOnce({ record: mockSsoConfigData });
      await composable.initialize();
      settle({ record: { ...mockSsoConfigData, last_sign_in: signedIn } });
      await pending;

      expect(composable.ssoConfig.value?.last_sign_in).toBeNull();
    });

    it('keeps what is shown when the request fails, without a toast or page error', async () => {
      mockGetConfigForDomain.mockResolvedValueOnce({ record: mockSsoConfigData });
      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();
      mockNotificationsShow.mockClear();
      mockGetConfigForDomain.mockRejectedValueOnce(new Error('Network error'));

      await composable.refreshLastSignIn({ passive: true });

      expect(composable.ssoConfig.value).toEqual(mockSsoConfigData);
      expect(composable.error.value).toBeNull();
      expect(mockNotificationsShow).not.toHaveBeenCalled();
      expect(mockRouterPush).not.toHaveBeenCalled();
      expect(composable.isRefreshingLastSignIn.value).toBe(false);
    });
  });

  // ---------------------------------------------------------------------------
  // testResult is bound to the fields it was run against (#4764 review)
  // ---------------------------------------------------------------------------

  describe('testResult staleness', () => {
    const oidcSuccess: TestSsoConnectionResponse = {
      ...mockTestSuccessResponse,
      provider_type: 'oidc',
      details: {
        ...mockTestSuccessResponse.details,
        token_endpoint_auth_methods_supported: ['client_secret_basic'],
        token_endpoint_auth_method_supported: false,
      },
    };

    const testedOidc = async () => {
      mockGetConfigForDomain.mockResolvedValue({
        record: { ...mockOidcConfigData, token_endpoint_auth_method: 'client_secret_post' },
      });
      mockTestConnectionForDomain.mockResolvedValue(oidcSuccess);
      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();
      await composable.testConnection();
      expect(composable.testResult.value).toEqual(oidcSuccess);
      return composable;
    };

    it('clears the result when token_endpoint_auth_method changes', async () => {
      const composable = await testedOidc();

      composable.formState.value = {
        ...composable.formState.value,
        token_endpoint_auth_method: 'client_secret_basic',
      };

      expect(composable.testResult.value).toBeNull();
      expect(composable.testError.value).toBe('');
    });

    it('clears the result when issuer changes', async () => {
      const composable = await testedOidc();

      composable.formState.value = {
        ...composable.formState.value,
        issuer: 'https://other.example.com',
      };

      expect(composable.testResult.value).toBeNull();
    });

    it.each(['client_id', 'provider_type'] as const)(
      'clears the result when %s changes',
      async (field) => {
        const composable = await testedOidc();

        composable.formState.value = {
          ...composable.formState.value,
          [field]: field === 'provider_type' ? 'entra_id' : 'other-client',
        };

        expect(composable.testResult.value).toBeNull();
      }
    );

    it('clears a failure result (and testError) on an edit too', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSsoConfigData });
      mockTestConnectionForDomain.mockResolvedValue(mockTestFailureResponse);
      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();
      await composable.testConnection();
      expect(composable.testError.value).toBe(mockTestFailureResponse.message);

      composable.formState.value = { ...composable.formState.value, tenant_id: 'other-tenant' };

      expect(composable.testResult.value).toBeNull();
      expect(composable.testError.value).toBe('');
    });

    it('keeps the result when a field the test does not send changes', async () => {
      const composable = await testedOidc();

      composable.formState.value = {
        ...composable.formState.value,
        display_name: 'Renamed',
        client_secret: 'rotated-secret',
        allowed_domains: ['new.example.com'],
        enabled: true,
        enforce_sso_only: true,
        grant_org_scope: true,
      };

      expect(composable.testResult.value).toEqual(oidcSuccess);
    });

    it('keeps the result when a change is a no-op for the test payload (whitespace)', async () => {
      const composable = await testedOidc();

      composable.formState.value = {
        ...composable.formState.value,
        issuer: '  https://idp.example.com  ',
      };

      expect(composable.testResult.value).toEqual(oidcSuccess);
    });

    it('keeps the result when saveConfig hydrates the form with the tested fields', async () => {
      const composable = await testedOidc();
      // The saved record carries what was tested; only an untested field differs.
      mockSaveConfigForDomain.mockResolvedValue({
        record: {
          ...mockOidcConfigData,
          token_endpoint_auth_method: 'client_secret_post',
          display_name: 'Saved',
        },
      });

      await composable.saveConfig();

      expect(composable.formState.value.display_name).toBe('Saved');
      expect(composable.testResult.value).toEqual(oidcSuccess);

      // An edit from the hydrated values still clears.
      composable.formState.value = { ...composable.formState.value, issuer: 'https://x.example' };
      expect(composable.testResult.value).toBeNull();
    });

    it('clears the result when the saved record differs in a tested field', async () => {
      const composable = await testedOidc();
      // The server stored something other than what was tested (a value it
      // rewrote, or a concurrent save): the result no longer describes the form.
      mockSaveConfigForDomain.mockResolvedValue({
        record: {
          ...mockOidcConfigData,
          token_endpoint_auth_method: 'client_secret_post',
          issuer: 'https://idp.example.com/',
        },
      });

      await composable.saveConfig();

      expect(composable.formState.value.issuer).toBe('https://idp.example.com/');
      expect(composable.testResult.value).toBeNull();
    });

    it('keeps the result when initialize hydrates the same record again', async () => {
      const composable = await testedOidc();

      await composable.initialize();

      expect(composable.formState.value.token_endpoint_auth_method).toBe('client_secret_post');
      expect(composable.testResult.value).toEqual(oidcSuccess);
    });

    it('clears the result when initialize hydrates a record whose tested fields changed', async () => {
      const composable = await testedOidc();
      mockGetConfigForDomain.mockResolvedValue({
        record: { ...mockOidcConfigData, token_endpoint_auth_method: 'client_secret_basic' },
      });

      await composable.initialize();

      expect(composable.formState.value.token_endpoint_auth_method).toBe('client_secret_basic');
      expect(composable.testResult.value).toBeNull();
    });

    it('discards a result for values edited away while the test was in flight', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockOidcConfigData });
      let resolveTest: (value: TestSsoConnectionResponse) => void = () => {};
      mockTestConnectionForDomain.mockReturnValue(
        new Promise<TestSsoConnectionResponse>((resolve) => {
          resolveTest = resolve;
        })
      );
      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      const pending = composable.testConnection();
      composable.formState.value = {
        ...composable.formState.value,
        issuer: 'https://changed.example.com',
      };
      resolveTest(oidcSuccess);
      await pending;

      expect(composable.testResult.value).toBeNull();
    });

    it('clears the result on deleteConfig', async () => {
      const composable = await testedOidc();

      await composable.deleteConfig();

      expect(composable.testResult.value).toBeNull();
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
