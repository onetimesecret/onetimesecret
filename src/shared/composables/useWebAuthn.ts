// src/shared/composables/useWebAuthn.ts

import {
  otpVerifyResponseSchema,
  webauthnCredentialsResponseSchema,
  type OtpVerifySuccess,
  type WebAuthnCredential,
} from '@/schemas/api/auth/responses/auth';
import { usePostAuthRedirect } from '@/shared/composables/usePostAuthRedirect';
import { useAuthStore } from '@/shared/stores/authStore';
import { useCsrfStore } from '@/shared/stores/csrfStore';
import type {
  AuthenticationResponseJSON,
  PublicKeyCredentialCreationOptionsJSON,
  PublicKeyCredentialRequestOptionsJSON,
  RegistrationResponseJSON,
} from '@simplewebauthn/browser';
import { startAuthentication, startRegistration } from '@simplewebauthn/browser';
import type { AxiosInstance } from 'axios';
import { inject, ref } from 'vue';
import { useI18n } from 'vue-i18n';

// Response types
type WebAuthnSuccessResponse = { success: string };
type WebAuthnErrorResponse = { error: string; 'field-error'?: [string, string] };
// Rodauth JSON API returns credential options as raw objects (via as_json)
type WebAuthnChallengeResponse = {
  webauthn_setup?: PublicKeyCredentialCreationOptionsJSON;
  webauthn_setup_challenge?: string;
  webauthn_setup_challenge_hmac?: string;
  // BOTH authentication routes (webauthn-auth for MFA and webauthn-login for
  // passwordless first-factor) emit the webauthn_auth key family — Rodauth's
  // JSON layer (json.rb) has no webauthn_login* keys on the wire.
  webauthn_auth?: PublicKeyCredentialRequestOptionsJSON;
  webauthn_auth_challenge?: string;
  webauthn_auth_challenge_hmac?: string;
};

type WebAuthnResponse = WebAuthnSuccessResponse | WebAuthnErrorResponse | WebAuthnChallengeResponse;

function isError(response: WebAuthnResponse): response is WebAuthnErrorResponse {
  return 'error' in response;
}

/**
 * WebAuthn composable - biometric/hardware key authentication
 *
 * @example
 * const { supported, registerWebAuthn, authenticateWebAuthn } = useWebAuthn();
 * if (supported.value) await authenticateWebAuthn();
 */
/* eslint-disable max-lines-per-function */
export function useWebAuthn() {
  const $api = inject('api') as AxiosInstance;
  const { t } = useI18n();
  const authStore = useAuthStore();
  const csrfStore = useCsrfStore();
  const { navigateAfterAuth } = usePostAuthRedirect();

  const isLoading = ref(false);
  const error = ref<string | null>(null);
  const supported = ref(
    typeof window !== 'undefined' &&
      window.PublicKeyCredential !== undefined &&
      typeof window.PublicKeyCredential === 'function'
  );
  /**
   * Body of the last successful webauthn SECOND-FACTOR completion. Mirrors
   * useMfa's `verifyResponse`: the backend replays billing_redirect on the
   * two-factor completion (#4306), and MfaChallenge.vue hands this to
   * usePostAuthRedirect.navigateAfterAuth(). Null until a ceremony succeeds,
   * and reset at the start of every attempt.
   */
  const mfaVerifyResponse = ref<OtpVerifySuccess | null>(null);

  /**
   * Clears error state
   */
  function clearError() {
    error.value = null;
  }

  /**
   * Normalizes WebAuthn catch-block errors into a displayable string.
   * Extracted to keep the three async action functions below the ESLint
   * complexity limit (max 13 branches each).
   */
  function handleWebAuthnError(err: unknown, fallbackKey: string): void {
    type AxiosLike = { response?: { data?: { error?: string } } };
    if (err instanceof DOMException && err.name === 'NotAllowedError') {
      error.value = t('web.auth.webauthn.cancelled');
    } else if (err instanceof Error && 'response' in err && (err as AxiosLike).response?.data) {
      error.value = (err as AxiosLike).response!.data!.error || t(fallbackKey);
    } else if (err instanceof Error) {
      error.value = err.message || t(fallbackKey);
    } else {
      error.value = t(fallbackKey);
    }
  }

  /**
   * Phase 1 of a Rodauth two-phase WebAuthn route: POST without the credential
   * param to obtain the ceremony challenge.
   *
   * Rodauth's JSON layer populates the webauthn_* challenge keys in its
   * before_*_route hook WITHOUT returning early (json.rb:137-165), so the
   * credential-less POST falls through to the route's missing-param
   * throw_error_reason(..., invalid_field_error_status) and the challenge
   * arrives in a 422 body alongside error/field-error. Same Rodauth quirk
   * useMfa.setupMfa handles for otp-setup (the "HMAC 422 flow"). A 2xx body
   * carrying the keys is tolerated in case server behavior differs.
   *
   * @param path - Auth route path (webauthn-setup / webauthn-login / webauthn-auth)
   * @param payload - Request body (shrimp, and password/login when applicable)
   * @param expectedKey - Challenge key family the route emits
   * @returns the challenge payload; throws on responses without it
   */
  async function fetchWebAuthnChallenge(
    path: string,
    payload: Record<string, unknown>,
    expectedKey: 'webauthn_setup' | 'webauthn_auth'
  ): Promise<WebAuthnChallengeResponse> {
    try {
      const response = await $api.post<WebAuthnChallengeResponse>(path, payload);
      return response.data;
    } catch (err: unknown) {
      const axiosErr = err as { response?: { status?: number; data?: Record<string, unknown> } };
      const data = axiosErr.response?.data;

      if (axiosErr.response?.status === 422 && data && data[expectedKey]) {
        // Expected challenge delivery, not a real error
        return data as WebAuthnChallengeResponse;
      }

      // Anything else (401 wrong password / no matching login, 5xx, network)
      // is a genuine failure for the caller's catch block.
      throw err;
    }
  }

  /**
   * Registers a new WebAuthn credential (setup flow)
   *
   * Password confirmation is only required for accounts that HAVE a local
   * password — SSO-only accounts register passkeys without one. When no
   * password is supplied the key is omitted from the request entirely.
   *
   * @param password - User's current password for verification (optional)
   * @returns true if registration successful
   */
  async function registerWebAuthn(password?: string): Promise<boolean> {
    if (!supported.value) {
      error.value = t('web.auth.webauthn.notSupported');
      return false;
    }

    clearError();
    isLoading.value = true;

    try {
      // 1. Get registration challenge from server (arrives in a 422 body)
      const challengeData = await fetchWebAuthnChallenge(
        '/auth/webauthn-setup',
        {
          ...(password ? { password } : {}),
          shrimp: csrfStore.shrimp,
        },
        'webauthn_setup'
      );

      if (!challengeData.webauthn_setup) {
        throw new Error('Invalid challenge response');
      }

      // Rodauth JSON API returns credential options as raw JSON objects
      const optionsJSON = challengeData.webauthn_setup;

      // 2. Trigger browser WebAuthn registration flow
      const credential: RegistrationResponseJSON = await startRegistration({ optionsJSON });

      // 3. Send credential to server for verification
      // Rodauth expects raw JSON, not base64-encoded
      const verifyResp = await $api.post<WebAuthnResponse>('/auth/webauthn-setup', {
        webauthn_setup: credential,
        webauthn_setup_challenge: challengeData.webauthn_setup_challenge,
        webauthn_setup_challenge_hmac: challengeData.webauthn_setup_challenge_hmac,
        ...(password ? { password } : {}),
        shrimp: csrfStore.shrimp,
      });

      const verifyData = verifyResp.data;

      if (isError(verifyData)) {
        error.value = verifyData.error;
        return false;
      }

      return true;
    } catch (err: unknown) {
      handleWebAuthnError(err, 'web.auth.webauthn.setupFailed');
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  /**
   * Passwordless login using a WebAuthn credential
   * Uses the webauthn_login route (no prior session required)
   *
   * @param email - The account's email. Effectively required: without a login
   *   param the route 401s at no_matching_login before ever emitting a
   *   challenge (webauthn_login.rb — this Rodauth version has no autofill/
   *   conditional-UI discovery), so we fail fast instead of posting.
   * @returns true if authentication successful
   */
  async function authenticateWebAuthn(email?: string): Promise<boolean> {
    if (!supported.value) {
      error.value = t('web.auth.webauthn.notSupported');
      return false;
    }

    if (!email) {
      error.value = t('web.auth.webauthn.emailRequired');
      return false;
    }

    clearError();
    isLoading.value = true;

    try {
      // 1. Get authentication challenge from server (passwordless login
      // route; challenge arrives in a 422 body). Rodauth emits it under the
      // webauthn_auth key family (json.rb), NOT webauthn_login — same keys
      // as the MFA route.
      const challengeData = await fetchWebAuthnChallenge(
        '/auth/webauthn-login',
        {
          login: email,
          shrimp: csrfStore.shrimp,
        },
        'webauthn_auth'
      );

      if (!challengeData.webauthn_auth) {
        throw new Error('Invalid challenge response');
      }

      // Rodauth JSON API returns credential options as raw JSON objects
      const optionsJSON = challengeData.webauthn_auth;

      // 2. Trigger browser WebAuthn authentication
      const assertion: AuthenticationResponseJSON = await startAuthentication({ optionsJSON });

      // 3. Send assertion to server for verification. Phase 2 of the
      // webauthn-login route reads the webauthn_auth* params (webauthn_login.rb)
      // and resolves the account by `login`, which is therefore required.
      const verifyResp = await $api.post<WebAuthnResponse>('/auth/webauthn-login', {
        webauthn_auth: assertion,
        webauthn_auth_challenge: challengeData.webauthn_auth_challenge,
        webauthn_auth_challenge_hmac: challengeData.webauthn_auth_challenge_hmac,
        login: email,
        shrimp: csrfStore.shrimp,
      });

      const verifyData = verifyResp.data;

      if (isError(verifyData)) {
        error.value = verifyData.error;
        return false;
      }

      // Success - update auth state and navigate. This route is the PASSWORDLESS
      // first factor (webauthn-login), so the session is complete here; apply
      // the same destination precedence as a password login (billing intent >
      // validated ?redirect > '/'). The MFA route below deliberately does not —
      // MfaChallenge.vue owns the redirect once the second factor lands.
      await authStore.setAuthenticated(true);
      await navigateAfterAuth();
      return true;
    } catch (err: unknown) {
      handleWebAuthnError(err, 'web.auth.webauthn.authFailed');
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  /**
   * MFA authentication using a WebAuthn credential
   * Uses the webauthn_auth route (requires prior session/partial auth)
   *
   * The completion body is kept in `mfaVerifyResponse` — it may carry the
   * replayed billing_redirect (#4306), which MfaChallenge.vue feeds into
   * navigateAfterAuth(). Without it this factor would fall back to the route
   * query, which the MFA hop is not guaranteed to still carry.
   *
   * @returns true if MFA verification successful
   */
  async function verifyWebAuthnMfa(): Promise<boolean> {
    if (!supported.value) {
      error.value = t('web.auth.webauthn.notSupported');
      return false;
    }

    clearError();
    // Reset first so a stale intent can never leak into a later completion.
    mfaVerifyResponse.value = null;
    isLoading.value = true;

    try {
      // 1. Get MFA challenge from server (arrives in a 422 body)
      const challengeData = await fetchWebAuthnChallenge(
        '/auth/webauthn-auth',
        { shrimp: csrfStore.shrimp },
        'webauthn_auth'
      );

      if (!challengeData.webauthn_auth) {
        throw new Error('Invalid challenge response');
      }

      // Rodauth JSON API returns credential options as raw JSON objects
      const optionsJSON = challengeData.webauthn_auth;

      // 2. Trigger browser WebAuthn authentication
      const assertion: AuthenticationResponseJSON = await startAuthentication({ optionsJSON });

      // 3. Send assertion to server for verification
      // Rodauth expects raw JSON, not base64-encoded
      const verifyResp = await $api.post<WebAuthnResponse>('/auth/webauthn-auth', {
        webauthn_auth: assertion,
        webauthn_auth_challenge: challengeData.webauthn_auth_challenge,
        webauthn_auth_challenge_hmac: challengeData.webauthn_auth_challenge_hmac,
        shrimp: csrfStore.shrimp,
      });

      const verifyData = verifyResp.data;

      if (isError(verifyData)) {
        error.value = verifyData.error;
        return false;
      }

      // Keep the completion body for the post-auth redirect. Parsed with the
      // shared two-factor schema so this factor and the OTP/recovery factors
      // agree on the shape; an unexpected body simply leaves the ref null
      // rather than failing an otherwise successful ceremony.
      const completion = otpVerifyResponseSchema.safeParse(verifyData);
      if (completion.success && 'success' in completion.data) {
        mfaVerifyResponse.value = completion.data;
      }

      return true;
    } catch (err: unknown) {
      handleWebAuthnError(err, 'web.auth.webauthn.authFailed');
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  /**
   * Fetches the account's registered WebAuthn credentials
   *
   * The endpoint returns `{ credentials: [{ id, last_used_at }], count }`,
   * ordered last_used desc. There is no name and no created_at — the table
   * has neither column.
   *
   * @returns the credential list, or null on failure (error is set)
   */
  async function fetchWebAuthnCredentials(): Promise<WebAuthnCredential[] | null> {
    clearError();
    isLoading.value = true;

    try {
      const response = await $api.get('/auth/webauthn-credentials');
      const validated = webauthnCredentialsResponseSchema.parse(response.data);
      return validated.credentials;
    } catch (err: unknown) {
      handleWebAuthnError(err, 'web.auth.passkeys.load_failed');
      return null;
    } finally {
      isLoading.value = false;
    }
  }

  /**
   * Removes a registered WebAuthn credential
   *
   * Single POST to Rodauth's webauthn-remove route — no browser ceremony.
   * Password is validated only for accounts that HAVE a local password;
   * omit it (key excluded from the body) for SSO-only accounts.
   *
   * @param credentialId - The credential's webauthn id
   * @param password - User's current password for verification (optional)
   * @returns true if removal successful
   */
  async function removeWebAuthn(credentialId: string, password?: string): Promise<boolean> {
    clearError();
    isLoading.value = true;

    try {
      const response = await $api.post<WebAuthnResponse>('/auth/webauthn-remove', {
        webauthn_remove: credentialId,
        ...(password ? { password } : {}),
        shrimp: csrfStore.shrimp,
      });

      const data = response.data;

      if (isError(data)) {
        error.value = data.error;
        return false;
      }

      return true;
    } catch (err: unknown) {
      handleWebAuthnError(err, 'web.auth.passkeys.remove_failed');
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  return {
    // State
    supported,
    isLoading,
    error,
    mfaVerifyResponse, // Completion body of the last webauthn second factor

    // Actions
    registerWebAuthn,
    authenticateWebAuthn, // Passwordless login (signin page)
    verifyWebAuthnMfa, // MFA verification (after password login)
    fetchWebAuthnCredentials, // Passkey management list (settings page)
    removeWebAuthn, // Passkey removal (settings page)
    clearError,
  };
}
