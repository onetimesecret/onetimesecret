/**
 * Multi-Factor Authentication (MFA) composable
 * Handles OTP setup, verification, disabling, and recovery codes
 */

import { ref, inject } from 'vue';
import type { AxiosInstance } from 'axios';
import {
  otpSetupResponseSchema,
  otpToggleResponseSchema,
  otpVerifyResponseSchema,
  recoveryCodesResponseSchema,
  mfaStatusResponseSchema,
  isAuthError,
  type OtpSetupResponse,
  type OtpToggleResponse,
  type OtpVerifyResponse,
  type RecoveryCodesResponse,
  type MfaStatusResponse,
} from '@/schemas/api/endpoints/auth';
import type { OtpSetupData, MfaStatus } from '@/types/auth';
import { useNotificationsStore } from '@/stores/notificationsStore';

/* eslint-disable max-lines-per-function */
export function useMfa() {
  const $api = inject('api') as AxiosInstance;
  const notificationsStore = useNotificationsStore();

  const isLoading = ref(false);
  const error = ref<string | null>(null);
  const mfaStatus = ref<MfaStatus | null>(null);
  const setupData = ref<OtpSetupData | null>(null);
  const recoveryCodes = ref<string[]>([]);

  /**
   * Clears error state
   */
  function clearError() {
    error.value = null;
  }

  /**
   * Fetches current MFA status
   *
   * @returns MFA status object or null on error
   */
  async function fetchMfaStatus(): Promise<MfaStatus | null> {
    clearError();
    isLoading.value = true;

    try {
      const response = await $api.get<MfaStatusResponse>('/auth/mfa-status');
      const validated = mfaStatusResponseSchema.parse(response.data);

      mfaStatus.value = validated;
      return validated;
    } catch (err: any) {
      console.error('[useMfa] fetchMfaStatus error:', {
        status: err.response?.status,
        statusText: err.response?.statusText,
        data: err.response?.data,
        message: err.message,
      });
      error.value = err.response?.data?.error || 'Failed to load MFA status';
      return null;
    } finally {
      isLoading.value = false;
    }
  }

  /**
   * Initiates MFA setup - gets QR code and secret
   *
   * @returns Setup data with QR code and secret
   */
  async function setupMfa(): Promise<OtpSetupData | null> {
    clearError();
    isLoading.value = true;

    try {
      // POST to /auth/otp-setup without otp_code returns the setup data
      const response = await $api.post<OtpSetupResponse>('/auth/otp-setup', {});

      const validated = otpSetupResponseSchema.parse(response.data);

      // Convert SVG string to data URI for img tag
      if (validated.qr_code && validated.qr_code.startsWith('<svg')) {
        validated.qr_code = `data:image/svg+xml;base64,${btoa(validated.qr_code)}`;
      }

      setupData.value = validated;
      return validated;
    } catch (err: any) {
      console.error('[useMfa] setupMfa error:', {
        status: err.response?.status,
        data: err.response?.data,
      });
      error.value = err.response?.data?.error || 'Failed to initiate MFA setup';
      return null;
    } finally {
      isLoading.value = false;
    }
  }

  /**
   * Completes MFA setup by verifying the OTP code
   *
   * @param otpCode - 6-digit OTP code from authenticator app
   * @returns true if setup successful
   */
  async function enableMfa(otpCode: string): Promise<boolean> {
    clearError();
    isLoading.value = true;

    try {
      // Build request payload
      const payload: Record<string, string> = {
        otp_code: otpCode,
      };

      // Include HMAC parameters if they were provided in setup response
      if (setupData.value?.otp_setup) {
        payload.otp_setup = setupData.value.otp_setup;
      }
      if (setupData.value?.otp_raw_secret) {
        payload.otp_raw_secret = setupData.value.otp_raw_secret;
      }

      const response = await $api.post<OtpToggleResponse>('/auth/otp-setup', payload);

      const validated = otpToggleResponseSchema.parse(response.data);

      if (isAuthError(validated)) {
        error.value = validated.error;
        return false;
      }

      notificationsStore.show('Two-factor authentication has been enabled', 'success', 'top');
      return true;
    } catch (err: any) {
      error.value = err.response?.data?.error || 'Failed to enable MFA';
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  /**
   * Verifies an OTP code (during login or testing)
   *
   * @param otpCode - 6-digit OTP code
   * @returns true if verification successful
   */
  async function verifyOtp(otpCode: string): Promise<boolean> {
    clearError();
    isLoading.value = true;

    try {
      const response = await $api.post<OtpVerifyResponse>('/auth/otp-auth', {
        otp_code: otpCode,
      });

      const validated = otpVerifyResponseSchema.parse(response.data);

      if (isAuthError(validated)) {
        error.value = validated.error;
        return false;
      }

      return true;
    } catch (err: any) {
      error.value = err.response?.data?.error || 'Invalid authentication code';
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  /**
   * Disables MFA for the account
   *
   * @param password - User's password for confirmation
   * @returns true if disable successful
   */
  async function disableMfa(password: string): Promise<boolean> {
    clearError();
    isLoading.value = true;

    try {
      const response = await $api.post<OtpToggleResponse>('/auth/otp-disable', {
        password,
      });

      const validated = otpToggleResponseSchema.parse(response.data);

      if (isAuthError(validated)) {
        error.value = validated.error;
        return false;
      }

      notificationsStore.show('Two-factor authentication has been disabled', 'success', 'top');
      return true;
    } catch (err: any) {
      error.value = err.response?.data?.error || 'Failed to disable MFA';
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  /**
   * Fetches recovery codes
   *
   * @returns Array of recovery codes
   */
  async function fetchRecoveryCodes(): Promise<string[]> {
    clearError();
    isLoading.value = true;

    try {
      // Rodauth with only_json? true requires POST requests with JSON body
      const response = await $api.post<RecoveryCodesResponse>('/auth/recovery-codes', {});

      const validated = recoveryCodesResponseSchema.parse(response.data);

      recoveryCodes.value = validated.codes;
      return validated.codes;
    } catch (err: any) {
      console.error('[useMfa] fetchRecoveryCodes error:', {
        status: err.response?.status,
        data: err.response?.data,
      });
      error.value = err.response?.data?.error || 'Failed to load recovery codes';
      recoveryCodes.value = [];
      return [];
    } finally {
      isLoading.value = false;
    }
  }

  /**
   * Generates new recovery codes (invalidates old ones)
   *
   * @returns Array of new recovery codes
   */
  async function generateNewRecoveryCodes(): Promise<string[]> {
    clearError();
    isLoading.value = true;

    try {
      const response = await $api.post<RecoveryCodesResponse>('/auth/recovery-codes', {});

      const validated = recoveryCodesResponseSchema.parse(response.data);

      recoveryCodes.value = validated.codes;
      notificationsStore.show('New recovery codes have been generated', 'success', 'top');
      return validated.codes;
    } catch (err: any) {
      error.value = err.response?.data?.error || 'Failed to generate recovery codes';
      recoveryCodes.value = [];
      return [];
    } finally {
      isLoading.value = false;
    }
  }

  /**
   * Verifies a recovery code (during login)
   *
   * @param code - Recovery code
   * @returns true if verification successful
   */
  async function verifyRecoveryCode(code: string): Promise<boolean> {
    clearError();
    isLoading.value = true;

    try {
      const response = await $api.post<OtpVerifyResponse>('/auth/recovery-auth', {
        recovery_code: code,
      });

      const validated = otpVerifyResponseSchema.parse(response.data);

      if (isAuthError(validated)) {
        error.value = validated.error;
        return false;
      }

      return true;
    } catch (err: any) {
      error.value = err.response?.data?.error || 'Invalid recovery code';
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  /**
   * Requests MFA recovery via email magic link
   * Used when user is stuck in MFA verification but can't access authenticator
   *
   * @returns true if recovery email sent successfully
   */
  async function requestMfaRecovery(): Promise<boolean> {
    clearError();
    isLoading.value = true;

    try {
      const response = await $api.post<{ success: string } | { error: string }>(
        '/auth/mfa-recovery-request',
        {}
      );

      if ('error' in response.data) {
        error.value = response.data.error;
        return false;
      }

      notificationsStore.show(
        response.data.success || 'Recovery email sent. Check your inbox.',
        'success',
        'top'
      );
      return true;
    } catch (err: any) {
      console.error('[useMfa] requestMfaRecovery error:', {
        status: err.response?.status,
        data: err.response?.data,
      });
      error.value = err.response?.data?.error || 'Failed to send recovery email';
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  return {
    // State
    isLoading,
    error,
    mfaStatus,
    setupData,
    recoveryCodes,

    // Actions
    fetchMfaStatus,
    setupMfa,
    enableMfa,
    verifyOtp,
    disableMfa,
    fetchRecoveryCodes,
    generateNewRecoveryCodes,
    verifyRecoveryCode,
    requestMfaRecovery,
    clearError,
  };
}
