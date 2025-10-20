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
import { useCsrfStore } from '@/stores/csrfStore';
import { useNotificationsStore } from '@/stores/notificationsStore';

/* eslint-disable max-lines-per-function */
export function useMfa() {
  const $api = inject('api') as AxiosInstance;
  const csrfStore = useCsrfStore();
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
      const response = await $api.get<OtpSetupResponse>('/auth/otp-setup', {
        params: {
          shrimp: csrfStore.shrimp,
        },
      });

      const validated = otpSetupResponseSchema.parse(response.data);

      setupData.value = validated;
      return validated;
    } catch (err: any) {
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
      const response = await $api.post<OtpToggleResponse>('/auth/otp-setup', {
        otp_code: otpCode,
        shrimp: csrfStore.shrimp,
      });

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
        shrimp: csrfStore.shrimp,
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
        shrimp: csrfStore.shrimp,
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
      const response = await $api.get<RecoveryCodesResponse>('/auth/recovery-codes', {
        params: {
          shrimp: csrfStore.shrimp,
        },
      });

      const validated = recoveryCodesResponseSchema.parse(response.data);

      recoveryCodes.value = validated.codes;
      return validated.codes;
    } catch (err: any) {
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
      const response = await $api.post<RecoveryCodesResponse>('/auth/recovery-codes', {
        shrimp: csrfStore.shrimp,
      });

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
        shrimp: csrfStore.shrimp,
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
    clearError,
  };
}
