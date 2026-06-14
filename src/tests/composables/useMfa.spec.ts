// src/tests/composables/useMfa.spec.ts

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { useMfa } from '@/shared/composables/useMfa';
import { setupTestPinia } from '../setup';
import QRCode from 'qrcode';
import type AxiosMockAdapter from 'axios-mock-adapter';

// Mock QR code generation
vi.mock('qrcode', () => ({
  default: {
    toDataURL: vi.fn().mockResolvedValue('data:image/png;base64,mockQrCode'),
  },
}));

// Mock vue-i18n to provide translation function
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key: string) => key, // Return the key itself for testing
  }),
}));

describe('useMfa', () => {
  let axiosMock: AxiosMockAdapter;

  beforeEach(async () => {
    const setup = await setupTestPinia();
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
        recovery_codes_limit: 4,
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
        recovery_codes_limit: 4,
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
      expect(error.value).toBe('web.auth.security.internal_error');
    });

    it('handles network errors with default message', async () => {
      axiosMock.onGet('/auth/mfa-status').networkError();

      const { fetchMfaStatus, error } = useMfa();
      const result = await fetchMfaStatus();

      expect(result).toBeNull();
      expect(error.value).toBe('web.auth.security.internal_error');
    });
  });

  describe('setupMfa - HMAC flow', () => {
    it('handles HMAC setup with 422 response (success path)', async () => {
      const hmacResponse = {
        otp_setup: 'hmac_secret_123',
        otp_raw_secret: 'JBSWY3DPEHPK3PXP',
        provisioning_uri:
          'otpauth://totp/OneTimeSecret:test@example.com?secret=hmac_secret_123&issuer=OneTimeSecret',
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
      // The QR must be rendered from the backend's provisioning_uri verbatim,
      // not reconstructed client-side from a secret (issue #3431).
      expect(QRCode.toDataURL).toHaveBeenCalledWith(hmacResponse.provisioning_uri);
    });

    it('handles HMAC setup without password parameter', async () => {
      const hmacResponse = {
        otp_setup: 'hmac_secret_456',
        otp_raw_secret: 'JBSWY3DPEHPK3PXQ',
        provisioning_uri:
          'otpauth://totp/OneTimeSecret:test@example.com?secret=hmac_secret_456&issuer=OneTimeSecret',
      };

      axiosMock.onPost('/auth/otp-setup').reply(422, hmacResponse);

      const { setupMfa } = useMfa();
      const result = await setupMfa();

      expect(result?.otp_raw_secret).toBe('JBSWY3DPEHPK3PXQ');
      expect(result?.qr_code).toBe('data:image/png;base64,mockQrCode');
      // QR is rendered from the backend's provisioning_uri verbatim, even on
      // the no-password path (issue #3431).
      expect(QRCode.toDataURL).toHaveBeenCalledWith(hmacResponse.provisioning_uri);
    });

    it('handles actual errors (not HMAC success)', async () => {
      axiosMock.onPost('/auth/otp-setup').reply(403, { error: 'Incorrect password' });

      const { setupMfa, error } = useMfa();
      const result = await setupMfa('wrong_password');

      expect(result).toBeNull();
      expect(error.value).toBe('web.auth.security.internal_error');
    });

    it('handles 422 without HMAC data (actual error)', async () => {
      axiosMock.onPost('/auth/otp-setup').reply(422, { error: 'Validation failed' });

      const { setupMfa, error } = useMfa();
      const result = await setupMfa();

      expect(result).toBeNull();
      expect(error.value).toBe('web.auth.security.internal_error');
    });

    it('surfaces an error when HMAC 422 omits provisioning_uri (version skew)', async () => {
      // Both HMAC secrets present (passes hasHmacSetupData) but no
      // provisioning_uri — e.g. the SPA is deployed ahead of the backend hook.
      // Must fail visibly rather than advance to a blank scan step (#3431).
      axiosMock.onPost('/auth/otp-setup').reply(422, {
        otp_setup: 'hmac_secret',
        otp_raw_secret: 'JBSWY3DPEHPK3PXP',
      });

      const { setupMfa, error } = useMfa();
      const result = await setupMfa();

      expect(result).toBeNull();
      expect(error.value).toBe('web.auth.security.internal_error');
    });

    it('surfaces an error when a 200 setup response omits provisioning_uri', async () => {
      // Non-HMAC 200 path with setup secrets but no provisioning_uri: no
      // scannable QR can be rendered (the SPA must not reconstruct it, #3431),
      // so setupMfa must fail visibly instead of populating setupData with an
      // undefined qr_code (the blank-scan-step gap). Mirrors the 422 skew case.
      axiosMock.onPost('/auth/otp-setup').reply(200, {
        otp_setup: 'plain_secret',
        otp_raw_secret: 'JBSWY3DPEHPK3PXP',
      });

      const { setupMfa, setupData, error } = useMfa();
      const result = await setupMfa();

      expect(result).toBeNull();
      expect(setupData.value).toBeNull();
      expect(error.value).toBe('web.auth.security.internal_error');
      expect(QRCode.toDataURL).not.toHaveBeenCalled();
    });

    it('renders the QR on a 200 setup response that includes provisioning_uri', async () => {
      // Non-HMAC 200 happy path: provisioning_uri present, so renderSetupQr
      // produces the QR and setupData is populated (no blank-scan-step).
      const setupResponse = {
        otp_setup: 'plain_secret',
        otp_raw_secret: 'JBSWY3DPEHPK3PXP',
        provisioning_uri:
          'otpauth://totp/OTS:test@example.com?secret=plain_secret&issuer=OTS',
      };

      axiosMock.onPost('/auth/otp-setup').reply(200, setupResponse);

      const { setupMfa, setupData } = useMfa();
      const result = await setupMfa();

      expect(result?.qr_code).toBe('data:image/png;base64,mockQrCode');
      expect(setupData.value?.qr_code).toBe('data:image/png;base64,mockQrCode');
      expect(QRCode.toDataURL).toHaveBeenCalledWith(setupResponse.provisioning_uri);
    });

    it('handles rate limiting errors', async () => {
      axiosMock.onPost('/auth/otp-setup').reply(429, { error: 'Too many requests' });

      const { setupMfa, error } = useMfa();
      const result = await setupMfa();

      expect(result).toBeNull();
      expect(error.value).toBe('web.auth.security.internal_error');
    });

    it('handles authentication required errors', async () => {
      axiosMock.onPost('/auth/otp-setup').reply(401, { error: 'Not authenticated' });

      const { setupMfa, error } = useMfa();
      const result = await setupMfa();

      expect(result).toBeNull();
      expect(error.value).toBe('web.auth.security.internal_error');
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
      expect(error.value).toBe('web.auth.mfa.invalid_code');
    });

    it('handles incorrect password error', async () => {
      axiosMock.onPost('/auth/otp-setup').reply(403, { error: 'Incorrect password' });

      const { enableMfa, error } = useMfa();
      const result = await enableMfa('123456', 'wrong_password');

      expect(result).toBe(false);
      expect(error.value).toBe('web.auth.security.internal_error');
    });

    it('handles network errors gracefully', async () => {
      axiosMock.onPost('/auth/otp-setup').networkError();

      const { enableMfa, error } = useMfa();
      const result = await enableMfa('123456', 'password123');

      expect(result).toBe(false);
      expect(error.value).toBe('web.auth.security.internal_error');
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
      expect(error.value).toBe('web.auth.mfa.invalid_code');
    });

    it('handles session expired error', async () => {
      axiosMock.onPost('/auth/otp-auth').reply(401, { error: 'Session expired' });

      const { verifyOtp, error } = useMfa();
      const result = await verifyOtp('123456');

      expect(result).toBe(false);
      expect(error.value).toBe('web.auth.security.internal_error');
    });

    it('handles rate limiting with specific message', async () => {
      axiosMock.onPost('/auth/otp-auth').reply(429, { error: 'Too many attempts' });

      const { verifyOtp, error } = useMfa();
      const result = await verifyOtp('123456');

      expect(result).toBe(false);
      expect(error.value).toBe('web.auth.security.internal_error');
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
      expect(error.value).toBe('web.auth.security.authentication_failed');
    });

    it('handles authentication required error', async () => {
      axiosMock.onPost('/auth/otp-disable').reply(401, { error: 'Not authenticated' });

      const { disableMfa, error } = useMfa();
      const result = await disableMfa('password123');

      expect(result).toBe(false);
      expect(error.value).toBe('web.auth.security.internal_error');
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
      expect(error.value).toBe('web.auth.security.internal_error');
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
      expect(error.value).toBe('web.auth.security.internal_error');
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
      expect(error.value).toBe('web.auth.security.recovery_code_used');
    });

    it('handles invalid recovery code', async () => {
      const errorResponse = {
        error: 'Invalid recovery code',
      };

      axiosMock.onPost('/auth/recovery-auth').reply(200, errorResponse);

      const { verifyRecoveryCode, error } = useMfa();
      const result = await verifyRecoveryCode('INVALID_CODE');

      expect(result).toBe(false);
      expect(error.value).toBe('web.auth.security.recovery_code_not_found');
    });

    it('handles 410 status for used codes', async () => {
      axiosMock.onPost('/auth/recovery-auth').reply(410, { error: 'Code already used' });

      const { verifyRecoveryCode, error } = useMfa();
      const result = await verifyRecoveryCode('USED_CODE');

      expect(result).toBe(false);
      expect(error.value).toBe('web.auth.security.internal_error');
    });
  });

  describe('Loading states', () => {
    it('manages loading state during setup', async () => {
      const hmacResponse = {
        otp_setup: 'hmac',
        otp_raw_secret: 'SECRET',
        provisioning_uri: 'otpauth://totp/test@example.com?secret=hmac&issuer=test',
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
      expect(error.value).toBe('web.auth.security.internal_error');

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
        provisioning_uri: 'otpauth://totp/test@example.com?secret=hmac&issuer=test',
      });

      await setupMfa();
      // Error should be cleared by clearError() call at start of setupMfa
      expect(error.value).toBeNull();
    });
  });
});
