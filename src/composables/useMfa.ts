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
import {
  generateQrCode,
  hasHmacSetupData,
  enrichSetupResponse,
} from './helpers/mfaHelpers';

/* eslint-disable max-lines-per-function, complexity */
export function useMfa() {
  const $api = inject('api') as AxiosInstance;
  const notificationsStore = useNotificationsStore();

  const isLoading = ref(false);
  const error = ref<string | null>(null);
  const mfaStatus = ref<MfaStatus | null>(null);
  const setupData = ref<OtpSetupData | null>(null);
  const recoveryCodes = ref<string[]>([]);

  function clearError() {
    error.value = null;
  }

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

  async function setupMfa(password?: string): Promise<OtpSetupData | null> {
    clearError();
    isLoading.value = true;

    try {
      const payload: Record<string, string> = password ? { password } : {};
      const response = await $api.post<OtpSetupResponse>('/auth/otp-setup', payload);
      const validated = otpSetupResponseSchema.parse(response.data);

      if (validated.otp_raw_secret) {
        validated.qr_code = await generateQrCode(validated.otp_raw_secret);
      }

      setupData.value = validated;
      return validated;
    } catch (err: any) {
      const errorData = err.response?.data;
      if (err.response?.status === 422 && errorData && hasHmacSetupData(errorData)) {
        const hmacData = await enrichSetupResponse(errorData);
        if (hmacData) {
          setupData.value = hmacData;
          return hmacData;
        }
      }

      console.error('[useMfa] setupMfa error:', {
        status: err.response?.status,
        data: errorData,
      });
      error.value = errorData?.error || 'Failed to initiate MFA setup';
      return null;
    } finally {
      isLoading.value = false;
    }
  }

  async function enableMfa(otpCode: string, password: string): Promise<boolean> {
    clearError();
    isLoading.value = true;

    try {
      const payload: Record<string, string> = { otp_code: otpCode, password };

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

  async function fetchRecoveryCodes(): Promise<string[]> {
    clearError();
    isLoading.value = true;

    try {
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

  async function generateNewRecoveryCodes(password: string): Promise<string[]> {
    clearError();
    isLoading.value = true;

    try {
      const response = await $api.post<RecoveryCodesResponse>('/auth/recovery-codes', { password });
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

  return {
    isLoading,
    error,
    mfaStatus,
    setupData,
    recoveryCodes,
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
