/**
 * Multi-Factor Authentication (MFA) composable
 * Handles OTP setup, verification, disabling, and recovery codes
 *
 * MFA Flow Overview:
 * =================
 * 1. Setup Flow (HMAC-based):
 *    a) User requests setup → POST /auth/otp-setup {} (empty payload)
 *    b) Backend returns 422 with otp_setup (HMAC'd secret) + otp_raw_secret
 *    c) Frontend generates QR code from otp_raw_secret
 *    d) User scans QR code and enters OTP
 *    e) POST /auth/otp-setup {otp_code, otp_setup, otp_raw_secret, password}
 *    f) Backend validates and enables MFA → 200 success
 *
 * 2. Verification Flow:
 *    - POST /auth/otp-auth {otp_code}
 *    - Returns success/error based on OTP validity
 *
 * 3. Recovery Flow:
 *    - POST /auth/recovery-auth {recovery_code}
 *    - One-time use codes for account recovery
 *
 * State Transitions:
 * ==================
 * - Not authenticated → No MFA actions available
 * - Authenticated, no MFA → Can setup MFA
 * - Authenticated, MFA setup in progress → Collecting secrets
 * - Authenticated, MFA verification in progress → Validating OTP
 * - Authenticated, MFA complete → Protected account
 * - Authenticated, MFA recovery → Using backup codes
 *
 * HMAC Setup Note:
 * ================
 * When Rodauth's OTP HMAC feature is enabled, the backend returns a 422 status
 * on the first setup request with just the secrets (no success message). This is
 * INTENTIONAL behavior in JSON-only mode. The frontend treats this 422 as success
 * and proceeds to QR code generation.
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
import { generateQrCode, hasHmacSetupData, enrichSetupResponse } from './helpers/mfaHelpers';
import { useAsyncHandler, createError } from '@/composables/useAsyncHandler';
import type { ApplicationError } from '@/schemas/errors';

/* eslint-disable max-lines-per-function, complexity */
export function useMfa() {
  const $api = inject('api') as AxiosInstance;
  const notificationsStore = useNotificationsStore();

  const isLoading = ref(false);
  const error = ref<string | null>(null);
  const mfaStatus = ref<MfaStatus | null>(null);
  const setupData = ref<OtpSetupData | null>(null);
  const recoveryCodes = ref<string[]>([]);

  // Configure async handler for auth-specific pattern (no auto-notify)
  const { wrap } = useAsyncHandler({
    // Don't auto-notify - MFA shows errors inline
    notify: false,
    setLoading: (loading) => (isLoading.value = loading),
    onError: (err: ApplicationError) => {
      // IMPORTANT: Clear all error state first to prevent stale data
      error.value = null;

      // Provide user-friendly error messages based on error code
      const code = err.code;
      const originalMessage = err.message;

      // Map common HTTP status codes to user-friendly messages
      if (code === 401) {
        error.value = originalMessage.includes('Session')
          ? originalMessage // Keep specific session messages
          : 'Incorrect password. Please try again.';
      } else if (code === 403) {
        error.value = 'Not authorized.';
      } else if (code === 404) {
        error.value = 'Recovery code not found. Please verify you entered it correctly.';
      } else if (code === 410) {
        error.value = 'This recovery code has already been used. Each code can only be used once.';
      } else if (code === 429) {
        error.value = 'Too many failed attempts. Please wait 5 minutes before trying again.';
      } else {
        error.value = err.message;
      }
    },
  });

  function clearError() {
    error.value = null;
  }

  /**
   * Fetches current MFA status for authenticated user
   *
   * State: Authenticated → Authenticated (MFA status loaded)
   *
   * @returns MfaStatus object with enabled state and recovery code count, or null on error
   *
   * Response includes:
   * - enabled: Whether MFA is active
   * - last_used_at: Timestamp of last successful MFA verification (null if never used)
   * - recovery_codes_remaining: Count of unused recovery codes
   */
  async function fetchMfaStatus(): Promise<MfaStatus | null> {
    clearError();

    const result = await wrap(async () => {
      const response = await $api.get<MfaStatusResponse>('/auth/mfa-status');
      const validated = mfaStatusResponseSchema.parse(response.data);

      mfaStatus.value = validated;
      return validated;
    });

    return result ?? null;
  }

  /**
   * Initiates MFA setup - Step 1 of 2-step HMAC process
   *
   * State: Authenticated (no MFA) → Authenticated (MFA setup in progress)
   *
   * HMAC Setup Flow:
   * ----------------
   * When HMAC is enabled (default for security), this function handles the first
   * step of OTP setup. The backend returns a 422 status with the secrets, which
   * is the EXPECTED behavior in JSON-only mode (not an error).
   *
   * @param password - Optional password for authentication (may be required by backend)
   * @returns OtpSetupData with QR code and secrets, or null on actual errors
   *
   * Success path (HMAC enabled):
   * - POST /auth/otp-setup {} (empty or with password)
   * - Receive 422 with {otp_setup, otp_raw_secret, error: "..."}
   * - Generate QR code from otp_raw_secret
   * - Return enriched setup data for user to scan
   *
   * The 422 status is treated as success because it contains the necessary
   * setup data. A true error would not include otp_raw_secret.
   */
  async function setupMfa(password?: string): Promise<OtpSetupData | null> {
    clearError();

    try {
      const result = await wrap(async () => {
        const payload: Record<string, string> = password ? { password } : {};
        const response = await $api.post<OtpSetupResponse>('/auth/otp-setup', payload);
        const validated = otpSetupResponseSchema.parse(response.data);

        // Standard response (non-HMAC mode): includes QR code data directly
        if (validated.otp_raw_secret) {
          validated.qr_code = await generateQrCode(
            'Onetime Secret',
            'user@example.com', // TODO: Get from authenticated user
            validated.otp_raw_secret
          );
        }

        setupData.value = validated;
        return validated;
      });

      return result ?? null;
    } catch (err: any) {
      // HMAC Setup Success Path: 422 with secrets (not a real error)
      // When HMAC is enabled, backend returns 422 with otp_setup and otp_raw_secret
      // This is expected behavior, not an actual error
      const errorData = err.response?.data;

      if (err.response?.status === 422 && errorData && hasHmacSetupData(errorData)) {
        const hmacData = await enrichSetupResponse(errorData);
        if (hmacData) {
          setupData.value = hmacData;
          error.value = null; // Clear the error set by wrap()
          return hmacData; // Success: proceed to QR code display
        }
      }

      // For other errors, re-throw to let wrap() handle them
      throw err;
    }
  }

  /**
   * Completes MFA setup - Step 2 of 2-step HMAC process
   *
   * State: Authenticated (MFA setup in progress) → Authenticated (MFA complete)
   *
   * This function verifies the user's OTP code and enables MFA on their account.
   * It sends the HMAC'd secret (otp_setup) and raw secret (otp_raw_secret) back
   * to the backend for validation.
   *
   * @param otpCode - 6-digit code from authenticator app
   * @param password - User's password for security confirmation
   * @returns true if MFA was successfully enabled, false otherwise
   *
   * Required fields in payload:
   * - otp_code: The 6-digit TOTP code
   * - password: User's account password
   * - otp_setup: HMAC'd secret from setupMfa (when HMAC enabled)
   * - otp_raw_secret: Raw secret from setupMfa (when HMAC enabled)
   *
   * Success response: { success: "..." }
   * Error response: { error: "...", field-error: [...] }
   */
  async function enableMfa(otpCode: string, password: string): Promise<boolean> {
    clearError();

    const result = await wrap(async () => {
      const payload: Record<string, string> = { otp_code: otpCode, password };

      // Include HMAC'd secret and raw secret from setup step
      if (setupData.value?.otp_setup) {
        payload.otp_setup = setupData.value.otp_setup;
      }
      if (setupData.value?.otp_raw_secret) {
        payload.otp_raw_secret = setupData.value.otp_raw_secret;
      }

      const response = await $api.post<OtpToggleResponse>('/auth/otp-setup', payload);
      const validated = otpToggleResponseSchema.parse(response.data);

      // Check for error response (validation failure)
      if (isAuthError(validated)) {
        const errorMsg = validated.error.toLowerCase();
        const message =
          errorMsg.includes('invalid') || errorMsg.includes('incorrect')
            ? 'Invalid verification code. Please check your authenticator app and try again.'
            : validated.error;

        throw createError(message, 'human', 'error', {
          'field-error': validated['field-error'],
        });
      }

      notificationsStore.show('Two-factor authentication has been enabled', 'success', 'top');
      return true;
    });

    return result ?? false;
  }

  /**
   * Verifies OTP code during login (post-password authentication)
   *
   * State: Authenticated (MFA required) → Authenticated (MFA complete)
   *
   * This is called AFTER successful password authentication when MFA is enabled.
   * The user must provide a valid OTP code to complete the login process.
   *
   * @param otpCode - 6-digit TOTP code from authenticator app
   * @returns true if OTP is valid, false otherwise
   *
   * Common error cases:
   * - Invalid code: Wrong digits or expired code
   * - Rate limiting: Too many failed attempts
   * - Session expired: Need to re-authenticate with password
   */
  async function verifyOtp(otpCode: string): Promise<boolean> {
    clearError();

    const result = await wrap(async () => {
      const response = await $api.post<OtpVerifyResponse>('/auth/otp-auth', {
        otp_code: otpCode,
      });

      const validated = otpVerifyResponseSchema.parse(response.data);

      if (isAuthError(validated)) {
        const errorMsg = validated.error.toLowerCase();
        const message =
          errorMsg.includes('invalid') || errorMsg.includes('incorrect')
            ? 'Invalid code. Codes expire every 30 seconds. Try the latest code from your authenticator app.'
            : validated.error;

        throw createError(message, 'human', 'error');
      }

      return true;
    });

    return result ?? false;
  }

  /**
   * Disables MFA on user account
   *
   * State: Authenticated (MFA complete) → Authenticated (no MFA)
   *
   * Removes MFA requirement from account. User will only need password for future logins.
   * Recovery codes are invalidated when MFA is disabled.
   *
   * @param password - User's password for security confirmation
   * @returns true if MFA was successfully disabled, false otherwise
   *
   * Security note: Always requires password confirmation to prevent unauthorized MFA removal.
   */
  async function disableMfa(password: string): Promise<boolean> {
    clearError();

    const result = await wrap(async () => {
      const response = await $api.post<OtpToggleResponse>('/auth/otp-disable', {
        password,
      });

      const validated = otpToggleResponseSchema.parse(response.data);

      if (isAuthError(validated)) {
        const message = validated.error.toLowerCase().includes('password')
          ? 'Incorrect password. Please verify your password and try again.'
          : validated.error;

        throw createError(message, 'human', 'error');
      }

      notificationsStore.show('Two-factor authentication has been disabled', 'success', 'top');
      return true;
    });

    return result ?? false;
  }

  /**
   * Fetches existing recovery codes (view only, no regeneration)
   *
   * State: Authenticated (MFA complete) → Authenticated (viewing codes)
   *
   * Retrieves the current set of recovery codes. Does not generate new codes.
   *
   * @returns Array of recovery code strings
   *
   * Note: Recovery codes are only available after MFA is enabled. This endpoint
   * shows the codes that were generated during setup or last regeneration.
   */
  async function fetchRecoveryCodes(): Promise<string[]> {
    clearError();

    const result = await wrap(async () => {
      const response = await $api.post<RecoveryCodesResponse>('/auth/recovery-codes', {});
      const validated = recoveryCodesResponseSchema.parse(response.data);

      recoveryCodes.value = validated.codes;
      return validated.codes;
    });

    if (!result) {
      recoveryCodes.value = [];
    }

    return result ?? [];
  }

  /**
   * Generates new recovery codes, invalidating old ones
   *
   * State: Authenticated (MFA complete) → Authenticated (new codes generated)
   *
   * Creates a fresh set of recovery codes. All previous codes become invalid.
   * User should save the new codes immediately.
   *
   * @param password - User's password for security confirmation
   * @returns Array of new recovery code strings
   *
   * Security note: Old codes are immediately invalidated. If the user loses
   * the new codes without saving them, they must regenerate again or risk
   * being locked out if they lose their authenticator device.
   */
  async function generateNewRecoveryCodes(password: string): Promise<string[]> {
    clearError();

    const result = await wrap(async () => {
      const response = await $api.post<RecoveryCodesResponse>('/auth/recovery-codes', { password });
      const validated = recoveryCodesResponseSchema.parse(response.data);

      recoveryCodes.value = validated.codes;
      return validated.codes;
    });

    if (result) {
      notificationsStore.show('New recovery codes have been generated', 'success', 'top');
    } else {
      recoveryCodes.value = [];
    }

    return result ?? [];
  }

  /**
   * Verifies recovery code for account access
   *
   * State: Authenticated (MFA recovery) → Authenticated (MFA complete)
   *
   * Used when user cannot access their authenticator app. Each recovery code
   * can only be used once. After use, the code is marked as consumed.
   *
   * @param code - Recovery code string (generated during MFA setup)
   * @returns true if code is valid and unused, false otherwise
   *
   * Common error cases:
   * - Invalid code: Not in the system or typo
   * - Already used: Code was previously consumed
   * - Expired session: Need to re-authenticate with password first
   *
   * Important: User should regenerate recovery codes after using several,
   * to maintain a healthy supply of backup codes.
   */
  async function verifyRecoveryCode(code: string): Promise<boolean> {
    clearError();

    const result = await wrap(async () => {
      const response = await $api.post<OtpVerifyResponse>('/auth/recovery-auth', {
        recovery_code: code,
      });

      const validated = otpVerifyResponseSchema.parse(response.data);

      if (isAuthError(validated)) {
        const errorMsg = validated.error.toLowerCase();
        let message = validated.error;

        if (errorMsg.includes('used') || errorMsg.includes('consumed')) {
          message = 'This recovery code has already been used. Please use a different code.';
        } else if (errorMsg.includes('invalid') || errorMsg.includes('not found')) {
          message = 'Invalid recovery code. Please check for typos and try again.';
        }

        throw createError(message, 'human', 'error');
      }

      return true;
    });

    return result ?? false;
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
