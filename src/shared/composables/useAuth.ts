// src/shared/composables/useAuth.ts

import {
  changePasswordResponseSchema,
  closeAccountResponseSchema,
  createAccountResponseSchema,
  emailChangeConfirmResponseSchema,
  emailChangeRequestResponseSchema,
  emailChangeResendResponseSchema,
  isAuthError,
  loginResponseSchema,
  logoutResponseSchema,
  requiresMfa,
  resendVerificationEmailResponseSchema,
  resetPasswordRequestResponseSchema,
  resetPasswordResponseSchema,
  verifyAccountResponseSchema,
  type ChangePasswordResponse,
  type CloseAccountResponse,
  type CreateAccountResponse,
  type EmailChangeConfirmResponse,
  type EmailChangeRequestResponse,
  type EmailChangeResendResponse,
  type LoginResponse,
  type LogoutResponse,
  type ResendVerificationEmailResponse,
  type ResetPasswordRequestResponse,
  type ResetPasswordResponse,
  type VerifyAccountResponse,
} from '@/schemas/api/auth/responses/auth';
import { loggingService } from '@/services/logging.service';
import { useApi } from '@/shared/composables/useApi';
import {
  createError,
  useAsyncHandler,
  type AsyncHandlerOptions,
} from '@/shared/composables/useAsyncHandler';
import { usePostAuthRedirect } from '@/shared/composables/usePostAuthRedirect';
import { CHECK_EMAIL_STATE_KEY } from '@/shared/constants/checkEmail';
import { SIGNIN_VERIFIED_STATE_KEY } from '@/shared/constants/signin';
import { useAuthStore } from '@/shared/stores/authStore';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { useCsrfStore } from '@/shared/stores/csrfStore';
import { useNotificationsStore } from '@/shared/stores/notificationsStore';
import type { LockoutStatus } from '@/types/auth';
import { isValidInternalPath } from '@/utils/redirect';
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';

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
  const $api = useApi();
  const router = useRouter();
  const { locale } = useI18n();
  const authStore = useAuthStore();
  const bootstrapStore = useBootstrapStore();
  const csrfStore = useCsrfStore();
  const notificationsStore = useNotificationsStore();

  // Post-authentication destination (billing intent > ?redirect > '/') lives in
  // its own composable so the passwordless flows resolve it identically.
  const { getRedirectParam, getBillingParams, navigateAfterAuth } = usePostAuthRedirect();

  // Alias for backward compatibility - uses shared utility from @/utils/redirect
  const isValidRedirect = isValidInternalPath;

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
        status: response.status,
        hasMfaRequired: 'mfa_required' in response.data,
        mfaRequiredValue: (response.data as any).mfa_required,
        isError: 'error' in validated,
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

        // Redirect to MFA verification - guard will allow access since awaiting_mfa is set.
        // Preserve the redirect param AND the plan-intent pair (product/interval)
        // so MfaChallenge's navigateAfterAuth() keeps the full post-auth
        // precedence: the backend replays a validated billing_redirect on the
        // two-factor completion response (#4306), and the forwarded query is
        // the fallback tier (webauthn factor, page reload, older backends).
        const redirectPath = getRedirectParam();
        const mfaQuery = {
          ...billingParams,
          ...(redirectPath ? { redirect: redirectPath } : {}),
        };
        await router.push({
          path: '/mfa-verify',
          query: Object.keys(mfaQuery).length > 0 ? mfaQuery : undefined,
        });
        return false; // Not fully logged in yet
      }

      // Success - update auth state (this fetches fresh window state)
      await authStore.setAuthenticated(true);

      // Billing intent (validated by backend, else the query pair) wins, then
      // the validated ?redirect, then the dashboard. Shared with the
      // passwordless flows so they can never drift apart.
      await navigateAfterAuth(validated);
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
      // The validated ?redirect goes in the POST body so the backend can store
      // it (pending_auth_redirect) and replay it from the verify-account
      // response — the verification link is typically opened in a different
      // browser session, where this page's query string no longer exists.
      const signupRedirect = getRedirectParam();
      const response = await $api.post<CreateAccountResponse>('/auth/create-account', {
        login: email,
        password: password,
        agree: termsAgreed,
        shrimp: csrfStore.shrimp,
        locale: locale.value,
        ...billingParams,
        ...(signupRedirect ? { redirect: signupRedirect } : {}),
      });

      const validated = createAccountResponseSchema.parse(response.data);

      if (isAuthError(validated)) {
        throw createError(validated.error, 'human', 'error', {
          'field-error': validated['field-error'],
        });
      }

      // Success - account created but NOT authenticated yet. The user must
      // click the verification link in their email before they can sign in.
      notificationsStore.show(validated.success, 'success', 'top');

      // Route to a dedicated "Check your email" confirmation page rather than
      // the sign-in form. The sign-in form is unusable until the account is
      // verified, and a transient toast is the only cue the user would get
      // there. The confirmation page persistently echoes the email address,
      // explains the next step, and offers a resend action.
      //
      // The email travels in router history state, NOT the URL: it is PII, and
      // a query string would leak it through browser history, the Referer
      // header, proxy/CDN access logs and Sentry (disclosure F6; see
      // src/utils/pii.ts and src/router/README.md "Query-string policy"). A
      // plain reload preserves state, but a fresh entry (shared link, new tab)
      // does not — so the billing params and redirect path ride in the query,
      // which survives both, keeping the checkout flow intact.
      const query: Record<string, string> = {};

      if (billingParams.product && billingParams.interval) {
        query.product = billingParams.product;
        query.interval = billingParams.interval;
      }
      if (signupRedirect) {
        query.redirect = signupRedirect;
      }

      await router.push({
        path: '/check-email',
        ...(Object.keys(query).length > 0 ? { query } : {}),
        state: { [CHECK_EMAIL_STATE_KEY]: email },
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

      // Force page reload to fetch fresh unauthenticated state from backend.
      // Navigate BEFORE clearing reactive state to prevent a flash where
      // brand-dependent components (logo, colors) briefly revert to defaults
      // as Pinia stores reset. The hard navigation discards all in-memory
      // state anyway, making the reset purely a cleanup for non-visual concerns.
      const safeRedirect = isValidRedirect(redirectTo) ? redirectTo : '/';

      // Clear cookies and session storage before navigating so the server
      // sees an unauthenticated request. Skip bootstrapStore.$reset() —
      // it triggers reactive flushes that cause visual artifacts, and the
      // full page reload will discard all Pinia state regardless.
      await authStore.logoutMinimal();

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

      // A successful reset revokes every session, including this browser's.
      // Clear local session state and hard-navigate so stale authenticated
      // stores cannot issue protected requests during an SPA route change.
      await authStore.logoutMinimal();
      window.location.href = '/signin';
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

      // Success - show notification, then navigate to the sign-in page. The
      // "just verified" signal is handed over via router history `state`
      // (SIGNIN_VERIFIED_STATE_KEY), NOT a `?verified=1` query param: it is a
      // one-shot UI flag, so keeping it out of the URL lets Login.vue clear it
      // after showing the banner without remounting the fullPath-keyed view
      // (see Login.vue). The sign-in page renders a persistent success banner
      // (surviving longer than the transient toast) and defaults to the password
      // tab so the user re-enters the password they just chose during signup.
      notificationsStore.show(validated.success, 'success', 'top');

      // Carry the return destination across the last hop of the signup journey.
      // `redirect` goes the OPPOSITE way to the verified flag — into the QUERY —
      // because it has to survive a fresh entry: the verification link is opened
      // from a mail client, often in a different browser, so the request that
      // lands here has no history state and frequently no query either. That is
      // why the backend replays the redirect it VALIDATED and stored at signup;
      // we re-validate it anyway (never trust a server-supplied path blindly)
      // and fall back to a ?redirect still present on this URL.
      //
      // Billing/plan intent outranks redirect, and the backend applies that
      // precedence before answering — a response carrying a plan intent simply
      // omits `redirect`. From here on the ordinary sign-in machinery finishes
      // the job: Login.vue reads the query, login() re-applies the precedence,
      // and an MFA account forwards it on to /mfa-verify.
      const responseRedirect = isValidRedirect(validated.redirect) ? validated.redirect : undefined;
      const redirectPath = responseRedirect ?? getRedirectParam();

      await router.push({
        path: '/signin',
        ...(redirectPath ? { query: { redirect: redirectPath } } : {}),
        state: { [SIGNIN_VERIFIED_STATE_KEY]: true },
      });
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

      // Refresh bootstrap state so has_password and other auth-related
      // fields reflect the current server state. This matters when an
      // SSO-only user sets a password for the first time.
      await bootstrapStore.refresh();

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

      // Success - clear cookies/session and redirect to home with full page reload.
      // Use logoutMinimal() instead of logout() to avoid reactive store resets
      // that cause a visual flash before the hard navigation discards state.
      await authStore.logoutMinimal();
      window.location.href = '/';
      return true;
    });

    return result ?? false;
  }

  /**
   * Requests an email address change for the authenticated user.
   * Sends a verification email to the new address.
   *
   * @param newEmail - Desired new email address
   * @param password - Current password for confirmation
   * @returns true if request was successful
   */
  async function requestEmailChange(newEmail: string, password: string): Promise<boolean> {
    clearErrors();

    const result = await wrap(async () => {
      const response = await $api.post<EmailChangeRequestResponse>('/api/account/change-email', {
        new_email: newEmail,
        password,
        shrimp: csrfStore.shrimp,
        locale: locale.value,
      });

      const validated = emailChangeRequestResponseSchema.parse(response.data);

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
   * Confirms an email change using a verification token.
   *
   * @param token - Verification token from email link
   * @returns true if confirmation was successful
   */
  async function confirmEmailChange(token: string): Promise<boolean> {
    clearErrors();

    const result = await wrap(async () => {
      const response = await $api.post<EmailChangeConfirmResponse>(
        '/api/account/confirm-email-change',
        { token, shrimp: csrfStore.shrimp }
      );

      const validated = emailChangeConfirmResponseSchema.parse(response.data);

      if (isAuthError(validated)) {
        throw createError(validated.error, 'human', 'error');
      }

      return true;
    });

    return result ?? false;
  }

  /**
   * Resends the email change confirmation email.
   * Rate-limited to 3 resends per pending change.
   *
   * @returns true if resend was successful
   */
  async function resendEmailChangeConfirmation(): Promise<boolean> {
    clearErrors();

    const result = await wrap(async () => {
      const response = await $api.post<EmailChangeResendResponse>(
        '/api/account/resend-email-change-confirmation',
        {
          shrimp: csrfStore.shrimp,
          locale: locale.value,
        }
      );

      const validated = emailChangeResendResponseSchema.parse(response.data);

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
   * Resends the account verification email for an unverified account.
   *
   * Anti-enumeration: the backend returns an identical { sent: true } for all
   * cases, so this resolves true whenever the request was well-formed and
   * accepted — it does NOT reveal whether the email exists or was actually sent.
   *
   * @param email - the login/email to (re)send verification to
   * @returns true if the request was accepted
   */
  async function resendVerificationEmail(email: string): Promise<boolean> {
    clearErrors();

    const result = await wrap(async () => {
      const response = await $api.post<ResendVerificationEmailResponse>(
        '/api/account/resend-verification-email',
        {
          login: email,
          shrimp: csrfStore.shrimp,
          locale: locale.value,
        }
      );

      const validated = resendVerificationEmailResponseSchema.parse(response.data);

      if (isAuthError(validated)) {
        throw createError(validated.error, 'human', 'error', {
          'field-error': validated['field-error'],
        });
      }

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
    requestEmailChange,
    confirmEmailChange,
    resendEmailChangeConfirmation,
    resendVerificationEmail,
    clearErrors,
  };
}
