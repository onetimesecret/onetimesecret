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
}

/** Shape of Rodauth-style error responses */
interface RodauthErrorResponse {
  error?: string;
  'field-error'?: [string, string];
}

/** Shape of axios-style errors */
interface AxiosLikeError {
  response?: { data?: RodauthErrorResponse };
  message?: string;
}

/**
 * Extracts error info from a Rodauth-style response or axios error.
 */
function extractErrorInfo(
  data: RodauthErrorResponse | undefined,
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
   * Creates a new account and atomically accepts the invitation.
   * The backend handles both operations when invite_token is provided.
   */
  async function signupAndAccept(
    email: string,
    password: string,
    termsAgreed: boolean,
    inviteToken: string,
    skill: string = ''
  ): Promise<InviteAuthResult> {
    isLoading.value = true;
    error.value = null;
    fieldErrors.value = {};

    try {
      await refreshCsrf();

      const response = await $api.post('/auth/create-account', {
        login: email,
        password,
        agree: termsAgreed,
        invite_token: inviteToken,
        skill,
        shrimp: csrfStore.shrimp,
        locale: locale.value,
      });

      if (response.data?.error) {
        const info = extractErrorInfo(response.data);
        setError(info);
        return { success: false, error: info.message };
      }

      // Server set session cookie via create_account_autologin — sync frontend state.
      // Fire-and-forget: awaiting would yield to the microtask queue, letting Vue
      // flush a re-render that unmounts InviteSignUpForm (inviteState transitions
      // from signup_required → direct_accept) before emit('success') reaches the
      // parent. The 1.5s redirect delay in onAcceptSuccess gives the background
      // refresh ample time to complete.
      authStore.setAuthenticated(true).catch((err) => {
        console.warn('[useInviteAuth] Background auth sync failed after signup:', err);
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

      // Login successful - membership already created by after_login hook.
      // Fire-and-forget: same reasoning as signupAndAccept — awaiting triggers
      // a reactive cascade that unmounts the form before emit('success') fires.
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
    signupAndAccept,
    loginAndAccept,
    clearErrors,
    isLoading,
    error,
    fieldErrors,
  };
}
