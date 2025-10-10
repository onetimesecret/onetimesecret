// src/composables/useAuth.ts
import { inject, ref } from 'vue';
import { useRouter } from 'vue-router';
import { useAuthStore } from '@/stores/authStore';
import { useCsrfStore } from '@/stores/csrfStore';
import { useNotificationsStore } from '@/stores/notificationsStore';
import {
  isAuthError,
  type LoginResponse,
  type CreateAccountResponse,
  type LogoutResponse,
  type ResetPasswordRequestResponse,
  type ResetPasswordResponse,
} from '@/schemas/api/endpoints/auth';
import {
  loginResponseSchema,
  createAccountResponseSchema,
  logoutResponseSchema,
  resetPasswordRequestResponseSchema,
  resetPasswordResponseSchema,
} from '@/schemas/api/endpoints/auth';
import type { AxiosInstance } from 'axios';

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
export function useAuth() {
  const $api = inject('api') as AxiosInstance;
  const router = useRouter();
  const authStore = useAuthStore();
  const csrfStore = useCsrfStore();
  const notificationsStore = useNotificationsStore();

  const isLoading = ref(false);
  const error = ref<string | null>(null);
  const fieldError = ref<[string, string] | null>(null);

  /**
   * Clears error state
   */
  function clearErrors() {
    error.value = null;
    fieldError.value = null;
  }

  /**
   * Sets error from auth response
   */
  function setError(response: LoginResponse | CreateAccountResponse | ResetPasswordRequestResponse | ResetPasswordResponse) {
    if (isAuthError(response)) {
      error.value = response.error;
      fieldError.value = response['field-error'] || null;
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
  async function login(email: string, password: string, rememberMe: boolean = false): Promise<boolean> {
    clearErrors();
    isLoading.value = true;

    try {
      const response = await $api.post<LoginResponse>('/auth/login', {
        u: email,
        p: password,
        shrimp: csrfStore.shrimp,
        'remember-me': rememberMe,
      });

      const validated = loginResponseSchema.parse(response.data);

      if (isAuthError(validated)) {
        setError(validated);
        return false;
      }

      // Success - update auth state
      authStore.setAuthenticated(true);

      // Fetch updated window state with authenticated customer data
      try {
        const windowResponse = await $api.get('/window');
        if (window.__ONETIME_STATE__ && windowResponse.data) {
          // Update window state with fresh authenticated data
          window.__ONETIME_STATE__ = windowResponse.data;
        }
      } catch (windowErr) {
        console.warn('Failed to update window state after login:', windowErr);
        // Non-critical - proceed with navigation
      }

      await router.push('/');
      return true;
    } catch (err: any) {
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
        u: email,
        p: password,
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
        u: email,
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

  return {
    // State
    isLoading,
    error,
    fieldError,

    // Actions
    login,
    signup,
    logout,
    requestPasswordReset,
    resetPassword,
    clearErrors,
  };
}
