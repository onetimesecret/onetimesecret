// src/composables/useAuth.ts
import { inject, ref } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAuthStore } from '@/stores/authStore';
import { useCsrfStore } from '@/stores/csrfStore';
import { useNotificationsStore } from '@/stores/notificationsStore';
import {
  isAuthError,
  lockoutErrorSchema,
  type LoginResponse,
  type CreateAccountResponse,
  type LogoutResponse,
  type ResetPasswordRequestResponse,
  type ResetPasswordResponse,
  type VerifyAccountResponse,
  type ChangePasswordResponse,
  type CloseAccountResponse,
} from '@/schemas/api/endpoints/auth';
import {
  loginResponseSchema,
  createAccountResponseSchema,
  logoutResponseSchema,
  resetPasswordRequestResponseSchema,
  resetPasswordResponseSchema,
  verifyAccountResponseSchema,
  changePasswordResponseSchema,
  closeAccountResponseSchema,
} from '@/schemas/api/endpoints/auth';
import type { AxiosInstance } from 'axios';
import type { LockoutStatus } from '@/types/auth';

/**
 * Authentication composable for handling login, signup, logout, and password reset
 *
 * Works with both basic and advanced authentication modes - backend returns
 * Rodauth-compatible JSON format in both cases.
 *
 * @example
 * ```ts
 * const { login, signup, logout, isLoading, error } = useAuth();
 *
 * // Login
 * const success = await login('user@example.com', 'password');
 * if (!success && error.value) {
 *   console.log(error.value); // Display error message
 * }
 * ```
 */
/* eslint-disable max-lines-per-function */
export function useAuth() {
  const $api = inject('api') as AxiosInstance;
  const router = useRouter();
  const { t } = useI18n();
  const authStore = useAuthStore();
  const csrfStore = useCsrfStore();
  const notificationsStore = useNotificationsStore();

  const isLoading = ref(false);
  const error = ref<string | null>(null);
  const fieldError = ref<[string, string] | null>(null);
  const lockoutStatus = ref<LockoutStatus | null>(null);

  /**
   * Clears error state
   */
  function clearErrors() {
    error.value = null;
    fieldError.value = null;
    lockoutStatus.value = null;
  }

  /**
   * Sets error from auth response
   */
  function setError(response: LoginResponse | CreateAccountResponse | ResetPasswordRequestResponse | ResetPasswordResponse | VerifyAccountResponse | ChangePasswordResponse | CloseAccountResponse) {
    if (isAuthError(response)) {
      error.value = response.error;
      fieldError.value = response['field-error'] || null;

      // Try to parse lockout information if present
      try {
        const lockoutParsed = lockoutErrorSchema.safeParse(response);
        if (lockoutParsed.success && lockoutParsed.data.lockout) {
          lockoutStatus.value = lockoutParsed.data.lockout;
        }
      } catch {
        // Lockout info not present, which is fine
      }
    }
  }

  /**
   * Logs in a user with email and password
   *
   * @param email - User's email address
   * @param password - User's password
   * @param rememberMe - Whether to keep session alive (optional)
   * @returns true if login successful, false otherwise
   */
  /* eslint-disable complexity */
  async function login(email: string, password: string, rememberMe: boolean = false): Promise<boolean> {
    clearErrors();
    isLoading.value = true;

    try {
      const response = await $api.post<LoginResponse>('/auth/login', {
        login: email,
        password: password,
        shrimp: csrfStore.shrimp,
        'remember-me': rememberMe,
      });

      const validated = loginResponseSchema.parse(response.data);

      if (isAuthError(validated)) {
        setError(validated);
        return false;
      }

      // Check if MFA is required (Rodauth returns success but with mfa_required flag)
      // In advanced mode with MFA enabled, Rodauth will redirect or indicate MFA is needed
      // The response might have a special flag or the backend might return HTTP 401 with mfa_required
      // For now, we'll check if the response indicates MFA is required
      const responseData = validated as any;
      if (responseData.mfa_required || responseData.requires_otp) {
        // MFA verification needed - redirect to MFA verify page
        await router.push('/mfa-verify');
        return false; // Not fully logged in yet
      }

      // Success - update auth state (this fetches fresh window state)
      await authStore.setAuthenticated(true);

      await router.push('/');
      return true;
    } catch (err: any) {
      // Check if error response indicates MFA is required
      const errorData = err.response?.data;
      if (errorData?.mfa_required || errorData?.requires_otp) {
        await router.push('/mfa-verify');
        return false;
      }

      error.value = err.response?.data?.error || 'Login failed. Please try again.';
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  /**
   * Creates a new user account
   *
   * @param email - User's email address
   * @param password - User's password
   * @param termsAgreed - Whether user agreed to terms (optional)
   * @returns true if account created successfully, false otherwise
   */
  async function signup(email: string, password: string, termsAgreed: boolean = true): Promise<boolean> {
    clearErrors();
    isLoading.value = true;

    try {
      const response = await $api.post<CreateAccountResponse>('/auth/create-account', {
        login: email,
        password: password,
        agree: termsAgreed,
        shrimp: csrfStore.shrimp,
      });

      const validated = createAccountResponseSchema.parse(response.data);

      if (isAuthError(validated)) {
        setError(validated);
        return false;
      }

      // Success - account created but NOT authenticated yet
      // User needs to either verify email or sign in
      // Show success message and navigate to signin page
      notificationsStore.show(validated.success, 'success', 'top');
      await router.push('/signin');
      return true;
    } catch (err: any) {
      error.value = err.response?.data?.error || 'Account creation failed. Please try again.';
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  /**
   * Logs out the current user
   *
   * @returns true if logout successful
   */
  async function logout(): Promise<boolean> {
    clearErrors();
    isLoading.value = true;

    try {
      const response = await $api.post<LogoutResponse>('/auth/logout', {
        shrimp: csrfStore.shrimp,
      });

      const validated = logoutResponseSchema.parse(response.data);

      if (isAuthError(validated)) {
        setError(validated);
        return false;
      }

      // Success - clear auth state and navigate
      await authStore.logout();
      await router.push('/');
      return true;
    } catch (err: any) {
      error.value = err.response?.data?.error || 'Logout failed.';
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  /**
   * Requests a password reset email
   *
   * @param email - User's email address
   * @returns true if request successful
   */
  async function requestPasswordReset(email: string): Promise<boolean> {
    clearErrors();
    isLoading.value = true;

    try {
      const response = await $api.post<ResetPasswordRequestResponse>('/auth/reset-password', {
        login: email,
        shrimp: csrfStore.shrimp,
      });

      const validated = resetPasswordRequestResponseSchema.parse(response.data);

      if (isAuthError(validated)) {
        setError(validated);
        return false;
      }

      return true;
    } catch (err: any) {
      error.value = err.response?.data?.error || 'Password reset request failed.';
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  /**
   * Resets password using a reset key
   *
   * @param key - Password reset key from email
   * @param newPassword - New password
   * @param confirmPassword - Password confirmation
   * @returns true if reset successful
   */
  async function resetPassword(key: string, newPassword: string, confirmPassword: string): Promise<boolean> {
    clearErrors();
    isLoading.value = true;

    try {
      const response = await $api.post<ResetPasswordResponse>(`/auth/reset-password/${key}`, {
        key,
        newp: newPassword,
        newp2: confirmPassword,
        shrimp: csrfStore.shrimp,
      });

      const validated = resetPasswordResponseSchema.parse(response.data);

      if (isAuthError(validated)) {
        setError(validated);
        return false;
      }

      // Success - navigate to signin
      await router.push('/signin');
      return true;
    } catch (err: any) {
      error.value = err.response?.data?.error || 'Password reset failed.';
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  /**
   * Verifies a user account with a verification key
   *
   * @param key - Account verification key from email
   * @returns true if verification successful
   */
  async function verifyAccount(key: string): Promise<boolean> {
    clearErrors();
    isLoading.value = true;

    try {
      const response = await $api.post<VerifyAccountResponse>('/auth/verify-account', {
        key,
        shrimp: csrfStore.shrimp,
      });

      const validated = verifyAccountResponseSchema.parse(response.data);

      if (isAuthError(validated)) {
        setError(validated);
        return false;
      }

      // Success - show notification and navigate to signin
      notificationsStore.show(validated.success, 'success', 'top');
      await router.push('/signin');
      return true;
    } catch (err: any) {
      error.value = err.response?.data?.error || t('web.auth.verify.error');
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  /**
   * Changes the authenticated user's password
   *
   * @param currentPassword - Current password
   * @param newPassword - New password
   * @param confirmPassword - Password confirmation
   * @returns true if password changed successfully
   */
  async function changePassword(
    currentPassword: string,
    newPassword: string,
    confirmPassword: string
  ): Promise<boolean> {
    clearErrors();
    isLoading.value = true;

    try {
      const response = await $api.post<ChangePasswordResponse>('/auth/change-password', {
        password: currentPassword,
        newp: newPassword,
        newp2: confirmPassword,
        shrimp: csrfStore.shrimp,
      });

      const validated = changePasswordResponseSchema.parse(response.data);

      if (isAuthError(validated)) {
        setError(validated);
        return false;
      }

      // Success - show notification
      notificationsStore.show(validated.success, 'success', 'top');
      return true;
    } catch (err: any) {
      error.value = err.response?.data?.error || t('web.auth.change-password.error');
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  /**
   * Closes the authenticated user's account (permanent deletion)
   *
   * @param password - Current password for confirmation
   * @returns true if account closed successfully
   */
  async function closeAccount(password: string): Promise<boolean> {
    clearErrors();
    isLoading.value = true;

    try {
      const response = await $api.post<CloseAccountResponse>('/auth/close-account', {
        password,
        shrimp: csrfStore.shrimp,
      });

      const validated = closeAccountResponseSchema.parse(response.data);

      if (isAuthError(validated)) {
        setError(validated);
        return false;
      }

      // Success - logout and redirect to home
      await authStore.logout();
      await router.push('/');
      return true;
    } catch (err: any) {
      error.value = err.response?.data?.error || t('web.auth.close-account.error');
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  return {
    // State
    isLoading,
    error,
    fieldError,
    lockoutStatus,

    // Actions
    login,
    signup,
    logout,
    requestPasswordReset,
    resetPassword,
    verifyAccount,
    changePassword,
    closeAccount,
    clearErrors,
  };
}
