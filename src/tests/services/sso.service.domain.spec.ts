// src/tests/services/sso.service.domain.spec.ts

/**
 * Tests for SsoService domain-scoped methods
 *
 * Issue: #2786 - Per-domain SSO configuration
 *
 * These tests verify the frontend service methods for managing
 * per-domain SSO configurations.
 *
 * Run:
 *   pnpm test src/tests/services/sso.service.domain.spec.ts
 */

import { describe, it, expect, beforeEach, vi } from 'vitest';

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

describe('SsoService domain methods', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockGet.mockReset();
    mockPut.mockReset();
    mockPatch.mockReset();
    mockPost.mockReset();
    mockDelete.mockReset();
  });

  // Test data
  // Note: Domain SSO endpoints are at /api/domains/:domainExtId/sso (no org prefix)
  const domainExtId = 'dm_test_domain_456';
  const baseUrl = `/api/domains/${domainExtId}/sso`;

  const mockDomainSsoConfig = {
    record: {
      domain_id: domainExtId,
      provider_type: 'entra_id',
      display_name: 'Test Domain SSO',
      client_id: 'test-client-id',
      client_secret_masked: '********',
      tenant_id: 'test-tenant-id',
      enabled: true,
      allowed_domains: ['example.com'],
      requires_domain_filter: false,
      idp_controls_access: true,
      created_at: 1234567890,
      updated_at: 1234567890,
    },
  };

  // ==========================================================================
  // getConfigForDomain Tests
  // ==========================================================================

  describe('getConfigForDomain', () => {
    it('fetches domain SSO config successfully', async () => {
      mockGet.mockResolvedValueOnce({ data: mockDomainSsoConfig });

      const result = await SsoService.getConfigForDomain(domainExtId);

      expect(mockGet).toHaveBeenCalledWith(baseUrl);
      expect(result.record).toBeDefined();
      expect(result.record?.provider_type).toBe('entra_id');
      expect(result.record?.domain_id).toBe(domainExtId);
    });

    it('returns null record on 404 (no config exists)', async () => {
      const axiosError = {
        response: { status: 404 },
        isAxiosError: true,
      };
      mockGet.mockRejectedValueOnce(axiosError);

      const result = await SsoService.getConfigForDomain(domainExtId);

      expect(mockGet).toHaveBeenCalledWith(baseUrl);
      expect(result.record).toBeNull();
    });

    it('throws on authorization error (403)', async () => {
      const axiosError = {
        response: { status: 403 },
        isAxiosError: true,
        message: 'Forbidden',
      };
      mockGet.mockRejectedValueOnce(axiosError);

      await expect(SsoService.getConfigForDomain(domainExtId)).rejects.toEqual(axiosError);
    });

    it('throws on server error (500)', async () => {
      const axiosError = {
        response: { status: 500 },
        isAxiosError: true,
        message: 'Internal Server Error',
      };
      mockGet.mockRejectedValueOnce(axiosError);

      await expect(SsoService.getConfigForDomain(domainExtId)).rejects.toEqual(axiosError);
    });

    it('includes client_secret_masked in response', async () => {
      mockGet.mockResolvedValueOnce({ data: mockDomainSsoConfig });

      const result = await SsoService.getConfigForDomain(domainExtId);

      expect(result.record?.client_secret_masked).toBe('********');
    });

    it('propagates network errors without response', async () => {
      const networkError = new Error('Network Error');
      mockGet.mockRejectedValueOnce(networkError);

      await expect(SsoService.getConfigForDomain(domainExtId)).rejects.toThrow('Network Error');
    });
  });

  // ==========================================================================
  // putConfigForDomain Tests
  // ==========================================================================

  describe('putConfigForDomain', () => {
    const createPayload = {
      provider_type: 'entra_id' as const,
      display_name: 'New Domain SSO',
      client_id: 'new-client-id',
      client_secret: 'new-client-secret',
      tenant_id: 'new-tenant-id',
      enabled: true,
      allowed_domains: ['newdomain.com'],
    };

    it('creates domain SSO config with PUT', async () => {
      mockPut.mockResolvedValueOnce({ data: mockDomainSsoConfig });

      const result = await SsoService.putConfigForDomain(domainExtId, createPayload);

      expect(mockPut).toHaveBeenCalledWith(baseUrl, createPayload);
      expect(result.record).toBeDefined();
    });

    it('sends client_secret in request body', async () => {
      mockPut.mockResolvedValueOnce({ data: mockDomainSsoConfig });

      await SsoService.putConfigForDomain(domainExtId, createPayload);

      expect(mockPut).toHaveBeenCalledWith(
        baseUrl,
        expect.objectContaining({ client_secret: 'new-client-secret' })
      );
    });

    it('handles validation errors (422)', async () => {
      const validationError = {
        response: { status: 422 },
        isAxiosError: true,
        message: 'Validation failed',
      };
      mockPut.mockRejectedValueOnce(validationError);

      await expect(
        SsoService.putConfigForDomain(domainExtId, { ...createPayload, tenant_id: undefined })
      ).rejects.toEqual(validationError);
    });
  });

  // ==========================================================================
  // patchConfigForDomain Tests
  // ==========================================================================

  describe('patchConfigForDomain', () => {
    const updatePayload = {
      display_name: 'Updated Domain SSO',
      enabled: false,
      // Note: client_secret intentionally omitted to test preservation
    };

    it('updates domain SSO config with PATCH', async () => {
      const updatedConfig = {
        ...mockDomainSsoConfig,
        record: { ...mockDomainSsoConfig.record, ...updatePayload },
      };
      mockPatch.mockResolvedValueOnce({ data: updatedConfig });

      const result = await SsoService.patchConfigForDomain(domainExtId, updatePayload);

      expect(mockPatch).toHaveBeenCalledWith(baseUrl, updatePayload);
      expect(result.record?.display_name).toBe('Updated Domain SSO');
      expect(result.record?.enabled).toBe(false);
    });

    it('uses PATCH method for partial update', async () => {
      mockPatch.mockResolvedValueOnce({ data: mockDomainSsoConfig });

      await SsoService.patchConfigForDomain(domainExtId, updatePayload);

      expect(mockPatch).toHaveBeenCalledTimes(1);
      expect(mockPut).not.toHaveBeenCalled();
    });

    it('allows updating without client_secret (preserves existing)', async () => {
      mockPatch.mockResolvedValueOnce({ data: mockDomainSsoConfig });

      const payload = {
        provider_type: 'entra_id' as const,
        client_id: 'updated-client',
        display_name: 'Updated Config',
        // No client_secret - preserves existing
      };

      await SsoService.patchConfigForDomain(domainExtId, payload);

      expect(mockPatch).toHaveBeenCalledWith(baseUrl, payload);
    });
  });

  // ==========================================================================
  // saveConfigForDomain Tests (auto PUT/PATCH selection)
  // ==========================================================================

  describe('saveConfigForDomain', () => {
    it('uses PUT when client_secret is provided and non-empty', async () => {
      mockPut.mockResolvedValueOnce({ data: mockDomainSsoConfig });

      const payload = {
        provider_type: 'entra_id' as const,
        display_name: 'New Config',
        client_id: 'client-id',
        client_secret: 'new-secret-value',
        tenant_id: 'tenant-123',
      };

      await SsoService.saveConfigForDomain(domainExtId, payload);

      expect(mockPut).toHaveBeenCalledWith(baseUrl, payload);
      expect(mockPatch).not.toHaveBeenCalled();
    });

    it('uses PATCH when client_secret is omitted', async () => {
      mockPatch.mockResolvedValueOnce({ data: mockDomainSsoConfig });

      const payload = {
        provider_type: 'entra_id' as const,
        display_name: 'Updated Config',
        client_id: 'client-id',
        tenant_id: 'tenant-123',
        // Note: no client_secret
      };

      await SsoService.saveConfigForDomain(domainExtId, payload);

      expect(mockPatch).toHaveBeenCalledWith(baseUrl, payload);
      expect(mockPut).not.toHaveBeenCalled();
    });

    it('uses PATCH when client_secret is empty string', async () => {
      mockPatch.mockResolvedValueOnce({ data: mockDomainSsoConfig });

      const payload = {
        provider_type: 'entra_id' as const,
        display_name: 'Updated Config',
        client_id: 'client-id',
        client_secret: '', // Empty string should trigger PATCH
        tenant_id: 'tenant-123',
      };

      await SsoService.saveConfigForDomain(domainExtId, payload);

      expect(mockPatch).toHaveBeenCalledWith(baseUrl, payload);
      expect(mockPut).not.toHaveBeenCalled();
    });

    it('returns the same response type regardless of method', async () => {
      const putResponse = { data: { record: { domain_id: 'dm_put', enabled: true } } };
      const patchResponse = { data: { record: { domain_id: 'dm_patch', enabled: false } } };
      mockPut.mockResolvedValueOnce(putResponse);
      mockPatch.mockResolvedValueOnce(patchResponse);

      const putResult = await SsoService.saveConfigForDomain('dm_1', {
        provider_type: 'google' as const,
        client_id: 'id',
        client_secret: 'secret',
        display_name: 'Test',
      });

      const patchResult = await SsoService.saveConfigForDomain('dm_2', {
        display_name: 'Updated',
      });

      expect(putResult).toEqual(putResponse.data);
      expect(patchResult).toEqual(patchResponse.data);
    });
  });

  // ==========================================================================
  // deleteConfigForDomain Tests
  // ==========================================================================

  describe('deleteConfigForDomain', () => {
    it('deletes domain SSO config', async () => {
      const deleteResponse = { success: true, message: 'SSO configuration deleted' };
      mockDelete.mockResolvedValueOnce({ data: deleteResponse });

      const result = await SsoService.deleteConfigForDomain(domainExtId);

      expect(mockDelete).toHaveBeenCalledWith(baseUrl);
      expect(result.success).toBe(true);
    });

    it('propagates API errors', async () => {
      mockDelete.mockRejectedValueOnce(new Error('Not found'));

      await expect(SsoService.deleteConfigForDomain(domainExtId)).rejects.toThrow('Not found');
    });
  });

  // ==========================================================================
  // testConnectionForDomain Tests
  // ==========================================================================

  describe('testConnectionForDomain', () => {
    const testPayload = {
      provider_type: 'entra_id' as const,
      client_id: 'test-client-id',
      tenant_id: 'test-tenant-id',
    };

    const successResponse = {
      user_id: 'user_123',
      success: true,
      provider_type: 'entra_id',
      message: 'Connection successful',
      details: {
        issuer: 'https://login.microsoftonline.com/test-tenant-id/v2.0',
        authorization_endpoint: 'https://login.microsoftonline.com/test-tenant-id/oauth2/v2.0/authorize',
        token_endpoint: 'https://login.microsoftonline.com/test-tenant-id/oauth2/v2.0/token',
      },
    };

    it('tests SSO connection successfully', async () => {
      mockPost.mockResolvedValueOnce({ data: successResponse });

      const result = await SsoService.testConnectionForDomain(domainExtId, testPayload);

      expect(mockPost).toHaveBeenCalledWith(`${baseUrl}/test`, testPayload);
      expect(result.success).toBe(true);
      expect(result.details.issuer).toBeDefined();
    });

    it('returns failure response for invalid credentials', async () => {
      const failureResponse = {
        user_id: 'user_123',
        success: false,
        provider_type: 'entra_id',
        message: 'Discovery document fetch failed',
        details: {
          error_code: 'discovery_failed',
          http_status: 404,
          url: 'https://login.microsoftonline.com/invalid-tenant/v2.0/.well-known/openid-configuration',
        },
      };
      mockPost.mockResolvedValueOnce({ data: failureResponse });

      const result = await SsoService.testConnectionForDomain(domainExtId, {
        provider_type: 'entra_id' as const,
        client_id: 'test-client',
        tenant_id: 'invalid-tenant',
      });

      expect(result.success).toBe(false);
      expect(result.details.error_code).toBe('discovery_failed');
    });

    it('handles GitHub provider validation', async () => {
      const githubResponse = {
        user_id: 'user_123',
        success: true,
        provider_type: 'github',
        message: 'Client ID format is valid',
        details: {
          client_id_format: 'valid',
          note: 'GitHub does not support OIDC discovery',
        },
      };
      mockPost.mockResolvedValueOnce({ data: githubResponse });

      const result = await SsoService.testConnectionForDomain(domainExtId, {
        provider_type: 'github' as const,
        client_id: 'Iv1.abc123def456',
      });

      expect(result.success).toBe(true);
      expect(result.provider_type).toBe('github');
      expect(result.details.client_id_format).toBe('valid');
    });
  });

  // ==========================================================================
  // URL Construction Tests
  // ==========================================================================

  describe('URL construction', () => {
    it('constructs correct URL with domain ID', async () => {
      mockGet.mockResolvedValueOnce({ data: mockDomainSsoConfig });

      await SsoService.getConfigForDomain(domainExtId);

      expect(mockGet).toHaveBeenCalledWith(`/api/domains/${domainExtId}/sso`);
    });

    it('handles special characters in domain IDs', async () => {
      const specialDomainId = 'dm_test-domain_456';
      mockGet.mockResolvedValueOnce({ data: mockDomainSsoConfig });

      await SsoService.getConfigForDomain(specialDomainId);

      expect(mockGet).toHaveBeenCalledWith(`/api/domains/${specialDomainId}/sso`);
    });
  });
});
