// src/shared/composables/useAuth.ts

import {
  useAsyncHandler,
  createError,
  type AsyncHandlerOptions,
} from '@/shared/composables/useAsyncHandler';
import { loggingService } from '@/services/logging.service';
import { isValidInternalPath } from '@/utils/redirect';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
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
 * - authStore: Session state management, periodic /bootstrap/me refresh
 * - useMfa: OTP setup, verification, recovery codes
 * - bootstrapStore: Reactive access to server state
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
  const bootstrapStore = useBootstrapStore();
  const csrfStore = useCsrfStore();
  const notificationsStore = useNotificationsStore();
  const organizationStore = useOrganizationStore();

  // Alias for backward compatibility - uses shared utility from @/utils/redirect
  const isValidRedirect = isValidInternalPath;

  /**
   * Gets the redirect path from query params if valid.
   *
   * @returns The redirect path if valid, undefined otherwise
   */
  function getRedirectParam(): string | undefined {
    const redirect = route.query.redirect;
    const redirectPath = typeof redirect === 'string' ? redirect : undefined;
    return isValidRedirect(redirectPath) ? redirectPath : undefined;
  }

  /**
   * Extracts billing-related query params from the current route.
   * Used to forward product/interval selection through auth flows.
   *
   * Terminology note:
   * - `interval` = plan frequency choice (month, year) - user's selection
   * - `billing_cycle` = subscription parameter - returned by backend
   *
   * The backend translates interval → billing_cycle when creating the
   * billing_redirect response, aligning with Stripe's terminology where
   * "interval" is the price frequency and "billing_cycle" refers to
   * subscription billing dates.
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
   * Extracts billing params from login response or falls back to query params.
   * Returns null if backend marked the plan as invalid.
   *
   * @param response - Login response that may contain billing_redirect
   * @returns Billing params or null if invalid/not present
   */
  function extractBillingParams(
    response?: LoginResponse | CreateAccountResponse
  ): { product: string; interval: string } | null {
    if (response && hasBillingRedirect(response)) {
      // Backend validated the plan - use the response values
      loggingService.debug('[useAuth] Using validated billing redirect from response', {
        product: response.billing_redirect.product,
        interval: response.billing_redirect.interval,
      });
      return {
        product: response.billing_redirect.product,
        interval: response.billing_redirect.interval,
      };
    }

    if (response && 'billing_redirect' in response && response.billing_redirect) {
      // Backend returned billing_redirect but valid=false - do not redirect
      const billingRedirect = response.billing_redirect as BillingRedirect;
      loggingService.warn('[useAuth] Billing redirect skipped - backend marked plan as invalid', {
        product: billingRedirect.product,
        interval: billingRedirect.interval,
        valid: billingRedirect.valid,
      });
      return null;
    }

    // No billing_redirect in response - check query params as fallback
    const params = getBillingParams();
    if (params.product && params.interval) {
      return { product: params.product, interval: params.interval };
    }

    return null;
  }

  /**
   * Normalizes plan IDs for comparison by stripping version/interval suffixes.
   * e.g., 'identity_plus_v1_monthly' -> 'identity_plus'
   */
  function normalizePlanId(planId: string): string {
    return planId.replace(/_v\d+.*$/, '');
  }

  /**
   * Handles redirect for users with existing subscriptions.
   * @returns true if redirect was performed
   */
  async function handleExistingSubscription(
    orgExtid: string,
    currentPlanId: string,
    product: string,
    interval: string
  ): Promise<boolean> {
    const normalizedCurrent = normalizePlanId(currentPlanId);
    const normalizedRequested = normalizePlanId(product);

    if (normalizedCurrent === normalizedRequested) {
      // Already subscribed to the same plan - redirect to billing overview
      loggingService.info('[useAuth] User already subscribed to requested plan', {
        currentPlan: currentPlanId,
        requestedProduct: product,
      });
      notificationsStore.show('You are already subscribed to this plan.', 'info', 'top');
      await router.push(`/billing/${orgExtid}/overview`);
      return true;
    }

    // Subscribed to a different plan - redirect to plan change flow
    loggingService.info('[useAuth] User has different subscription, redirecting to plans', {
      currentPlan: currentPlanId,
      requestedProduct: product,
    });
    await router.push(
      `/billing/${orgExtid}/plans?product=${product}&interval=${interval}&change=true`
    );
    return true;
  }

  /**
   * Handles billing redirect after successful authentication.
   * Uses billing_redirect from login response if valid, otherwise falls back to route query params.
   * Returns true if redirect was performed, false otherwise.
   *
   * Safety checks:
   * 1. Validates billing_redirect.valid flag from backend
   * 2. Checks if user already has an active subscription
   * 3. Redirects appropriately based on subscription status
   *
   * @param response - Login response that may contain billing_redirect
   */
  async function handleBillingRedirect(
    response?: LoginResponse | CreateAccountResponse
  ): Promise<boolean> {
    // Extract and validate billing params
    const billingParams = extractBillingParams(response);
    if (!billingParams) {
      return false;
    }
    const { product, interval } = billingParams;

    // Check if billing is enabled (graceful degradation for self-hosted)
    if (!bootstrapStore.billing_enabled) {
      loggingService.debug('[useAuth] Billing redirect skipped - billing not enabled');
      return false;
    }

    try {
      // Fetch organizations to get the default org's extid and subscription status
      await organizationStore.fetchOrganizations();
      const org = organizationStore.restorePersistedSelection();

      if (!org?.extid) {
        loggingService.warn('[useAuth] Billing redirect skipped - no organization found');
        return false;
      }

      // Fetch entitlements to get current subscription status
      await organizationStore.fetchEntitlements(org.extid);

      // Re-fetch org after entitlements update (it may have been updated in the store)
      const updatedOrg = organizationStore.organizations.find((o) => o.extid === org.extid);
      const currentPlanId = updatedOrg?.planid;

      // Check subscription status - delegate to helper if subscribed
      if (currentPlanId) {
        return handleExistingSubscription(org.extid, currentPlanId, product, interval);
      }

      // No active subscription - proceed to plans page for checkout
      loggingService.debug('[useAuth] Redirecting to billing plans', {
        org: org.extid,
        product,
        interval,
      });
      await router.push(`/billing/${org.extid}/plans?product=${product}&interval=${interval}`);
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

      loggingService.debug('[useAuth] Login response:', {
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

        // Update bootstrap store directly from login response - no round-trip needed.
        // The login response already tells us MFA is required, so we set awaiting_mfa
        // to allow route guards to permit access to /mfa-verify.
        // We also explicitly set authenticated: false to ensure consistent state.
        bootstrapStore.update({ awaiting_mfa: true, authenticated: false });

        // Redirect to MFA verification - guard will allow access since awaiting_mfa is set
        // Preserve redirect param so MFA flow can complete the redirect after verification
        const redirectPath = getRedirectParam();
        await router.push({
          path: '/mfa-verify',
          query: redirectPath ? { redirect: redirectPath } : undefined,
        });
        return false; // Not fully logged in yet
      }

      // Success - update auth state (this fetches fresh window state)
      await authStore.setAuthenticated(true);

      // Check for billing redirect using response data (validated by backend)
      // This handles both billing_redirect in response and fallback to query params
      const redirected = await handleBillingRedirect(validated);
      if (redirected) {
        return true; // Redirected to billing plans or overview
      }

      // Check for redirect param (e.g., from invitation flow)
      const redirectPath = getRedirectParam();
      if (redirectPath) {
        loggingService.debug('[useAuth] Redirecting to saved path after login', { redirectPath });
        await router.push(redirectPath);
        return true;
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

      // Build query params for signin redirect
      // Preserve billing params and redirect path for subsequent login
      const redirectPath = getRedirectParam();
      const query: Record<string, string> = {};

      if (billingParams.product && billingParams.interval) {
        query.product = billingParams.product;
        query.interval = billingParams.interval;
      }
      if (redirectPath) {
        query.redirect = redirectPath;
      }

      await router.push({
        path: '/signin',
        query: Object.keys(query).length > 0 ? query : undefined,
      });
      return true;
    });

    return result ?? false;
  }

  /**
   * Logs out the current user
   *
   * @param redirectTo - Optional path to redirect to after logout (must be a valid internal path)
   * @returns true if logout successful
   */
  async function logout(redirectTo?: string): Promise<boolean> {
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
      // Validate redirect URL to prevent open redirect attacks
      const safeRedirect = isValidRedirect(redirectTo) ? redirectTo : '/';
      window.location.href = safeRedirect;
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
