// src/shared/composables/useAuth.ts

import {
  useAsyncHandler,
  createError,
  type AsyncHandlerOptions,
} from '@/shared/composables/useAsyncHandler';
import { loggingService } from '@/services/logging.service';
import { WindowService } from '@/services/window.service';
import {
  isAuthError,
  requiresMfa,
  hasBillingRedirect,
  type LoginResponse,
  type CreateAccountResponse,
  type LogoutResponse,
  type ResetPasswordRequestResponse,
  type ResetPasswordResponse,
  type VerifyAccountResponse,
  type ChangePasswordResponse,
  type CloseAccountResponse,
  type BillingRedirect,
} from '@/schemas/api/auth/endpoints/auth';
import {
  loginResponseSchema,
  createAccountResponseSchema,
  logoutResponseSchema,
  resetPasswordRequestResponseSchema,
  resetPasswordResponseSchema,
  verifyAccountResponseSchema,
  changePasswordResponseSchema,
  closeAccountResponseSchema,
} from '@/schemas/api/auth/endpoints/auth';
import { useAuthStore } from '@/shared/stores/authStore';
import { useCsrfStore } from '@/shared/stores/csrfStore';
import { useNotificationsStore } from '@/shared/stores/notificationsStore';
import { useOrganizationStore } from '@/shared/stores/organizationStore';
import type { LockoutStatus } from '@/types/auth';
import type { AxiosInstance } from 'axios';
import { inject, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';

/**
 * ═══════════════════════════════════════════════════════════════════════════════
 * AUTHENTICATION COMPOSABLE
 * ═══════════════════════════════════════════════════════════════════════════════
 *
 * Handles authentication operations: login, signup, logout, password management.
 * Works with Rodauth-compatible JSON API backend.
 *
 * ───────────────────────────────────────────────────────────────────────────────
 * LOGIN FLOW WITH MFA
 * ───────────────────────────────────────────────────────────────────────────────
 *
 * 1. User submits credentials via SignInForm
 * 2. login() POSTs to /auth/login
 * 3. Response is validated by loginResponseSchema (Zod)
 *    - CRITICAL: Schema union order matters - MFA schema must be first
 * 4. If requiresMfa(response) is true:
 *    a. checkWindowStatus() refreshes state (gets awaiting_mfa=true)
 *    b. router.push('/mfa-verify') navigates to OTP form
 *    c. MfaChallenge.vue handles OTP verification via useMfa composable
 * 5. If no MFA required:
 *    a. setAuthenticated(true) updates state and fetches /window
 *    b. router.push('/') navigates to dashboard
 *
 * ───────────────────────────────────────────────────────────────────────────────
 * RELATED MODULES
 * ───────────────────────────────────────────────────────────────────────────────
 *
 * - authStore: Session state management, periodic /window refresh
 * - useMfa: OTP setup, verification, recovery codes
 * - WindowService: Reactive access to server state
 * - Route guards: Navigation protection based on auth state
 *
 * @example
 * ```ts
 * const { login, signup, logout, isLoading, error } = useAuth();
 *
 * const success = await login('user@example.com', 'password');
 * // If MFA enabled: redirects to /mfa-verify
 * // If no MFA: redirects to dashboard
 * ```
 */
/* eslint-disable max-lines-per-function */
export function useAuth() {
  const $api = inject('api') as AxiosInstance;
  const route = useRoute();
  const router = useRouter();
  const { locale } = useI18n();
  const authStore = useAuthStore();
  const csrfStore = useCsrfStore();
  const notificationsStore = useNotificationsStore();
  const organizationStore = useOrganizationStore();

  /**
   * Extracts billing-related query params from the current route.
   * Used to forward product/interval selection through auth flows.
   *
   * @returns Object with product and interval if present in query params
   */
  function getBillingParams(): { product?: string; interval?: string } {
    const params: { product?: string; interval?: string } = {};
    if (route.query.product && typeof route.query.product === 'string') {
      params.product = route.query.product;
    }
    if (route.query.interval && typeof route.query.interval === 'string') {
      params.interval = route.query.interval;
    }
    return params;
  }

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
   * Handles billing redirect after successful authentication.
   * Returns true if redirect was performed, false otherwise.
   *
   * Only redirects when:
   * - billing_redirect is present and valid
   * - billing_enabled is true (WindowService)
   * - Organization can be resolved
   */
  async function handleBillingRedirect(billingRedirect: BillingRedirect): Promise<boolean> {
    // Check if billing is enabled (graceful degradation for self-hosted)
    const billingEnabled = WindowService.get('billing_enabled');
    if (!billingEnabled) {
      loggingService.debug('[useAuth] Billing redirect skipped - billing not enabled');
      return false;
    }

    try {
      // Fetch organizations to get the default org's extid
      await organizationStore.fetchOrganizations();
      const org = organizationStore.restorePersistedSelection();

      if (!org?.extid) {
        loggingService.warn('[useAuth] Billing redirect skipped - no organization found');
        return false;
      }

      const { tier, billing_cycle } = billingRedirect;
      const checkoutUrl = `/billing/${org.extid}/checkout?tier=${tier}&billing_cycle=${billing_cycle}`;

      loggingService.debug('[useAuth] Redirecting to billing checkout', {
        org: org.extid,
        tier,
        billing_cycle,
      });

      await router.push(checkoutUrl);
      return true;
    } catch (err) {
      // Graceful degradation - if billing redirect fails, continue to dashboard
      loggingService.error(new Error(`Billing redirect failed: ${err}`));
      return false;
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

  async function login(
    email: string,
    password: string,
    rememberMe: boolean = false
  ): Promise<boolean> {
    clearErrors();

    const result = await wrap(async () => {
      const billingParams = getBillingParams();
      const response = await $api.post<LoginResponse>('/auth/login', {
        login: email,
        password: password,
        shrimp: csrfStore.shrimp,
        'remember-me': rememberMe,
        locale: locale.value,
        ...billingParams,
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
        loggingService.debug('[useAuth] MFA required, updating state and redirecting', {
          mfa_auth_url: validated.mfa_auth_url,
          mfa_methods: validated.mfa_methods,
        });

        // Update window state directly from login response - no round-trip needed.
        // The login response already tells us MFA is required, so we set awaiting_mfa
        // to allow route guards to permit access to /mfa-verify.
        // We also explicitly set authenticated: false to ensure consistent state.
        WindowService.update({ awaiting_mfa: true, authenticated: false });

        // Redirect to MFA verification - guard will allow access since awaiting_mfa is set
        await router.push('/mfa-verify');
        return false; // Not fully logged in yet
      }

      // Success - update auth state (this fetches fresh window state)
      await authStore.setAuthenticated(true);

      // Check for billing redirect (e.g., user upgrading during signup flow)
      if (hasBillingRedirect(validated)) {
        const redirected = await handleBillingRedirect(validated.billing_redirect);
        if (redirected) {
          return true; // Redirected to checkout
        }
        // Fall through to dashboard if billing redirect failed
      }

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
      const billingParams = getBillingParams();
      const response = await $api.post<CreateAccountResponse>('/auth/create-account', {
        login: email,
        password: password,
        agree: termsAgreed,
        shrimp: csrfStore.shrimp,
        locale: locale.value,
        ...billingParams,
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
      const response = await $api.post<ResetPasswordRequestResponse>(
        '/auth/reset-password-request',
        {
          login: email,
          shrimp: csrfStore.shrimp,
          locale: locale.value,
        }
      );

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
      const response = await $api.post<ResetPasswordResponse>('/auth/reset-password', {
        key,
        password: newPassword,
        'password-confirm': confirmPassword,
        shrimp: csrfStore.shrimp,
        locale: locale.value,
      });

      const validated = resetPasswordResponseSchema.parse(response.data);

      if (isAuthError(validated)) {
        throw createError(validated.error, 'human', 'error', {
          'field-error': validated['field-error'],
        });
      }

      // Success - show notification and navigate to signin
      notificationsStore.show(validated.success, 'success', 'top');
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
        locale: locale.value,
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
        locale: locale.value,
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
        locale: locale.value,
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
