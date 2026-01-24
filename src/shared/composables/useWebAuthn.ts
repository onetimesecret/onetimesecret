// src/shared/composables/useWebAuthn.ts

import { useAuthStore } from '@/shared/stores/authStore';
import { useCsrfStore } from '@/shared/stores/csrfStore';
import { startRegistration, startAuthentication } from '@simplewebauthn/browser';
import type {
  RegistrationResponseJSON,
  AuthenticationResponseJSON,
} from '@simplewebauthn/browser';
import type { AxiosInstance } from 'axios';
import { inject, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';

// Response types
type WebAuthnSuccessResponse = { success: string };
type WebAuthnErrorResponse = { error: string; 'field-error'?: [string, string] };
type WebAuthnChallengeResponse = {
  webauthn_setup?: string;
  webauthn_setup_challenge?: string;
  webauthn_setup_challenge_hmac?: string;
  // MFA route (webauthn-auth)
  webauthn_auth?: string;
  webauthn_auth_challenge?: string;
  webauthn_auth_challenge_hmac?: string;
  // Passwordless login route (webauthn-login)
  webauthn_login?: string;
  webauthn_login_challenge?: string;
  webauthn_login_challenge_hmac?: string;
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
  const router = useRouter();
  const { t } = useI18n();
  const authStore = useAuthStore();
  const csrfStore = useCsrfStore();

  const isLoading = ref(false);
  const error = ref<string | null>(null);
  const supported = ref(
    typeof window !== 'undefined' &&
      window.PublicKeyCredential !== undefined &&
      typeof window.PublicKeyCredential === 'function'
  );

  /**
   * Clears error state
   */
  function clearError() {
    error.value = null;
  }

  /**
   * Registers a new WebAuthn credential (setup flow)
   * Requires password confirmation for security
   *
   * @param password - User's current password for verification
   * @returns true if registration successful
   */
  async function registerWebAuthn(password: string): Promise<boolean> {
    if (!supported.value) {
      error.value = t('web.auth.webauthn.notSupported');
      return false;
    }

    if (!password) {
      error.value = t('web.auth.webauthn.passwordRequired');
      return false;
    }

    clearError();
    isLoading.value = true;

    try {
      // 1. Get registration challenge from server (requires password)
      const challengeResp = await $api.post<WebAuthnChallengeResponse>('/auth/webauthn-setup', {
        password,
        shrimp: csrfStore.shrimp,
      });

      const challengeData = challengeResp.data;

      if (!challengeData.webauthn_setup) {
        throw new Error('Invalid challenge response');
      }

      // Parse base64-encoded WebAuthn options
      const options = JSON.parse(atob(challengeData.webauthn_setup));

      // 2. Trigger browser WebAuthn registration flow
      const credential: RegistrationResponseJSON = await startRegistration(options);

      // 3. Send credential to server for verification
      const verifyResp = await $api.post<WebAuthnResponse>('/auth/webauthn-setup', {
        webauthn_setup: btoa(JSON.stringify(credential)),
        webauthn_setup_challenge: challengeData.webauthn_setup_challenge,
        webauthn_setup_challenge_hmac: challengeData.webauthn_setup_challenge_hmac,
        password,
        shrimp: csrfStore.shrimp,
      });

      const verifyData = verifyResp.data;

      if (isError(verifyData)) {
        error.value = verifyData.error;
        return false;
      }

      return true;
    } catch (err: any) {
      // Handle WebAuthn errors
      if (err.name === 'NotAllowedError') {
        error.value = t('web.auth.webauthn.cancelled');
      } else if (err.response?.data) {
        error.value = err.response.data.error || t('web.auth.webauthn.setupFailed');
      } else {
        error.value = err.message || t('web.auth.webauthn.setupFailed');
      }
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  /**
   * Passwordless login using a WebAuthn credential
   * Uses the webauthn_login route (no prior session required)
   *
   * @param email - Optional email hint for credential selection
   * @returns true if authentication successful
   */
  async function authenticateWebAuthn(email?: string): Promise<boolean> {
    if (!supported.value) {
      error.value = t('web.auth.webauthn.notSupported');
      return false;
    }

    clearError();
    isLoading.value = true;

    try {
      // 1. Get authentication challenge from server (passwordless login route)
      const challengeResp = await $api.post<WebAuthnChallengeResponse>('/auth/webauthn-login', {
        login: email,
        shrimp: csrfStore.shrimp,
      });

      const challengeData = challengeResp.data;

      if (!challengeData.webauthn_login) {
        throw new Error('Invalid challenge response');
      }

      // Parse base64-encoded WebAuthn options
      const options = JSON.parse(atob(challengeData.webauthn_login));

      // 2. Trigger browser WebAuthn authentication
      const assertion: AuthenticationResponseJSON = await startAuthentication(options);

      // 3. Send assertion to server for verification
      const verifyResp = await $api.post<WebAuthnResponse>('/auth/webauthn-login', {
        webauthn_login: btoa(JSON.stringify(assertion)),
        webauthn_login_challenge: challengeData.webauthn_login_challenge,
        webauthn_login_challenge_hmac: challengeData.webauthn_login_challenge_hmac,
        shrimp: csrfStore.shrimp,
      });

      const verifyData = verifyResp.data;

      if (isError(verifyData)) {
        error.value = verifyData.error;
        return false;
      }

      // Success - update auth state and navigate
      await authStore.setAuthenticated(true);
      await router.push('/');
      return true;
    } catch (err: any) {
      // Handle WebAuthn errors
      if (err.name === 'NotAllowedError') {
        error.value = t('web.auth.webauthn.cancelled');
      } else if (err.response?.data) {
        error.value = err.response.data.error || t('web.auth.webauthn.authFailed');
      } else {
        error.value = err.message || t('web.auth.webauthn.authFailed');
      }
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  /**
   * MFA authentication using a WebAuthn credential
   * Uses the webauthn_auth route (requires prior session/partial auth)
   *
   * @returns true if MFA verification successful
   */
  async function verifyWebAuthnMfa(): Promise<boolean> {
    if (!supported.value) {
      error.value = t('web.auth.webauthn.notSupported');
      return false;
    }

    clearError();
    isLoading.value = true;

    try {
      // 1. Get MFA challenge from server
      const challengeResp = await $api.post<WebAuthnChallengeResponse>('/auth/webauthn-auth', {
        shrimp: csrfStore.shrimp,
      });

      const challengeData = challengeResp.data;

      if (!challengeData.webauthn_auth) {
        throw new Error('Invalid challenge response');
      }

      // Parse base64-encoded WebAuthn options
      const options = JSON.parse(atob(challengeData.webauthn_auth));

      // 2. Trigger browser WebAuthn authentication
      const assertion: AuthenticationResponseJSON = await startAuthentication(options);

      // 3. Send assertion to server for verification
      const verifyResp = await $api.post<WebAuthnResponse>('/auth/webauthn-auth', {
        webauthn_auth: btoa(JSON.stringify(assertion)),
        webauthn_auth_challenge: challengeData.webauthn_auth_challenge,
        webauthn_auth_challenge_hmac: challengeData.webauthn_auth_challenge_hmac,
        shrimp: csrfStore.shrimp,
      });

      const verifyData = verifyResp.data;

      if (isError(verifyData)) {
        error.value = verifyData.error;
        return false;
      }

      return true;
    } catch (err: any) {
      // Handle WebAuthn errors
      if (err.name === 'NotAllowedError') {
        error.value = t('web.auth.webauthn.cancelled');
      } else if (err.response?.data) {
        error.value = err.response.data.error || t('web.auth.webauthn.authFailed');
      } else {
        error.value = err.message || t('web.auth.webauthn.authFailed');
      }
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

    // Actions
    registerWebAuthn,
    authenticateWebAuthn,  // Passwordless login (signin page)
    verifyWebAuthnMfa,     // MFA verification (after password login)
    clearError,
  };
}
