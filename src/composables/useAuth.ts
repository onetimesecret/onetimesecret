// src/composables/useAuth.ts
import { inject, ref } from 'vue';
import { useRouter } from 'vue-router';
import { useAuthStore } from '@/stores/authStore';
import { useCsrfStore } from '@/stores/csrfStore';
import { useNotificationsStore } from '@/stores/notificationsStore';
import {
  useAsyncHandler,
  createError,
  type AsyncHandlerOptions,
} from '@/composables/useAsyncHandler';
import {
  isAuthError,
  requiresMfa,
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

  // Configure useAsyncHandler for auth-specific needs
  const defaultAsyncHandlerOptions: AsyncHandlerOptions = {
    // Don't auto-notify - auth errors are shown inline in forms
    notify: false,
    setLoading: (loading) => (isLoading.value = loading),
    onError: (err) => {
      // Clear all error state first to avoid stale data from previous errors
      error.value = null;
      fieldError.value = null;
      lockoutStatus.value = null;

      // Set new error state
      error.value = err.message;

      // Field errors from Rodauth response
      if (err.details?.['field-error']) {
        fieldError.value = err.details['field-error'] as [string, string];
      }

      // Lockout status from Rodauth response
      if (err.details?.lockout) {
        lockoutStatus.value = err.details.lockout as LockoutStatus;
      }
    },
  };

  const { wrap } = useAsyncHandler(defaultAsyncHandlerOptions);

  /**
   * Logs in a user with email and password
   *
   * @param email - User's email address
   * @param password - User's password
   * @param rememberMe - Whether to keep session alive (optional)
   * @returns true if login successful, false otherwise
   */
  /* eslint-disable complexity */
  async function login(
    email: string,
    password: string,
    rememberMe: boolean = false
  ): Promise<boolean> {
    clearErrors();

    const result = await wrap(async () => {
      const response = await $api.post<LoginResponse>('/auth/login', {
        login: email,
        password: password,
        shrimp: csrfStore.shrimp,
        'remember-me': rememberMe,
      });

      const validated = loginResponseSchema.parse(response.data);

      console.log('[useAuth] Login response:', {
        data: response.data,
        validated: validated,
        hasMfaRequired: 'mfa_required' in response.data,
        mfaRequiredValue: (response.data as any).mfa_required,
      });

      if (isAuthError(validated)) {
        throw createError(validated.error, 'human', 'error', {
          'field-error': validated['field-error'],
          ...((validated as any).lockout ? { lockout: (validated as any).lockout } : {}),
        });
      }

      // Check if MFA is required (Rodauth returns success but with mfa_required flag)
      if (requiresMfa(validated)) {
        console.log('[useAuth] MFA required, refreshing window state and redirecting', {
          mfa_auth_url: validated.mfa_auth_url,
          mfa_methods: validated.mfa_methods,
        });

        // Refresh window state to get awaiting_mfa flag from backend
        await authStore.checkWindowStatus();

        // Now redirect - route guard will allow access since awaiting_mfa is set
        await router.push('/mfa-verify');
        return false; // Not fully logged in yet
      }

      // Success - update auth state (this fetches fresh window state)
      await authStore.setAuthenticated(true);
      await router.push('/');
      return true;
    });

    return result ?? false;
  }

  /**
   * Creates a new user account
   *
   * @param email - User's email address
   * @param password - User's password
   * @param termsAgreed - Whether user agreed to terms (optional)
   * @returns true if account created successfully, false otherwise
   */
  async function signup(
    email: string,
    password: string,
    termsAgreed: boolean = true
  ): Promise<boolean> {
    clearErrors();

    const result = await wrap(async () => {
      const response = await $api.post<CreateAccountResponse>('/auth/create-account', {
        login: email,
        password: password,
        agree: termsAgreed,
        shrimp: csrfStore.shrimp,
      });

      const validated = createAccountResponseSchema.parse(response.data);

      if (isAuthError(validated)) {
        throw createError(validated.error, 'human', 'error', {
          'field-error': validated['field-error'],
        });
      }

      // Success - account created but NOT authenticated yet
      // User needs to either verify email or sign in
      notificationsStore.show(validated.success, 'success', 'top');
      await router.push('/signin');
      return true;
    });

    return result ?? false;
  }

  /**
   * Logs out the current user
   *
   * @returns true if logout successful
   */
  async function logout(): Promise<boolean> {
    clearErrors();

    const result = await wrap(async () => {
      const response = await $api.post<LogoutResponse>('/auth/logout', {
        shrimp: csrfStore.shrimp,
      });

      const validated = logoutResponseSchema.parse(response.data);

      if (isAuthError(validated)) {
        throw createError(validated.error, 'human', 'error');
      }

      // Success - clear auth state
      await authStore.logout();

      // Force page reload to fetch fresh unauthenticated state from backend
      window.location.href = '/';
      return true;
    });

    return result ?? false;
  }

  /**
   * Requests a password reset email
   *
   * @param email - User's email address
   * @returns true if request successful
   */
  async function requestPasswordReset(email: string): Promise<boolean> {
    clearErrors();

    const result = await wrap(async () => {
      const response = await $api.post<ResetPasswordRequestResponse>('/auth/reset-password', {
        login: email,
        shrimp: csrfStore.shrimp,
      });

      const validated = resetPasswordRequestResponseSchema.parse(response.data);

      if (isAuthError(validated)) {
        throw createError(validated.error, 'human', 'error', {
          'field-error': validated['field-error'],
        });
      }

      return true;
    });

    return result ?? false;
  }

  /**
   * Resets password using a reset key
   *
   * @param key - Password reset key from email
   * @param newPassword - New password
   * @param confirmPassword - Password confirmation
   * @returns true if reset successful
   */
  async function resetPassword(
    key: string,
    newPassword: string,
    confirmPassword: string
  ): Promise<boolean> {
    clearErrors();

    const result = await wrap(async () => {
      const response = await $api.post<ResetPasswordResponse>(`/auth/reset-password/${key}`, {
        key,
        newp: newPassword,
        'password-confirm': confirmPassword,
        shrimp: csrfStore.shrimp,
      });

      const validated = resetPasswordResponseSchema.parse(response.data);

      if (isAuthError(validated)) {
        throw createError(validated.error, 'human', 'error', {
          'field-error': validated['field-error'],
        });
      }

      // Success - navigate to signin
      await router.push('/signin');
      return true;
    });

    return result ?? false;
  }

  /**
   * Verifies a user account with a verification key
   *
   * @param key - Account verification key from email
   * @returns true if verification successful
   */
  async function verifyAccount(key: string): Promise<boolean> {
    clearErrors();

    const result = await wrap(async () => {
      const response = await $api.post<VerifyAccountResponse>('/auth/verify-account', {
        key,
        shrimp: csrfStore.shrimp,
      });

      const validated = verifyAccountResponseSchema.parse(response.data);

      if (isAuthError(validated)) {
        throw createError(validated.error, 'human', 'error');
      }

      // Success - show notification and navigate to signin
      notificationsStore.show(validated.success, 'success', 'top');
      await router.push('/signin');
      return true;
    });

    return result ?? false;
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

    const result = await wrap(async () => {
      const response = await $api.post<ChangePasswordResponse>('/auth/change-password', {
        password: currentPassword,
        'new-password': newPassword, // was newp
        'password-confirm': confirmPassword, // was newp2
      });

      const validated = changePasswordResponseSchema.parse(response.data);

      if (isAuthError(validated)) {
        throw createError(validated.error, 'human', 'error', {
          'field-error': validated['field-error'],
        });
      }

      // Success - show notification
      notificationsStore.show(validated.success, 'success', 'top');
      return true;
    });

    return result ?? false;
  }

  /**
   * Closes the authenticated user's account (permanent deletion)
   *
   * @param password - Current password for confirmation
   * @returns true if account closed successfully
   */
  async function closeAccount(password: string): Promise<boolean> {
    clearErrors();

    const result = await wrap(async () => {
      const response = await $api.post<CloseAccountResponse>('/auth/close-account', {
        password,
        shrimp: csrfStore.shrimp,
      });

      const validated = closeAccountResponseSchema.parse(response.data);

      if (isAuthError(validated)) {
        throw createError(validated.error, 'human', 'error', {
          'field-error': validated['field-error'],
        });
      }

      // Success - logout and redirect to home
      await authStore.logout();
      await router.push('/');
      return true;
    });

    return result ?? false;
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
