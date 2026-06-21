// src/tests/services/signin-config.service.spec.ts
//
// Tests for SigninConfigService domain-scoped methods.
//
// Issue: #3383 - Per-domain signin configuration
//
// Run:
//   pnpm test src/tests/services/signin-config.service.spec.ts

import { describe, it, expect, beforeEach, vi } from 'vitest';

// Use vi.hoisted to properly hoist mock functions before vi.mock
const { mockGet, mockPut, mockDelete } = vi.hoisted(() => ({
  mockGet: vi.fn(),
  mockPut: vi.fn(),
  mockDelete: vi.fn(),
}));

vi.mock('@/api', () => ({
  createApi: () => ({
    get: mockGet,
    put: mockPut,
    delete: mockDelete,
  }),
}));

// Import after mocking
import { SigninConfigService } from '@/services/signin-config.service';
import axios from 'axios';

describe('SigninConfigService', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockGet.mockReset();
    mockPut.mockReset();
    mockDelete.mockReset();
  });

  const domainExtId = 'dm_test_domain_456';
  const baseUrl = `/api/domains/${domainExtId}/signin-config`;

  // Wire-format response (pre-transform: timestamps are numbers)
  const mockSigninConfigResponse = {
    record: {
      domain_id: domainExtId,
      enabled: true,
      signin_enabled: true,
      restrict_to: null,
      email_auth_enabled: true,
      sso_enabled: false,
      created_at: 1234567890,
      updated_at: 1234567890,
    },
  };

  // ==========================================================================
  // getConfigForDomain
  // ==========================================================================

  describe('getConfigForDomain', () => {
    it('fetches signin config successfully', async () => {
      mockGet.mockResolvedValueOnce({ data: mockSigninConfigResponse });

      const result = await SigninConfigService.getConfigForDomain(domainExtId);

      expect(mockGet).toHaveBeenCalledWith(baseUrl);
      expect(result.record).toBeDefined();
      expect(result.record?.enabled).toBe(true);
      expect(result.record?.domain_id).toBe(domainExtId);
    });

    it('returns null record on 404 (no config exists)', async () => {
      const axiosError = {
        response: { status: 404 },
        isAxiosError: true,
      };
      // Make axios.isAxiosError recognize it
      vi.spyOn(axios, 'isAxiosError').mockReturnValueOnce(true);
      mockGet.mockRejectedValueOnce(axiosError);

      const result = await SigninConfigService.getConfigForDomain(domainExtId);

      expect(result.record).toBeNull();
    });

    it('returns null record on graceful parse failure', async () => {
      // Malformed response that won't pass schema validation
      mockGet.mockResolvedValueOnce({ data: { record: { bad: 'data' } } });

      const result = await SigninConfigService.getConfigForDomain(domainExtId);

      expect(result.record).toBeNull();
    });

    it('rethrows non-404 errors', async () => {
      const serverError = new Error('Internal Server Error');
      mockGet.mockRejectedValueOnce(serverError);

      await expect(
        SigninConfigService.getConfigForDomain(domainExtId)
      ).rejects.toThrow('Internal Server Error');
    });

    it('transforms timestamps to Date objects', async () => {
      mockGet.mockResolvedValueOnce({ data: mockSigninConfigResponse });

      const result = await SigninConfigService.getConfigForDomain(domainExtId);

      expect(result.record?.created_at).toBeInstanceOf(Date);
      expect(result.record?.updated_at).toBeInstanceOf(Date);
    });

    it('preserves restrict_to value from response', async () => {
      const restricted = {
        record: {
          ...mockSigninConfigResponse.record,
          restrict_to: 'sso',
        },
      };
      mockGet.mockResolvedValueOnce({ data: restricted });

      const result = await SigninConfigService.getConfigForDomain(domainExtId);

      expect(result.record?.restrict_to).toBe('sso');
    });
  });

  // ==========================================================================
  // putConfigForDomain
  // ==========================================================================

  describe('putConfigForDomain', () => {
    it('sends PUT request with correct URL and payload', async () => {
      mockPut.mockResolvedValueOnce({ data: mockSigninConfigResponse });

      const payload = {
        enabled: true,
        signin_enabled: true,
        restrict_to: null as null,
        email_auth_enabled: true,
        sso_enabled: false,
      };

      await SigninConfigService.putConfigForDomain(domainExtId, payload);

      expect(mockPut).toHaveBeenCalledWith(baseUrl, payload);
    });

    it('returns validated record from response', async () => {
      mockPut.mockResolvedValueOnce({ data: mockSigninConfigResponse });

      const payload = {
        enabled: true,
        signin_enabled: true,
        restrict_to: null as null,
        email_auth_enabled: true,
        sso_enabled: false,
      };

      const result = await SigninConfigService.putConfigForDomain(domainExtId, payload);

      expect(result.record).toBeDefined();
      expect(result.record?.enabled).toBe(true);
      expect(result.record?.created_at).toBeInstanceOf(Date);
    });

    it('throws on invalid response schema (strictParse)', async () => {
      mockPut.mockResolvedValueOnce({ data: { bad: 'response' } });

      const payload = {
        enabled: true,
        signin_enabled: true,
      };

      await expect(
        SigninConfigService.putConfigForDomain(domainExtId, payload)
      ).rejects.toThrow();
    });
  });

  // ==========================================================================
  // deleteConfigForDomain
  // ==========================================================================

  describe('deleteConfigForDomain', () => {
    it('sends DELETE request with correct URL', async () => {
      mockDelete.mockResolvedValueOnce({ data: { success: true } });

      await SigninConfigService.deleteConfigForDomain(domainExtId);

      expect(mockDelete).toHaveBeenCalledWith(baseUrl);
    });

    it('returns validated delete response', async () => {
      mockDelete.mockResolvedValueOnce({
        data: { success: true, message: 'Signin config removed' },
      });

      const result = await SigninConfigService.deleteConfigForDomain(domainExtId);

      expect(result.success).toBe(true);
      expect(result.message).toBe('Signin config removed');
    });

    it('throws on invalid delete response', async () => {
      mockDelete.mockResolvedValueOnce({ data: { invalid: true } });

      await expect(
        SigninConfigService.deleteConfigForDomain(domainExtId)
      ).rejects.toThrow();
    });
  });
});
