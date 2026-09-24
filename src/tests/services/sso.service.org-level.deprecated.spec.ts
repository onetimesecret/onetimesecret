// src/tests/services/sso.service.org-level.deprecated.spec.ts
//
// DEPRECATED: This file tests org-level SSO API methods that no longer exist.
//
// As of #2786, SSO configuration moved from per-organization to per-domain.
// The old API methods (getConfig, putConfig, patchConfig, saveConfig, deleteConfig, testConnection)
// have been replaced by domain-scoped methods (getConfigForDomain, putConfigForDomain, etc.).
//
// For active tests, see: sso.service.domain.spec.ts
//
// This file is preserved for reference but all tests are skipped.

import { describe, it, expect, vi, beforeEach } from 'vitest';

// Use vi.hoisted to properly hoist mock functions before vi.mock
const { mockGet, mockPut, mockPatch, mockPost, mockDelete } = vi.hoisted(() => ({
  mockGet: vi.fn(),
  mockPut: vi.fn(),
  mockPatch: vi.fn(),
  mockPost: vi.fn(),
  mockDelete: vi.fn(),
}));

vi.mock('@/api', () => ({
  createApi: () => ({
    get: mockGet,
    put: mockPut,
    patch: mockPatch,
    post: mockPost,
    delete: mockDelete,
  }),
}));

// Import after mocking
import { SsoService } from '@/services/sso.service';

/**
 * The org-level methods this file exercises (getConfig/putConfig/patchConfig/
 * saveConfig/deleteConfig/testConnection) were removed from SsoService in
 * #2786 — the real service now exposes only the *ForDomain methods (see
 * sso.service.ts). This whole suite is `describe.skip`-ped and kept solely as
 * a historical reference of the old contract (no test here ever executes), so
 * this cast — not a production change — exists only to let the reference file
 * still type-check against the CURRENT SsoService shape.
 */
interface DeprecatedOrgLevelSsoService {
  getConfig(orgExtId: string): Promise<Record<string, unknown>>;
  putConfig(
    orgExtId: string,
    payload: Record<string, unknown>
  ): Promise<Record<string, unknown>>;
  patchConfig(
    orgExtId: string,
    payload: Record<string, unknown>
  ): Promise<Record<string, unknown>>;
  saveConfig(
    orgExtId: string,
    payload: Record<string, unknown>
  ): Promise<Record<string, unknown>>;
  deleteConfig(orgExtId: string): Promise<Record<string, unknown>>;
  testConnection(
    orgExtId: string,
    payload: Record<string, unknown>
  ): Promise<{
    success: boolean;
    provider_type: string;
    message?: string;
    details: Record<string, unknown>;
  }>;
}

const DeprecatedSsoService = SsoService as unknown as DeprecatedOrgLevelSsoService;

describe.skip('SsoService (DEPRECATED: org-level API removed in #2786)', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockGet.mockReset();
    mockPut.mockReset();
    mockPatch.mockReset();
    mockPost.mockReset();
    mockDelete.mockReset();
  });

  describe('getConfig', () => {
    it('calls correct endpoint with org extid', async () => {
      const mockResponse = {
        data: {
          record: {
            id: 'sso_123',
            provider_type: 'entra_id',
            client_id: 'client-abc',
            display_name: 'Test SSO',
            enabled: true,
          },
        },
      };
      mockGet.mockResolvedValueOnce(mockResponse);

      const result = await DeprecatedSsoService.getConfig('org_abc123');

      expect(mockGet).toHaveBeenCalledWith('/api/organizations/org_abc123/sso');
      expect(result).toEqual(mockResponse.data);
    });

    it('returns { record: null } on 404 response', async () => {
      const axiosError = {
        response: { status: 404 },
        isAxiosError: true,
      };
      mockGet.mockRejectedValueOnce(axiosError);

      const result = await DeprecatedSsoService.getConfig('org_no_sso');

      expect(mockGet).toHaveBeenCalledWith('/api/organizations/org_no_sso/sso');
      expect(result).toEqual({ record: null });
    });

    it('propagates non-404 errors', async () => {
      const axiosError = {
        response: { status: 500 },
        isAxiosError: true,
        message: 'Internal Server Error',
      };
      mockGet.mockRejectedValueOnce(axiosError);

      await expect(DeprecatedSsoService.getConfig('org_error')).rejects.toEqual(axiosError);
    });

    it('propagates network errors without response', async () => {
      const networkError = new Error('Network Error');
      mockGet.mockRejectedValueOnce(networkError);

      await expect(DeprecatedSsoService.getConfig('org_network_error')).rejects.toThrow('Network Error');
    });
  });

  describe('putConfig', () => {
    it('calls PUT endpoint with full payload', async () => {
      const mockResponse = {
        data: {
          record: {
            id: 'sso_new',
            provider_type: 'entra_id',
            client_id: 'new-client-id',
            display_name: 'New SSO Config',
            enabled: true,
          },
        },
      };
      mockPut.mockResolvedValueOnce(mockResponse);

      const payload = {
        provider_type: 'entra_id' as const,
        client_id: 'new-client-id',
        client_secret: 'new-secret',
        display_name: 'New SSO Config',
        tenant_id: 'tenant-123',
      };

      const result = await DeprecatedSsoService.putConfig('org_abc', payload);

      expect(mockPut).toHaveBeenCalledWith('/api/organizations/org_abc/sso', payload);
      expect(result).toEqual(mockResponse.data);
    });

    it('uses PUT method for full replacement', async () => {
      const mockResponse = { data: { record: { id: 'sso_123' } } };
      mockPut.mockResolvedValueOnce(mockResponse);

      await DeprecatedSsoService.putConfig('org_test', {
        provider_type: 'entra_id' as const,
        client_id: 'entra-client',
        client_secret: 'entra-secret',
        display_name: 'Entra SSO',
        tenant_id: 'tenant-123',
      });

      expect(mockPut).toHaveBeenCalledTimes(1);
      expect(mockPatch).not.toHaveBeenCalled();
    });
  });

  describe('patchConfig', () => {
    it('calls PATCH endpoint with partial payload', async () => {
      const mockResponse = {
        data: {
          record: {
            id: 'sso_123',
            provider_type: 'entra_id',
            client_id: 'existing-client',
            display_name: 'Updated Name',
            enabled: true,
          },
        },
      };
      mockPatch.mockResolvedValueOnce(mockResponse);

      const payload = {
        display_name: 'Updated Name',
      };

      const result = await DeprecatedSsoService.patchConfig('org_abc', payload);

      expect(mockPatch).toHaveBeenCalledWith('/api/organizations/org_abc/sso', payload);
      expect(result).toEqual(mockResponse.data);
    });

    it('uses PATCH method for partial update', async () => {
      const mockResponse = { data: { record: { id: 'sso_123' } } };
      mockPatch.mockResolvedValueOnce(mockResponse);

      await DeprecatedSsoService.patchConfig('org_test', {
        enabled: false,
      });

      expect(mockPatch).toHaveBeenCalledTimes(1);
      expect(mockPut).not.toHaveBeenCalled();
    });

    it('allows updating without client_secret', async () => {
      const mockResponse = { data: { record: { id: 'sso_123' } } };
      mockPatch.mockResolvedValueOnce(mockResponse);

      const payload = {
        provider_type: 'entra_id' as const,
        client_id: 'updated-client',
        display_name: 'Updated Config',
        // No client_secret - preserves existing
      };

      await DeprecatedSsoService.patchConfig('org_abc', payload);

      expect(mockPatch).toHaveBeenCalledWith('/api/organizations/org_abc/sso', payload);
    });
  });

  describe('saveConfig', () => {
    it('uses PUT when client_secret is provided and non-empty', async () => {
      const mockResponse = { data: { record: { id: 'sso_123' } } };
      mockPut.mockResolvedValueOnce(mockResponse);

      const payload = {
        provider_type: 'entra_id' as const,
        client_id: 'client-id',
        client_secret: 'new-secret-value',
        display_name: 'SSO Config',
        tenant_id: 'tenant-123',
      };

      await DeprecatedSsoService.saveConfig('org_abc', payload);

      expect(mockPut).toHaveBeenCalledWith('/api/organizations/org_abc/sso', payload);
      expect(mockPatch).not.toHaveBeenCalled();
    });

    it('uses PATCH when client_secret is omitted', async () => {
      const mockResponse = { data: { record: { id: 'sso_123' } } };
      mockPatch.mockResolvedValueOnce(mockResponse);

      const payload = {
        provider_type: 'entra_id' as const,
        client_id: 'client-id',
        display_name: 'SSO Config',
        tenant_id: 'tenant-123',
        // No client_secret
      };

      await DeprecatedSsoService.saveConfig('org_abc', payload);

      expect(mockPatch).toHaveBeenCalledWith('/api/organizations/org_abc/sso', payload);
      expect(mockPut).not.toHaveBeenCalled();
    });

    it('uses PATCH when client_secret is empty string', async () => {
      const mockResponse = { data: { record: { id: 'sso_123' } } };
      mockPatch.mockResolvedValueOnce(mockResponse);

      const payload = {
        provider_type: 'entra_id' as const,
        client_id: 'client-id',
        client_secret: '',
        display_name: 'SSO Config',
        tenant_id: 'tenant-123',
      };

      await DeprecatedSsoService.saveConfig('org_abc', payload);

      expect(mockPatch).toHaveBeenCalledWith('/api/organizations/org_abc/sso', payload);
      expect(mockPut).not.toHaveBeenCalled();
    });

    it('returns the same response type regardless of method', async () => {
      const putResponse = { data: { record: { id: 'sso_put', enabled: true } } };
      const patchResponse = { data: { record: { id: 'sso_patch', enabled: false } } };
      mockPut.mockResolvedValueOnce(putResponse);
      mockPatch.mockResolvedValueOnce(patchResponse);

      const putResult = await DeprecatedSsoService.saveConfig('org_1', {
        provider_type: 'entra_id' as const,
        client_id: 'id',
        client_secret: 'secret',
        display_name: 'Test',
        tenant_id: 'tenant-123',
      });

      const patchResult = await DeprecatedSsoService.saveConfig('org_2', {
        display_name: 'Updated',
      });

      expect(putResult).toEqual(putResponse.data);
      expect(patchResult).toEqual(patchResponse.data);
    });
  });

  describe('deleteConfig', () => {
    it('calls correct DELETE endpoint', async () => {
      const mockResponse = {
        data: {
          success: true,
          message: 'SSO configuration deleted',
        },
      };
      mockDelete.mockResolvedValueOnce(mockResponse);

      const result = await DeprecatedSsoService.deleteConfig('org_abc');

      expect(mockDelete).toHaveBeenCalledWith('/api/organizations/org_abc/sso');
      expect(result).toEqual(mockResponse.data);
    });

    it('propagates API errors', async () => {
      mockDelete.mockRejectedValueOnce(new Error('Not found'));

      await expect(DeprecatedSsoService.deleteConfig('org_no_sso')).rejects.toThrow('Not found');
    });
  });

  describe('testConnection', () => {
    it('calls correct POST endpoint with test payload', async () => {
      const mockResponse = {
        data: {
          user_id: 'user_123',
          success: true,
          provider_type: 'entra_id',
          message: 'Connection successful',
          details: {
            issuer: 'https://login.microsoftonline.com/tenant-id/v2.0',
            authorization_endpoint: 'https://login.microsoftonline.com/tenant-id/oauth2/v2.0/authorize',
            token_endpoint: 'https://login.microsoftonline.com/tenant-id/oauth2/v2.0/token',
          },
        },
      };
      mockPost.mockResolvedValueOnce(mockResponse);

      const payload = {
        provider_type: 'entra_id' as const,
        client_id: 'test-client-id',
        tenant_id: 'test-tenant-id',
      };

      const result = await DeprecatedSsoService.testConnection('org_abc', payload);

      expect(mockPost).toHaveBeenCalledWith('/api/organizations/org_abc/sso/test', payload);
      expect(result).toEqual(mockResponse.data);
    });

    it('returns failure response for invalid credentials', async () => {
      const mockResponse = {
        data: {
          user_id: 'user_123',
          success: false,
          provider_type: 'entra_id',
          message: 'Discovery document fetch failed',
          details: {
            error_code: 'discovery_failed',
            http_status: 404,
            url: 'https://login.microsoftonline.com/invalid-tenant/v2.0/.well-known/openid-configuration',
          },
        },
      };
      mockPost.mockResolvedValueOnce(mockResponse);

      const result = await DeprecatedSsoService.testConnection('org_abc', {
        provider_type: 'entra_id' as const,
        client_id: 'test-client',
        tenant_id: 'invalid-tenant',
      });

      expect(result.success).toBe(false);
      expect(result.details.error_code).toBe('discovery_failed');
    });

    // Converted from a GitHub case: issuerless providers were removed from
    // the tenant SSO surface (#3902) — tenant SSO is OIDC/Entra-only.
    it('handles generic OIDC provider validation', async () => {
      const mockResponse = {
        data: {
          user_id: 'user_123',
          success: true,
          provider_type: 'oidc',
          message: 'Discovery document fetched successfully',
          details: {
            issuer: 'https://idp.example.com',
            authorization_endpoint: 'https://idp.example.com/authorize',
            token_endpoint: 'https://idp.example.com/token',
          },
        },
      };
      mockPost.mockResolvedValueOnce(mockResponse);

      const result = await DeprecatedSsoService.testConnection('org_abc', {
        provider_type: 'oidc' as const,
        client_id: 'oidc-client-id',
        issuer: 'https://idp.example.com',
      });

      expect(result.success).toBe(true);
      expect(result.provider_type).toBe('oidc');
      expect(result.details.issuer).toBe('https://idp.example.com');
    });
  });
});
