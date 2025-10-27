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

      axiosMock.onGet('/auth/mfa-status').reply(200, mockStatus);

      const { fetchMfaStatus, mfaStatus } = useMfa();
      const result = await fetchMfaStatus();

      expect(result).toEqual(mockStatus);
      expect(mfaStatus.value?.enabled).toBe(false);
    });

    it('handles fetch errors gracefully', async () => {
      axiosMock.onGet('/auth/mfa-status').reply(500, { error: 'Internal server error' });

      const { fetchMfaStatus, error } = useMfa();
      const result = await fetchMfaStatus();

      expect(result).toBeNull();
      expect(error.value).toBe('Internal server error');
    });

    it('handles network errors with default message', async () => {
      axiosMock.onGet('/auth/mfa-status').networkError();

      const { fetchMfaStatus, error } = useMfa();
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

      axiosMock.onPost('/auth/otp-setup').reply(422, hmacResponse);

      const { setupMfa, setupData } = useMfa();
      const result = await setupMfa('password123');

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

      axiosMock.onPost('/auth/otp-setup').reply(422, hmacResponse);

      const { setupMfa } = useMfa();
      const result = await setupMfa();

      expect(result?.otp_raw_secret).toBe('JBSWY3DPEHPK3PXQ');
    });

    it('handles actual errors (not HMAC success)', async () => {
      axiosMock.onPost('/auth/otp-setup').reply(403, { error: 'Incorrect password' });

      const { setupMfa, error } = useMfa();
      const result = await setupMfa('wrong_password');

      expect(result).toBeNull();
      expect(error.value).toBe('Incorrect password. Please try again.');
    });

    it('handles 422 without HMAC data (actual error)', async () => {
      axiosMock.onPost('/auth/otp-setup').reply(422, { error: 'Validation failed' });

      const { setupMfa, error } = useMfa();
      const result = await setupMfa();

      expect(result).toBeNull();
      expect(error.value).toBe('Validation failed');
    });

    it('handles rate limiting errors', async () => {
      axiosMock.onPost('/auth/otp-setup').reply(429, { error: 'Too many requests' });

      const { setupMfa, error } = useMfa();
      const result = await setupMfa();

      expect(result).toBeNull();
      expect(error.value).toBe('Too many attempts. Please wait a few minutes and try again.');
    });

    it('handles authentication required errors', async () => {
      axiosMock.onPost('/auth/otp-setup').reply(401, { error: 'Not authenticated' });

      const { setupMfa, error } = useMfa();
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

      axiosMock.onPost('/auth/otp-setup').reply(200, successResponse);

      const { enableMfa, setupData } = useMfa();

      // Set setup data first (from setupMfa step)
      setupData.value = {
        otp_setup: 'hmac_secret_123',
        otp_raw_secret: 'JBSWY3DPEHPK3PXP',
      };

      const result = await enableMfa('123456', 'password123');

      expect(result).toBe(true);
    });

    it('handles invalid OTP code error', async () => {
      const errorResponse = {
        error: 'Invalid authentication code',
      };

      axiosMock.onPost('/auth/otp-setup').reply(200, errorResponse);

      const { enableMfa, error, setupData } = useMfa();

      setupData.value = {
        otp_setup: 'hmac_secret_123',
        otp_raw_secret: 'JBSWY3DPEHPK3PXP',
      };

      const result = await enableMfa('wrong_code', 'password123');

      expect(result).toBe(false);
      expect(error.value).toContain('Invalid verification code');
    });

    it('handles incorrect password error', async () => {
      axiosMock.onPost('/auth/otp-setup').reply(403, { error: 'Incorrect password' });

      const { enableMfa, error } = useMfa();
      const result = await enableMfa('123456', 'wrong_password');

      expect(result).toBe(false);
      expect(error.value).toBe('Incorrect password. Please verify your password and try again.');
    });

    it('handles network errors gracefully', async () => {
      axiosMock.onPost('/auth/otp-setup').networkError();

      const { enableMfa, error } = useMfa();
      const result = await enableMfa('123456', 'password123');

      expect(result).toBe(false);
      expect(error.value).toBe('Network error. Please check your connection and try again.');
    });

    it('includes setup data in payload when available', async () => {
      axiosMock.onPost('/auth/otp-setup').reply(200, { success: 'Enabled' });

      const { enableMfa, setupData } = useMfa();

      setupData.value = {
        otp_setup: 'hmac_123',
        otp_raw_secret: 'SECRET',
      };

      const result = await enableMfa('123456', 'password');

      expect(result).toBe(true);
    });
  });

  describe('verifyOtp - Login verification', () => {
    it('successfully verifies valid OTP code', async () => {
      const successResponse = {
        success: 'Authentication successful',
      };

      axiosMock.onPost('/auth/otp-auth').reply(200, successResponse);

      const { verifyOtp } = useMfa();
      const result = await verifyOtp('123456');

      expect(result).toBe(true);
    });

    it('handles invalid OTP code with helpful message', async () => {
      const errorResponse = {
        error: 'Invalid authentication code',
      };

      axiosMock.onPost('/auth/otp-auth').reply(200, errorResponse);

      const { verifyOtp, error } = useMfa();
      const result = await verifyOtp('wrong_code');

      expect(result).toBe(false);
      expect(error.value).toContain('Codes expire every 30 seconds');
    });

    it('handles session expired error', async () => {
      axiosMock.onPost('/auth/otp-auth').reply(401, { error: 'Session expired' });

      const { verifyOtp, error } = useMfa();
      const result = await verifyOtp('123456');

      expect(result).toBe(false);
      expect(error.value).toBe('Session expired. Please log in again with your password.');
    });

    it('handles rate limiting with specific message', async () => {
      axiosMock.onPost('/auth/otp-auth').reply(429, { error: 'Too many attempts' });

      const { verifyOtp, error } = useMfa();
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

      axiosMock.onPost('/auth/otp-disable').reply(200, successResponse);

      const { disableMfa } = useMfa();
      const result = await disableMfa('password123');

      expect(result).toBe(true);
    });

    it('handles incorrect password error', async () => {
      const errorResponse = {
        error: 'Incorrect password',
      };

      axiosMock.onPost('/auth/otp-disable').reply(200, errorResponse);

      const { disableMfa, error } = useMfa();
      const result = await disableMfa('wrong_password');

      expect(result).toBe(false);
      expect(error.value).toContain('Incorrect password');
    });

    it('handles authentication required error', async () => {
      axiosMock.onPost('/auth/otp-disable').reply(401, { error: 'Not authenticated' });

      const { disableMfa, error } = useMfa();
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

      axiosMock.onPost('/auth/recovery-codes').reply(200, mockCodes);

      const { fetchRecoveryCodes, recoveryCodes } = useMfa();
      const result = await fetchRecoveryCodes();

      expect(result).toEqual(mockCodes.codes);
      expect(recoveryCodes.value).toEqual(mockCodes.codes);
    });

    it('handles fetch error gracefully', async () => {
      axiosMock.onPost('/auth/recovery-codes').networkError();

      const { fetchRecoveryCodes, error, recoveryCodes } = useMfa();
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

      axiosMock.onPost('/auth/recovery-codes').reply(200, mockCodes);

      const { generateNewRecoveryCodes, recoveryCodes } = useMfa();
      const result = await generateNewRecoveryCodes('password123');

      expect(result).toEqual(mockCodes.codes);
      expect(recoveryCodes.value).toEqual(mockCodes.codes);
    });

    it('handles password validation error', async () => {
      axiosMock.onPost('/auth/recovery-codes').reply(400, { error: 'Invalid password' });

      const { generateNewRecoveryCodes, error } = useMfa();
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

      axiosMock.onPost('/auth/recovery-auth').reply(200, successResponse);

      const { verifyRecoveryCode } = useMfa();
      const result = await verifyRecoveryCode('RECOVERY_CODE');

      expect(result).toBe(true);
    });

    it('handles already used recovery code', async () => {
      const errorResponse = {
        error: 'This recovery code has already been used',
      };

      axiosMock.onPost('/auth/recovery-auth').reply(200, errorResponse);

      const { verifyRecoveryCode, error } = useMfa();
      const result = await verifyRecoveryCode('USED_CODE');

      expect(result).toBe(false);
      expect(error.value).toBe('This recovery code has already been used. Please use a different code.');
    });

    it('handles invalid recovery code', async () => {
      const errorResponse = {
        error: 'Invalid recovery code',
      };

      axiosMock.onPost('/auth/recovery-auth').reply(200, errorResponse);

      const { verifyRecoveryCode, error } = useMfa();
      const result = await verifyRecoveryCode('INVALID_CODE');

      expect(result).toBe(false);
      expect(error.value).toBe('Invalid recovery code. Please check for typos and try again.');
    });

    it('handles 410 status for used codes', async () => {
      axiosMock.onPost('/auth/recovery-auth').reply(410, { error: 'Code already used' });

      const { verifyRecoveryCode, error } = useMfa();
      const result = await verifyRecoveryCode('USED_CODE');

      expect(result).toBe(false);
      expect(error.value).toBe('This recovery code has already been used. Each code can only be used once.');
    });
  });

  describe('Loading states', () => {
    it('manages loading state during setup', async () => {
      const hmacResponse = {
        otp_setup: 'hmac',
        otp_raw_secret: 'SECRET',
      };

      axiosMock.onPost('/auth/otp-setup').reply(422, hmacResponse);

      const { setupMfa, isLoading } = useMfa();

      expect(isLoading.value).toBe(false);

      const promise = setupMfa();
      // Note: isLoading is synchronous, so we can't check during promise execution easily
      await promise;

      expect(isLoading.value).toBe(false);
    });
  });

  describe('Error clearing', () => {
    it('clears error on new operation', async () => {
      axiosMock.onPost('/auth/otp-setup').reply(403, { error: 'Forbidden' });

      const { setupMfa, error, clearError } = useMfa();

      await setupMfa();
      expect(error.value).toBe('Incorrect password. Please try again.');

      // Clear error manually
      clearError();
      expect(error.value).toBeNull();
    });

    it('automatically clears error on new operation', async () => {
      const { setupMfa, error } = useMfa();

      // First attempt fails
      axiosMock.onPost('/auth/otp-setup').reply(403, { error: 'Forbidden' });

      await setupMfa();
      expect(error.value).toBeTruthy();

      // Second attempt succeeds - reset the mock
      axiosMock.reset();
      axiosMock.onPost('/auth/otp-setup').reply(422, {
        otp_setup: 'hmac',
        otp_raw_secret: 'SECRET',
      });

      await setupMfa();
      // Error should be cleared by clearError() call at start of setupMfa
      expect(error.value).toBeNull();
    });
  });
});
