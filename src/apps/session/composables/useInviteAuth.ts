// src/apps/session/composables/useInviteAuth.ts
//
// Authentication composable for the organization invitation flow.
// Unlike useAuth, this composable emits events instead of navigating,
// allowing the parent AcceptInvite view to manage the flow.

import { ref } from 'vue';
import { useAuthStore } from '@/shared/stores/authStore';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { useCsrfStore } from '@/shared/stores/csrfStore';
import { useApi } from '@/shared/composables/useApi';
import { useI18n } from 'vue-i18n';

/**
 * Result from signup/login operations.
 */
export interface InviteAuthResult {
  success: boolean;
  error?: string | null;
  requiresMfa?: boolean;
  redirect?: string;
  /** Set when signup fails because account already exists; caller should switch to signin. */
  accountExists?: boolean;
}

/** Shape of API error responses */
interface ApiErrorResponse {
  error?: string;
  'field-error'?: [string, string];
}

/** Shape of axios-style errors */
interface AxiosLikeError {
  response?: { data?: ApiErrorResponse };
  message?: string;
}

/**
 * Extracts error info from an API response or axios error.
 */
function extractErrorInfo(
  data: ApiErrorResponse | undefined,
  err?: AxiosLikeError
): { message: string | null; fieldError?: [string, string] } {
  const errorData = data ?? err?.response?.data;
  if (errorData?.error) {
    return {
      message: errorData.error,
      fieldError: errorData['field-error'],
    };
  }
  return { message: err?.message ?? 'An error occurred' };
}

/**
 * Composable for handling authentication during organization invite acceptance.
 *
 * Key differences from useAuth:
 * - Does NOT navigate - returns results for parent component to handle
 * - Handles invite token alongside auth operations
 *
 * Explicit-consent design: signup and login establish a session but do NOT
 * consume the invitation. The user must explicitly click Accept (or Decline)
 * on the AcceptInvite view, which fires POST /api/invite/:token/accept against
 * the live token. This keeps the join action visible and reversible until the
 * user confirms.
 */
/* eslint-disable max-lines-per-function */
export function useInviteAuth() {
  const $api = useApi();
  const authStore = useAuthStore();
  const bootstrapStore = useBootstrapStore();
  const csrfStore = useCsrfStore();
  const { locale } = useI18n();

  const isLoading = ref(false);
  const error = ref<string | null>(null);
  const fieldErrors = ref<Record<string, string>>({});

  /** Best-effort CSRF token refresh before POST. */
  async function refreshCsrf() {
    try {
      await bootstrapStore.refresh();
    } catch (e) {
      console.warn('[useInviteAuth] Bootstrap refresh failed, proceeding:', e);
    }
  }

  /** Sets error state from extracted error info. */
  function setError(info: { message: string | null; fieldError?: [string, string] }) {
    error.value = info.message;
    if (info.fieldError) {
      const [field, msg] = info.fieldError;
      fieldErrors.value = { [field]: msg };
    }
  }

  /**
   * Creates a new account for an invite, establishing a session.
   *
   * Does NOT consume the invitation — the backend leaves the membership in
   * pending state. The parent view transitions to the explicit Decline/Accept
   * screen and the user issues the /accept call themselves.
   *
   * @returns InviteAuthResult with accountExists: true if the backend indicates
   *          the account already exists (caller should switch to signin flow).
   */
  async function signupForInvite(
    _email: string, // Kept for API compatibility; backend derives email from token
    password: string,
    termsAgreed: boolean,
    inviteToken: string,
    _skill: string = '' // Honeypot no longer sent to new endpoint
  ): Promise<InviteAuthResult & { accountExists?: boolean }> {
    isLoading.value = true;
    error.value = null;
    fieldErrors.value = {};

    try {
      await refreshCsrf();

      const response = await $api.post(`/api/invite/${inviteToken}/signup`, {
        password,
        agree: termsAgreed,
        shrimp: csrfStore.shrimp,
        locale: locale.value,
      });

      if (response.data?.error) {
        const info = extractErrorInfo(response.data);
        setError(info);

        // Check for "account exists" error to trigger signin flow
        const accountExists = response.data.error?.toLowerCase().includes('already exists');
        return { success: false, error: info.message, accountExists };
      }

      // Server set session cookie via create_account_autologin — sync frontend state.
      // Fire-and-forget: awaiting would yield to the microtask queue, letting Vue
      // flush a re-render that unmounts InviteSignUpForm (inviteState transitions
      // from signup_required → direct_accept) before emit('success') reaches
      // the parent.
      authStore.setAuthenticated(true).catch((err) => {
        console.warn('[useInviteAuth] Background auth sync failed after signup:', err);
      });

      return { success: true };
    } catch (e) {
      const info = extractErrorInfo(undefined, e as AxiosLikeError);
      setError(info);

      // Check for "account exists" in error response
      const axiosErr = e as AxiosLikeError;
      const accountExists = axiosErr.response?.data?.error?.toLowerCase().includes('already exists');
      return { success: false, error: info.message, accountExists };
    } finally {
      isLoading.value = false;
    }
  }

  /**
   * Logs in an existing user invited to an organization.
   *
   * Does NOT consume the invitation — only establishes the session. The user
   * must explicitly click Accept on the AcceptInvite view to complete the join.
   * Handles MFA by returning requiresMfa: true for the parent to redirect.
   */
  async function loginForInvite(
    email: string,
    password: string,
    inviteToken: string
  ): Promise<InviteAuthResult> {
    isLoading.value = true;
    error.value = null;
    fieldErrors.value = {};

    try {
      await refreshCsrf();

      // The invite_token is passed for telemetry/context; the after_login hook
      // does not auto-accept. Acceptance happens via the explicit user click on
      // the AcceptInvite view post-login.
      const loginResp = await $api.post('/auth/login', {
        login: email,
        password,
        invite_token: inviteToken,
        shrimp: csrfStore.shrimp,
        locale: locale.value,
      });

      if (loginResp.data?.error) {
        const info = extractErrorInfo(loginResp.data);
        setError(info);
        return { success: false, error: info.message };
      }

      if (loginResp.data?.mfa_required) {
        // MFA flow - invite_token is preserved in session by backend
        // User will return to invite page after MFA completion
        bootstrapStore.update({ awaiting_mfa: true, authenticated: false });
        return { success: false, requiresMfa: true, redirect: `/invite/${inviteToken}` };
      }

      // Login established the session. The invitation is NOT accepted here —
      // the user must explicitly click Accept on the AcceptInvite view. The
      // after_login hook no longer auto-accepts; signup and login share the
      // same downstream acceptance path (explicit user click).
      //
      // Fire-and-forget setAuthenticated: awaiting triggers a reactive cascade
      // that unmounts the form before emit('success') fires.
      authStore.setAuthenticated(true).catch((err) => {
        console.warn('[useInviteAuth] Background auth sync failed after login:', err);
      });

      return { success: true };
    } catch (e) {
      const info = extractErrorInfo(undefined, e as AxiosLikeError);
      setError(info);
      return { success: false, error: info.message };
    } finally {
      isLoading.value = false;
    }
  }

  /** Clears all error state. */
  function clearErrors() {
    error.value = null;
    fieldErrors.value = {};
  }

  return {
    signupForInvite,
    loginForInvite,
    clearErrors,
    isLoading,
    error,
    fieldErrors,
  };
}
