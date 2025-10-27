// src/tests/composables/useMfa.spec.ts
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { useMfa } from '@/composables/useMfa';
import { setupTestPinia } from '../setup';
import type { AxiosInstance } from 'axios';
import type AxiosMockAdapter from 'axios-mock-adapter';

// Mock QR code generation
vi.mock('qrcode', () => ({
  default: {
    toDataURL: vi.fn().mockResolvedValue('data:image/png;base64,mockQrCode'),
  },
}));

describe('useMfa', () => {
  let api: AxiosInstance;
  let axiosMock: AxiosMockAdapter;

  beforeEach(async () => {
    const setup = await setupTestPinia();
    api = setup.api;
    axiosMock = setup.axiosMock!;
  });

  afterEach(() => {
    axiosMock.restore();
    vi.clearAllMocks();
  });

  describe('fetchMfaStatus', () => {
    it('successfully fetches MFA status when enabled', async () => {
      const mockStatus = {
        enabled: true,
        last_used_at: '2024-01-01T12:00:00Z',
        recovery_codes_remaining: 8,
      };

      axiosMock.onGet('/auth/mfa-status').reply(200, mockStatus);

      const { fetchMfaStatus, mfaStatus } = useMfa();
      const result = await fetchMfaStatus();

      expect(result).toEqual(mockStatus);
      expect(mfaStatus.value).toEqual(mockStatus);
    });

    it('successfully fetches MFA status when disabled', async () => {
      const mockStatus = {
        enabled: false,
        last_used_at: null,
        recovery_codes_remaining: 0,
      };

      (mockApi.get as any).mockResolvedValue({ data: mockStatus });

      const { fetchMfaStatus, mfaStatus } = useMfa();
      vi.stubGlobal('inject', () => mockApi);

      const result = await fetchMfaStatus();

      expect(result).toEqual(mockStatus);
      expect(mfaStatus.value?.enabled).toBe(false);
    });

    it('handles fetch errors gracefully', async () => {
      const errorResponse = {
        response: {
          status: 500,
          data: { error: 'Internal server error' },
        },
      };

      (mockApi.get as any).mockRejectedValue(errorResponse);

      const { fetchMfaStatus, error } = useMfa();
      vi.stubGlobal('inject', () => mockApi);

      const result = await fetchMfaStatus();

      expect(result).toBeNull();
      expect(error.value).toBe('Internal server error');
    });

    it('handles network errors with default message', async () => {
      (mockApi.get as any).mockRejectedValue(new Error('Network error'));

      const { fetchMfaStatus, error } = useMfa();
      vi.stubGlobal('inject', () => mockApi);

      const result = await fetchMfaStatus();

      expect(result).toBeNull();
      expect(error.value).toBe('Failed to load MFA status');
    });
  });

  describe('setupMfa - HMAC flow', () => {
    it('handles HMAC setup with 422 response (success path)', async () => {
      const hmacResponse = {
        otp_setup: 'hmac_secret_123',
        otp_raw_secret: 'JBSWY3DPEHPK3PXP',
        error: 'MFA setup requires verification',
      };

      (mockApi.post as any).mockRejectedValue({
        response: {
          status: 422,
          data: hmacResponse,
        },
      });

      const { setupMfa, setupData } = useMfa();
      vi.stubGlobal('inject', () => mockApi);

      const result = await setupMfa('password123');

      expect(mockApi.post).toHaveBeenCalledWith('/auth/otp-setup', { password: 'password123' });
      expect(result).toBeTruthy();
      expect(result?.otp_setup).toBe('hmac_secret_123');
      expect(result?.otp_raw_secret).toBe('JBSWY3DPEHPK3PXP');
      expect(result?.qr_code).toBe('data:image/png;base64,mockQrCode');
      expect(setupData.value?.qr_code).toBeDefined();
    });

    it('handles HMAC setup without password parameter', async () => {
      const hmacResponse = {
        otp_setup: 'hmac_secret_456',
        otp_raw_secret: 'JBSWY3DPEHPK3PXQ',
      };

      (mockApi.post as any).mockRejectedValue({
        response: {
          status: 422,
          data: hmacResponse,
        },
      });

      const { setupMfa } = useMfa();
      vi.stubGlobal('inject', () => mockApi);

      const result = await setupMfa();

      expect(mockApi.post).toHaveBeenCalledWith('/auth/otp-setup', {});
      expect(result?.otp_raw_secret).toBe('JBSWY3DPEHPK3PXQ');
    });

    it('handles actual errors (not HMAC success)', async () => {
      const errorResponse = {
        response: {
          status: 403,
          data: { error: 'Incorrect password' },
        },
      };

      (mockApi.post as any).mockRejectedValue(errorResponse);

      const { setupMfa, error } = useMfa();
      vi.stubGlobal('inject', () => mockApi);

      const result = await setupMfa('wrong_password');

      expect(result).toBeNull();
      expect(error.value).toBe('Incorrect password. Please try again.');
    });

    it('handles 422 without HMAC data (actual error)', async () => {
      const errorResponse = {
        response: {
          status: 422,
          data: { error: 'Validation failed' }, // Missing otp_raw_secret
        },
      };

      (mockApi.post as any).mockRejectedValue(errorResponse);

      const { setupMfa, error } = useMfa();
      vi.stubGlobal('inject', () => mockApi);

      const result = await setupMfa();

      expect(result).toBeNull();
      expect(error.value).toContain('Failed to initiate MFA setup');
    });

    it('handles rate limiting errors', async () => {
      const errorResponse = {
        response: {
          status: 429,
          data: { error: 'Too many requests' },
        },
      };

      (mockApi.post as any).mockRejectedValue(errorResponse);

      const { setupMfa, error } = useMfa();
      vi.stubGlobal('inject', () => mockApi);

      const result = await setupMfa();

      expect(result).toBeNull();
      expect(error.value).toBe('Too many attempts. Please wait a few minutes and try again.');
    });

    it('handles authentication required errors', async () => {
      const errorResponse = {
        response: {
          status: 401,
          data: { error: 'Not authenticated' },
        },
      };

      (mockApi.post as any).mockRejectedValue(errorResponse);

      const { setupMfa, error } = useMfa();
      vi.stubGlobal('inject', () => mockApi);

      const result = await setupMfa();

      expect(result).toBeNull();
      expect(error.value).toBe('Authentication required. Please log in again.');
    });
  });

  describe('enableMfa - Complete setup', () => {
    it('successfully enables MFA with valid OTP', async () => {
      const successResponse = {
        success: 'Two-factor authentication has been enabled',
      };

      (mockApi.post as any).mockResolvedValue({ data: successResponse });

      const { enableMfa, setupData } = useMfa();
      vi.stubGlobal('inject', () => mockApi);

      // Set setup data first (from setupMfa step)
      setupData.value = {
        otp_setup: 'hmac_secret_123',
        otp_raw_secret: 'JBSWY3DPEHPK3PXP',
      };

      const result = await enableMfa('123456', 'password123');

      expect(mockApi.post).toHaveBeenCalledWith('/auth/otp-setup', {
        otp_code: '123456',
        password: 'password123',
        otp_setup: 'hmac_secret_123',
        otp_raw_secret: 'JBSWY3DPEHPK3PXP',
      });
      expect(result).toBe(true);
    });

    it('handles invalid OTP code error', async () => {
      const errorResponse = {
        error: 'Invalid authentication code',
      };

      (mockApi.post as any).mockResolvedValue({ data: errorResponse });

      const { enableMfa, error, setupData } = useMfa();
      vi.stubGlobal('inject', () => mockApi);

      setupData.value = {
        otp_setup: 'hmac_secret_123',
        otp_raw_secret: 'JBSWY3DPEHPK3PXP',
      };

      const result = await enableMfa('wrong_code', 'password123');

      expect(result).toBe(false);
      expect(error.value).toContain('Invalid verification code');
    });

    it('handles incorrect password error', async () => {
      const errorResponse = {
        response: {
          status: 403,
          data: { error: 'Incorrect password' },
        },
      };

      (mockApi.post as any).mockRejectedValue(errorResponse);

      const { enableMfa, error } = useMfa();
      vi.stubGlobal('inject', () => mockApi);

      const result = await enableMfa('123456', 'wrong_password');

      expect(result).toBe(false);
      expect(error.value).toBe('Incorrect password. Please verify your password and try again.');
    });

    it('handles network errors gracefully', async () => {
      (mockApi.post as any).mockRejectedValue(new Error('Network error'));

      const { enableMfa, error } = useMfa();
      vi.stubGlobal('inject', () => mockApi);

      const result = await enableMfa('123456', 'password123');

      expect(result).toBe(false);
      expect(error.value).toBe('Network error. Please check your connection and try again.');
    });

    it('includes setup data in payload when available', async () => {
      (mockApi.post as any).mockResolvedValue({ data: { success: 'Enabled' } });

      const { enableMfa, setupData } = useMfa();
      vi.stubGlobal('inject', () => mockApi);

      setupData.value = {
        otp_setup: 'hmac_123',
        otp_raw_secret: 'SECRET',
      };

      await enableMfa('123456', 'password');

      const callArgs = (mockApi.post as any).mock.calls[0][1];
      expect(callArgs.otp_setup).toBe('hmac_123');
      expect(callArgs.otp_raw_secret).toBe('SECRET');
    });
  });

  describe('verifyOtp - Login verification', () => {
    it('successfully verifies valid OTP code', async () => {
      const successResponse = {
        success: 'Authentication successful',
      };

      (mockApi.post as any).mockResolvedValue({ data: successResponse });

      const { verifyOtp } = useMfa();
      vi.stubGlobal('inject', () => mockApi);

      const result = await verifyOtp('123456');

      expect(mockApi.post).toHaveBeenCalledWith('/auth/otp-auth', {
        otp_code: '123456',
      });
      expect(result).toBe(true);
    });

    it('handles invalid OTP code with helpful message', async () => {
      const errorResponse = {
        error: 'Invalid authentication code',
      };

      (mockApi.post as any).mockResolvedValue({ data: errorResponse });

      const { verifyOtp, error } = useMfa();
      vi.stubGlobal('inject', () => mockApi);

      const result = await verifyOtp('wrong_code');

      expect(result).toBe(false);
      expect(error.value).toContain('Codes expire every 30 seconds');
    });

    it('handles session expired error', async () => {
      const errorResponse = {
        response: {
          status: 401,
          data: { error: 'Session expired' },
        },
      };

      (mockApi.post as any).mockRejectedValue(errorResponse);

      const { verifyOtp, error } = useMfa();
      vi.stubGlobal('inject', () => mockApi);

      const result = await verifyOtp('123456');

      expect(result).toBe(false);
      expect(error.value).toBe('Session expired. Please log in again with your password.');
    });

    it('handles rate limiting with specific message', async () => {
      const errorResponse = {
        response: {
          status: 429,
          data: { error: 'Too many attempts' },
        },
      };

      (mockApi.post as any).mockRejectedValue(errorResponse);

      const { verifyOtp, error } = useMfa();
      vi.stubGlobal('inject', () => mockApi);

      const result = await verifyOtp('123456');

      expect(result).toBe(false);
      expect(error.value).toBe('Too many failed attempts. Please wait 5 minutes before trying again.');
    });
  });

  describe('disableMfa', () => {
    it('successfully disables MFA with correct password', async () => {
      const successResponse = {
        success: 'Two-factor authentication has been disabled',
      };

      (mockApi.post as any).mockResolvedValue({ data: successResponse });

      const { disableMfa } = useMfa();
      vi.stubGlobal('inject', () => mockApi);

      const result = await disableMfa('password123');

      expect(mockApi.post).toHaveBeenCalledWith('/auth/otp-disable', {
        password: 'password123',
      });
      expect(result).toBe(true);
    });

    it('handles incorrect password error', async () => {
      const errorResponse = {
        error: 'Incorrect password',
      };

      (mockApi.post as any).mockResolvedValue({ data: errorResponse });

      const { disableMfa, error } = useMfa();
      vi.stubGlobal('inject', () => mockApi);

      const result = await disableMfa('wrong_password');

      expect(result).toBe(false);
      expect(error.value).toContain('Incorrect password');
    });

    it('handles authentication required error', async () => {
      const errorResponse = {
        response: {
          status: 401,
          data: { error: 'Not authenticated' },
        },
      };

      (mockApi.post as any).mockRejectedValue(errorResponse);

      const { disableMfa, error } = useMfa();
      vi.stubGlobal('inject', () => mockApi);

      const result = await disableMfa('password123');

      expect(result).toBe(false);
      expect(error.value).toBe('Authentication required. Please log in again.');
    });
  });

  describe('fetchRecoveryCodes', () => {
    it('successfully fetches recovery codes', async () => {
      const mockCodes = {
        codes: ['CODE1', 'CODE2', 'CODE3', 'CODE4', 'CODE5'],
      };

      (mockApi.post as any).mockResolvedValue({ data: mockCodes });

      const { fetchRecoveryCodes, recoveryCodes } = useMfa();
      vi.stubGlobal('inject', () => mockApi);

      const result = await fetchRecoveryCodes();

      expect(mockApi.post).toHaveBeenCalledWith('/auth/recovery-codes', {});
      expect(result).toEqual(mockCodes.codes);
      expect(recoveryCodes.value).toEqual(mockCodes.codes);
    });

    it('handles fetch error gracefully', async () => {
      (mockApi.post as any).mockRejectedValue(new Error('Failed'));

      const { fetchRecoveryCodes, error, recoveryCodes } = useMfa();
      vi.stubGlobal('inject', () => mockApi);

      const result = await fetchRecoveryCodes();

      expect(result).toEqual([]);
      expect(recoveryCodes.value).toEqual([]);
      expect(error.value).toBe('Failed to load recovery codes');
    });
  });

  describe('generateNewRecoveryCodes', () => {
    it('successfully generates new recovery codes', async () => {
      const mockCodes = {
        codes: ['NEW1', 'NEW2', 'NEW3', 'NEW4', 'NEW5'],
      };

      (mockApi.post as any).mockResolvedValue({ data: mockCodes });

      const { generateNewRecoveryCodes, recoveryCodes } = useMfa();
      vi.stubGlobal('inject', () => mockApi);

      const result = await generateNewRecoveryCodes('password123');

      expect(mockApi.post).toHaveBeenCalledWith('/auth/recovery-codes', {
        password: 'password123',
      });
      expect(result).toEqual(mockCodes.codes);
      expect(recoveryCodes.value).toEqual(mockCodes.codes);
    });

    it('handles password validation error', async () => {
      const errorResponse = {
        response: {
          data: { error: 'Invalid password' },
        },
      };

      (mockApi.post as any).mockRejectedValue(errorResponse);

      const { generateNewRecoveryCodes, error } = useMfa();
      vi.stubGlobal('inject', () => mockApi);

      const result = await generateNewRecoveryCodes('wrong_password');

      expect(result).toEqual([]);
      expect(error.value).toBe('Invalid password');
    });
  });

  describe('verifyRecoveryCode', () => {
    it('successfully verifies valid recovery code', async () => {
      const successResponse = {
        success: 'Recovery code accepted',
      };

      (mockApi.post as any).mockResolvedValue({ data: successResponse });

      const { verifyRecoveryCode } = useMfa();
      vi.stubGlobal('inject', () => mockApi);

      const result = await verifyRecoveryCode('RECOVERY_CODE');

      expect(mockApi.post).toHaveBeenCalledWith('/auth/recovery-auth', {
        recovery_code: 'RECOVERY_CODE',
      });
      expect(result).toBe(true);
    });

    it('handles already used recovery code', async () => {
      const errorResponse = {
        error: 'This recovery code has already been used',
      };

      (mockApi.post as any).mockResolvedValue({ data: errorResponse });

      const { verifyRecoveryCode, error } = useMfa();
      vi.stubGlobal('inject', () => mockApi);

      const result = await verifyRecoveryCode('USED_CODE');

      expect(result).toBe(false);
      expect(error.value).toBe('This recovery code has already been used. Please use a different code.');
    });

    it('handles invalid recovery code', async () => {
      const errorResponse = {
        error: 'Invalid recovery code',
      };

      (mockApi.post as any).mockResolvedValue({ data: errorResponse });

      const { verifyRecoveryCode, error } = useMfa();
      vi.stubGlobal('inject', () => mockApi);

      const result = await verifyRecoveryCode('INVALID_CODE');

      expect(result).toBe(false);
      expect(error.value).toBe('Invalid recovery code. Please check for typos and try again.');
    });

    it('handles 410 status for used codes', async () => {
      const errorResponse = {
        response: {
          status: 410,
          data: { error: 'Code already used' },
        },
      };

      (mockApi.post as any).mockRejectedValue(errorResponse);

      const { verifyRecoveryCode, error } = useMfa();
      vi.stubGlobal('inject', () => mockApi);

      const result = await verifyRecoveryCode('USED_CODE');

      expect(result).toBe(false);
      expect(error.value).toBe('This recovery code has already been used. Each code can only be used once.');
    });
  });

  describe('Loading states', () => {
    it('manages loading state during setup', async () => {
      (mockApi.post as any).mockRejectedValue({
        response: {
          status: 422,
          data: {
            otp_setup: 'hmac',
            otp_raw_secret: 'SECRET',
          },
        },
      });

      const { setupMfa, isLoading } = useMfa();
      vi.stubGlobal('inject', () => mockApi);

      expect(isLoading.value).toBe(false);

      const promise = setupMfa();
      // Note: isLoading is synchronous, so we can't check during promise execution easily
      await promise;

      expect(isLoading.value).toBe(false);
    });
  });

  describe('Error clearing', () => {
    it('clears error on new operation', async () => {
      // First operation fails
      (mockApi.post as any).mockRejectedValue({
        response: {
          status: 403,
          data: { error: 'Forbidden' },
        },
      });

      const { setupMfa, error, clearError } = useMfa();
      vi.stubGlobal('inject', () => mockApi);

      await setupMfa();
      expect(error.value).toBe('Incorrect password. Please try again.');

      // Clear error manually
      clearError();
      expect(error.value).toBeNull();
    });

    it('automatically clears error on new operation', async () => {
      const { setupMfa, error } = useMfa();
      vi.stubGlobal('inject', () => mockApi);

      // First attempt fails
      (mockApi.post as any).mockRejectedValue({
        response: {
          status: 403,
          data: { error: 'Forbidden' },
        },
      });

      await setupMfa();
      expect(error.value).toBeTruthy();

      // Second attempt succeeds
      (mockApi.post as any).mockRejectedValue({
        response: {
          status: 422,
          data: {
            otp_setup: 'hmac',
            otp_raw_secret: 'SECRET',
          },
        },
      });

      await setupMfa();
      // Error should be cleared by clearError() call at start of setupMfa
      expect(error.value).toBeNull();
    });
  });
});
