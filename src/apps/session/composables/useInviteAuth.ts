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
 * - Supports atomic signup+accept via invite_token parameter
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
   * Completes the invitation acceptance by POSTing to /api/invite/:token/accept.
   *
   * Called after signup or login succeeds and a session is established. The
   * backend leaves the invitation pending after auth so the acceptance step
   * stays explicit and the same code path serves both flows. A non-success
   * response here is logged but not propagated — the user is authenticated,
   * the AcceptInvite page will recover via its direct_accept handler on
   * the next render.
   */
  async function acceptPendingInvite(inviteToken: string): Promise<void> {
    try {
      await $api.post(`/api/invite/${inviteToken}/accept`, {
        shrimp: csrfStore.shrimp,
      });
    } catch (e) {
      console.warn('[useInviteAuth] /accept after auth failed:', e);
    }
  }

  /**
   * Creates a new account and atomically accepts the invitation.
   * Uses the dedicated invite signup endpoint which derives email from the token.
   *
   * @returns InviteAuthResult with accountExists: true if the backend indicates
   *          the account already exists (caller should switch to signin flow).
   */
  async function signupAndAccept(
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
      // from signup_required → direct_accept) before emit('success') reaches the
      // parent. The ACCEPT_SUCCESS_REDIRECT_DELAY_MS in AcceptInvite.vue gives
      // the background refresh ample time to complete before navigation.
      authStore.setAuthenticated(true).catch((err) => {
        console.warn('[useInviteAuth] Background auth sync failed after signup:', err);
      });

      // Complete the join: the signup endpoint creates the account and
      // session but leaves the invitation pending. Issue the explicit
      // /accept call now while the token is still valid and the user is
      // authenticated.
      await acceptPendingInvite(inviteToken);

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
   * Logs in an existing user and accepts the invitation atomically.
   * The backend after_login hook handles invite acceptance when invite_token is present.
   * Handles MFA by returning requiresMfa: true for parent to redirect.
   */
  async function loginAndAccept(
    email: string,
    password: string,
    inviteToken: string
  ): Promise<InviteAuthResult> {
    isLoading.value = true;
    error.value = null;
    fieldErrors.value = {};

    try {
      await refreshCsrf();

      // Single call - backend after_login hook handles invite acceptance
      // when invite_token is provided in the login request
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

      // Login established the session; complete the join via the explicit
      // /accept call. The after_login hook no longer accepts invitations —
      // signup and login share the same downstream acceptance path.
      // Fire-and-forget setAuthenticated: awaiting triggers a reactive
      // cascade that unmounts the form before emit('success') fires.
      authStore.setAuthenticated(true).catch((err) => {
        console.warn('[useInviteAuth] Background auth sync failed after login:', err);
      });

      await acceptPendingInvite(inviteToken);

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
    signupAndAccept,
    loginAndAccept,
    clearErrors,
    isLoading,
    error,
    fieldErrors,
  };
}
