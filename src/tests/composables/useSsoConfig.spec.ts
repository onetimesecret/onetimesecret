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

import { createPinia, setActivePinia } from 'pinia';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { useSsoConfig } from '../../shared/composables/useSsoConfig';

import type { CustomDomainSsoConfig } from '../../schemas/shapes/domains/sso-config';
import type { TestSsoConnectionResponse } from '../../services/sso.service';

// -----------------------------------------------------------------------------
// Mock Setup
// -----------------------------------------------------------------------------

const mockGetConfigForDomain = vi.fn();
const mockSaveConfigForDomain = vi.fn();
const mockPatchConfigForDomain = vi.fn();
const mockDeleteConfigForDomain = vi.fn();
const mockTestConnectionForDomain = vi.fn();
const mockNotificationsShow = vi.fn();
const mockRouterPush = vi.fn();

vi.mock('@/services/sso.service', () => ({
  SsoService: {
    getConfigForDomain: (...args: unknown[]) => mockGetConfigForDomain(...args),
    saveConfigForDomain: (...args: unknown[]) => mockSaveConfigForDomain(...args),
    patchConfigForDomain: (...args: unknown[]) => mockPatchConfigForDomain(...args),
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
  useAsyncHandler: (options: { setLoading?: (loading: boolean) => void }) => ({
    wrap: vi.fn(async (fn: () => Promise<unknown>) => {
      options.setLoading?.(true);
      try {
        return await fn();
      } catch {
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
  idp_sso_service_url: null,
  idp_entity_id: null,
  idp_cert: null,
  sp_entity_id: null,
  acs_url: null,
  unreadable_fields: [],
  allowed_domains: ['acme.com', 'acme.org'],
  requires_domain_filter: false,
  idp_controls_access: true,
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
};

const mockOidcConfigData: CustomDomainSsoConfig = {
  ...mockSsoConfigData,
  provider_type: 'oidc',
  tenant_id: null,
  issuer: 'https://idp.example.com',
  requires_domain_filter: true,
  idp_controls_access: false,
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

    // #4107: the Connection active toggle writes formState.enabled, and
    // saveConfig must carry it to the API — this field had NO UI writer after
    // 7326689cdc, stranding every saved config at enabled=false. saveConfig
    // builds ONE payload for both create (PUT) and update (PATCH);
    // SsoService.saveConfigForDomain picks the verb, so the two tests below
    // differ only in the initialized record (null vs existing).
    it('includes enabled: true in the save payload (create path — #4107)', async () => {
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

      await composable.saveConfig();

      expect(mockSaveConfigForDomain).toHaveBeenCalledWith(
        'dm-ext-123',
        expect.objectContaining({ enabled: true })
      );
    });

    it('sends enabled: false explicitly on update — not dropped as falsy (#4107)', async () => {
      // Existing config with enabled: true; admin turns the connection off.
      mockGetConfigForDomain.mockResolvedValue({ record: mockSsoConfigData });
      const composable = useSsoConfig('dm-ext-123');
      await composable.initialize();

      composable.formState.value = {
        ...composable.formState.value,
        enabled: false,
      };

      await composable.saveConfig();

      // The literal false must ride along: a truthiness-guarded payload
      // builder would omit it and the record would stay enabled.
      expect(mockSaveConfigForDomain).toHaveBeenCalledWith(
        'dm-ext-123',
        expect.objectContaining({ enabled: false })
      );
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

  describe('disableConfig recovery', () => {
    it('PATCHes only the two flags despite unreadable credentials and unsaved edits', async () => {
      const record = { ...mockEnforceSsoOnlyConfig, unreadable_fields: ['client_secret'] };
      mockGetConfigForDomain.mockResolvedValueOnce({ record });
      const disabled = { ...record, enabled: false, enforce_sso_only: false };
      mockPatchConfigForDomain.mockResolvedValueOnce({ record: disabled });
      const composable = useSsoConfig('dm_123');
      await composable.initialize();
      composable.formState.value.display_name = 'Unsaved name';
      composable.formState.value.client_secret = 'unsaved-secret';
      composable.formState.value.enabled = false;

      await composable.disableConfig();

      expect(mockPatchConfigForDomain).toHaveBeenCalledExactlyOnceWith('dm_123', {
        enabled: false,
        enforce_sso_only: false,
      });
      expect(mockSaveConfigForDomain).not.toHaveBeenCalled();
      expect(composable.ssoConfig.value).toEqual(disabled);
      expect(composable.formState.value.client_secret).toBe('unsaved-secret');
      expect(composable.formState.value.enforce_sso_only).toBe(false);
      expect(composable.hasUnsavedChanges.value).toBe(true);
      composable.discardChanges();
      expect(composable.formState.value.display_name).toBe(record.display_name);
      expect(composable.formState.value.enabled).toBe(false);
      expect(composable.hasUnsavedChanges.value).toBe(false);
    });

    it('holds the saving flag and prevents duplicate requests until completion', async () => {
      mockGetConfigForDomain.mockResolvedValueOnce({ record: mockSsoConfigData });
      let resolve!: (value: unknown) => void;
      mockPatchConfigForDomain.mockReturnValueOnce(
        new Promise((done) => {
          resolve = done;
        })
      );
      const composable = useSsoConfig('dm_123');
      await composable.initialize();
      const pending = composable.disableConfig();
      expect(composable.isSaving.value).toBe(true);
      await composable.disableConfig();
      expect(mockPatchConfigForDomain).toHaveBeenCalledTimes(1);
      resolve({ record: { ...mockSsoConfigData, enabled: false } });
      await pending;
      expect(composable.isSaving.value).toBe(false);
    });

    it('retains config and drafts on failure and permits retry', async () => {
      mockGetConfigForDomain.mockResolvedValueOnce({ record: mockSsoConfigData });
      mockPatchConfigForDomain.mockRejectedValueOnce(new Error('Failed'));
      const composable = useSsoConfig('dm_123');
      await composable.initialize();
      composable.formState.value.display_name = 'Draft';
      await composable.disableConfig();
      expect(composable.isSaving.value).toBe(false);
      expect(composable.ssoConfig.value).toEqual(mockSsoConfigData);
      expect(composable.formState.value.display_name).toBe('Draft');
      expect(mockNotificationsShow).not.toHaveBeenCalled();
      mockPatchConfigForDomain.mockResolvedValueOnce({ record: mockDisabledConfig });
      await composable.disableConfig();
      expect(composable.isEnabled.value).toBe(false);
    });

    it.each([null, mockDisabledConfig])(
      'does not PATCH an absent or disabled record',
      async (record) => {
        mockGetConfigForDomain.mockResolvedValueOnce({ record });
        const composable = useSsoConfig('dm_123');
        await composable.initialize();
        await composable.disableConfig();
        expect(mockPatchConfigForDomain).not.toHaveBeenCalled();
      }
    );
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
