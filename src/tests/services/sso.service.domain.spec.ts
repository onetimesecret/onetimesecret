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

import { describe, it, expect, beforeEach, afterEach, vi, type MockInstance } from 'vitest';
import { ZodError } from 'zod';

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

  // Complete mock config that passes schema validation
  // Must include all required fields from domainSsoConfigCanonical
  const mockDomainSsoConfig = {
    record: {
      domain_id: domainExtId,
      provider_type: 'entra_id',
      display_name: 'Test Domain SSO',
      client_id: 'test-client-id',
      client_secret_masked: '********',
      tenant_id: 'test-tenant-id',
      issuer: null,  // Required nullable field
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
      // Full valid responses required for schema validation
      const putResponse = {
        data: {
          record: {
            domain_id: 'dm_put',
            provider_type: 'google',
            display_name: 'PUT Config',
            client_id: 'put-client-id',
            client_secret_masked: '********',
            tenant_id: null,
            issuer: null,
            enabled: true,
            allowed_domains: [],
            requires_domain_filter: false,
            idp_controls_access: true,
            created_at: 1234567890,
            updated_at: 1234567890,
          },
        },
      };
      const patchResponse = {
        data: {
          record: {
            domain_id: 'dm_patch',
            provider_type: 'google',
            display_name: 'PATCH Config',
            client_id: 'patch-client-id',
            client_secret_masked: '********',
            tenant_id: null,
            issuer: null,
            enabled: false,
            allowed_domains: [],
            requires_domain_filter: false,
            idp_controls_access: true,
            created_at: 1234567890,
            updated_at: 1234567890,
          },
        },
      };
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

      // After schema validation, response is wrapped in { record }
      expect(putResult.record?.domain_id).toBe('dm_put');
      expect(putResult.record?.enabled).toBe(true);
      expect(patchResult.record?.domain_id).toBe('dm_patch');
      expect(patchResult.record?.enabled).toBe(false);
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

  // ==========================================================================
  // Schema Validation Tests
  // ==========================================================================

  describe('schema validation', () => {
    // These tests verify behavior when schema validation is added to SsoService.
    // Schema validation should:
    // - Transform timestamps from Unix epoch to Date objects
    // - Gracefully degrade to { record: null } for GET failures
    // - Throw ZodError for PUT/PATCH/DELETE failures

    let consoleErrorSpy: MockInstance;

    beforeEach(() => {
      consoleErrorSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
    });

    afterEach(() => {
      consoleErrorSpy.mockRestore();
    });

    describe('getConfigForDomain', () => {
      it('parses valid response and transforms timestamps', async () => {
        // Valid API response with Unix epoch timestamps
        const validApiResponse = {
          record: {
            domain_id: domainExtId,
            provider_type: 'entra_id',
            display_name: 'Test Domain SSO',
            client_id: 'test-client-id',
            client_secret_masked: '********',
            tenant_id: 'test-tenant-id',
            issuer: null,
            enabled: true,
            allowed_domains: ['example.com'],
            requires_domain_filter: false,
            idp_controls_access: true,
            created_at: 1234567890,
            updated_at: 1234567890,
          },
          user_id: 'user_123',
          shrimp: 'csrf_token',
        };
        mockGet.mockResolvedValueOnce({ data: validApiResponse });

        const result = await SsoService.getConfigForDomain(domainExtId);

        expect(result.record).not.toBeNull();
        expect(result.record?.provider_type).toBe('entra_id');
        // Schema transforms Unix epoch to Date objects
        expect(result.record?.created_at).toBeInstanceOf(Date);
        expect(result.record?.updated_at).toBeInstanceOf(Date);
      });

      it('returns null record on schema validation failure (graceful degradation)', async () => {
        // Malformed response: missing required fields
        const malformedResponse = {
          record: {
            domain_id: domainExtId,
            // Missing: provider_type, display_name, client_id, etc.
          },
        };
        mockGet.mockResolvedValueOnce({ data: malformedResponse });

        // getConfigForDomain uses gracefulParse which degrades to { record: null }
        const result = await SsoService.getConfigForDomain(domainExtId);

        expect(result.record).toBeNull();
        // gracefulParse logs errors in dev/test mode
        expect(consoleErrorSpy).toHaveBeenCalled();
      });

      it('degrades to null record when API returns null (schema parse failure)', async () => {
        // Note: The domainSsoConfigSchema doesn't allow null record, so this
        // triggers graceful degradation, not a pass-through
        const nullRecordResponse = {
          record: null,
          user_id: 'user_123',
        };
        mockGet.mockResolvedValueOnce({ data: nullRecordResponse });

        const result = await SsoService.getConfigForDomain(domainExtId);

        // Graceful degradation returns { record: null }
        expect(result.record).toBeNull();
      });

      it('handles response with extra fields (should be passed through or stripped)', async () => {
        const responseWithExtraFields = {
          record: {
            ...mockDomainSsoConfig.record,
            unexpected_field: 'should be ignored or passed through',
            another_extra: 12345,
          },
        };
        mockGet.mockResolvedValueOnce({ data: responseWithExtraFields });

        const result = await SsoService.getConfigForDomain(domainExtId);

        // Schema should strip unknown fields or pass them through (based on config)
        expect(result.record?.domain_id).toBe(domainExtId);
      });
    });

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

      it('parses valid response and returns typed result', async () => {
        const validResponse = {
          record: {
            domain_id: domainExtId,
            provider_type: 'entra_id',
            display_name: 'New Domain SSO',
            client_id: 'new-client-id',
            client_secret_masked: '********',
            tenant_id: 'new-tenant-id',
            issuer: null,
            enabled: true,
            allowed_domains: ['newdomain.com'],
            requires_domain_filter: false,
            idp_controls_access: true,
            created_at: 1234567890,
            updated_at: 1234567890,
          },
        };
        mockPut.mockResolvedValueOnce({ data: validResponse });

        const result = await SsoService.putConfigForDomain(domainExtId, createPayload);

        expect(result.record).toBeDefined();
        expect(result.record?.provider_type).toBe('entra_id');
      });

      it('throws ZodError on schema validation failure (strict mode)', async () => {
        // Malformed response missing required fields
        const malformedResponse = {
          record: {
            domain_id: domainExtId,
            provider_type: 'invalid_provider', // Invalid enum value
          },
        };
        mockPut.mockResolvedValueOnce({ data: malformedResponse });

        // PUT uses strictParse which throws ZodError on validation failure
        await expect(
          SsoService.putConfigForDomain(domainExtId, createPayload)
        ).rejects.toThrow(ZodError);
      });

      it('propagates ZodError to caller for handling', async () => {
        const responseWithWrongTypes = {
          record: {
            domain_id: domainExtId,
            provider_type: 'entra_id',
            display_name: 'Test',
            client_id: 'client-id',
            client_secret_masked: '********',
            enabled: 'yes', // Should be boolean, not string
            created_at: 'not-a-timestamp', // Should be number
            updated_at: 1234567890,
          },
        };
        mockPut.mockResolvedValueOnce({ data: responseWithWrongTypes });

        // strictParse throws on type mismatches - caller can catch and handle
        await expect(
          SsoService.putConfigForDomain(domainExtId, createPayload)
        ).rejects.toThrow(ZodError);
      });
    });

    describe('patchConfigForDomain', () => {
      const updatePayload = {
        display_name: 'Updated Domain SSO',
        enabled: false,
      };

      it('parses valid partial update response', async () => {
        const validResponse = {
          record: {
            ...mockDomainSsoConfig.record,
            display_name: 'Updated Domain SSO',
            enabled: false,
            updated_at: Date.now() / 1000,
          },
        };
        mockPatch.mockResolvedValueOnce({ data: validResponse });

        const result = await SsoService.patchConfigForDomain(domainExtId, updatePayload);

        expect(result.record?.display_name).toBe('Updated Domain SSO');
        expect(result.record?.enabled).toBe(false);
      });

      it('throws ZodError on schema validation failure (strict mode)', async () => {
        const malformedResponse = {
          record: {
            // Response missing domain_id and other required fields
            display_name: 'Updated',
          },
        };
        mockPatch.mockResolvedValueOnce({ data: malformedResponse });

        // PATCH uses strictParse which throws on validation failure
        await expect(
          SsoService.patchConfigForDomain(domainExtId, updatePayload)
        ).rejects.toThrow(ZodError);
      });
    });

    describe('deleteConfigForDomain', () => {
      it('parses valid deletion response', async () => {
        const deleteResponse = { success: true, message: 'SSO configuration deleted' };
        mockDelete.mockResolvedValueOnce({ data: deleteResponse });

        const result = await SsoService.deleteConfigForDomain(domainExtId);

        expect(result.success).toBe(true);
        expect(result.message).toBe('SSO configuration deleted');
      });

      it('throws ZodError on schema validation failure (strict mode)', async () => {
        // Response missing required 'success' field
        const malformedResponse = {
          message: 'Deleted',
          // Missing: success
        };
        mockDelete.mockResolvedValueOnce({ data: malformedResponse });

        // DELETE uses strictParse which throws on validation failure
        await expect(
          SsoService.deleteConfigForDomain(domainExtId)
        ).rejects.toThrow(ZodError);
      });

      it('throws ZodError on wrong type for success field', async () => {
        const wrongTypeResponse = {
          success: 'true', // String instead of boolean
        };
        mockDelete.mockResolvedValueOnce({ data: wrongTypeResponse });

        // strictParse rejects type mismatches
        await expect(
          SsoService.deleteConfigForDomain(domainExtId)
        ).rejects.toThrow(ZodError);
      });
    });

    describe('edge cases', () => {
      it('gracefully degrades on empty record object', async () => {
        const emptyRecordResponse = {
          record: {},
        };
        mockGet.mockResolvedValueOnce({ data: emptyRecordResponse });

        // gracefulParse returns { record: null } on validation failure
        const result = await SsoService.getConfigForDomain(domainExtId);
        expect(result.record).toBeNull();
        expect(consoleErrorSpy).toHaveBeenCalled();
      });

      it('gracefully degrades on deeply nested malformed data', async () => {
        const nestedMalformedResponse = {
          record: {
            domain_id: domainExtId,
            provider_type: 'entra_id',
            display_name: 'Test',
            client_id: 'client-id',
            client_secret_masked: '********',
            enabled: true,
            allowed_domains: [123, null, { invalid: true }], // Should be string[]
            created_at: 1234567890,
            updated_at: 1234567890,
          },
        };
        mockGet.mockResolvedValueOnce({ data: nestedMalformedResponse });

        // Malformed array elements cause validation failure -> graceful degradation
        const result = await SsoService.getConfigForDomain(domainExtId);
        expect(result.record).toBeNull();
      });

      it('transforms timestamp edge values to Date objects', async () => {
        const edgeTimestampResponse = {
          record: {
            ...mockDomainSsoConfig.record,
            created_at: 0, // Unix epoch start
            updated_at: 2147483647, // Max 32-bit signed int (Y2K38)
          },
        };
        mockGet.mockResolvedValueOnce({ data: edgeTimestampResponse });

        const result = await SsoService.getConfigForDomain(domainExtId);

        // Schema transforms Unix epoch numbers to Date objects
        expect(result.record?.created_at).toEqual(new Date(0));
        expect(result.record?.updated_at).toEqual(new Date(2147483647 * 1000));
      });

      it('handles null values in nullable fields and normalizes nullish to defaults', async () => {
        const nullableFieldsResponse = {
          record: {
            domain_id: domainExtId,
            provider_type: 'entra_id',
            display_name: 'Test',
            client_id: 'client-id',
            client_secret_masked: '********',
            tenant_id: null, // Nullable
            issuer: null, // Nullable
            enabled: true,
            allowed_domains: null, // Nullish, should normalize to []
            requires_domain_filter: false,
            idp_controls_access: true,
            created_at: 1234567890,
            updated_at: 1234567890,
          },
        };
        mockGet.mockResolvedValueOnce({ data: nullableFieldsResponse });

        const result = await SsoService.getConfigForDomain(domainExtId);

        expect(result.record?.tenant_id).toBeNull();
        expect(result.record?.issuer).toBeNull();
        // Schema transforms null -> [] for allowed_domains
        expect(result.record?.allowed_domains).toEqual([]);
      });

      it('transforms null client_id to empty string for form safety', async () => {
        // This is the key fix: client_id is nullable in the API contract but
        // the form component calls .trim() on it, so null must become ''
        const nullClientIdResponse = {
          record: {
            domain_id: domainExtId,
            provider_type: 'entra_id',
            display_name: 'Test',
            client_id: null, // API returns null
            client_secret_masked: '********',
            tenant_id: 'tenant-123',
            issuer: null,
            enabled: true,
            allowed_domains: [],
            requires_domain_filter: false,
            idp_controls_access: true,
            created_at: 1234567890,
            updated_at: 1234567890,
          },
        };
        mockGet.mockResolvedValueOnce({ data: nullClientIdResponse });

        const result = await SsoService.getConfigForDomain(domainExtId);

        // Schema transforms null -> '' for client_id (required field)
        expect(result.record?.client_id).toBe('');
        // Verify .trim() is now safe to call
        expect(() => result.record?.client_id.trim()).not.toThrow();
      });

      it('normalizes undefined nullish fields to their defaults', async () => {
        const undefinedFieldsResponse = {
          record: {
            domain_id: domainExtId,
            provider_type: 'entra_id',
            display_name: 'Test',
            client_id: 'client-id',
            client_secret_masked: '********',
            enabled: true,
            requires_domain_filter: false,
            idp_controls_access: true,
            created_at: 1234567890,
            updated_at: 1234567890,
            // tenant_id, issuer, allowed_domains all undefined (nullish)
          },
        };
        mockGet.mockResolvedValueOnce({ data: undefinedFieldsResponse });

        const result = await SsoService.getConfigForDomain(domainExtId);

        expect(result.record).not.toBeNull();
        // Schema transforms normalize undefined -> null for nullable fields
        expect(result.record?.tenant_id).toBeNull();
        expect(result.record?.issuer).toBeNull();
        // Schema transforms normalize undefined -> [] for allowed_domains
        expect(result.record?.allowed_domains).toEqual([]);
      });
    });
  });
});
