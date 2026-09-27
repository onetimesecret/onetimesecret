// src/shared/composables/useReauth.ts

import {
  reauthOfferResponseSchema,
  reauthResponseSchema,
  type ReauthOfferResponse,
  type ReauthResponse,
  type ReauthWebauthnChallenge,
} from '@/schemas/api/auth/responses/auth';
import { useApi } from '@/shared/composables/useApi';
import { useCsrfStore } from '@/shared/stores/csrfStore';
import type {
  AuthenticationResponseJSON,
  PublicKeyCredentialRequestOptionsJSON,
} from '@simplewebauthn/browser';
import { startAuthentication } from '@simplewebauthn/browser';
import { ref } from 'vue';

export type ReauthResult = 'success' | 'mfa_required' | 'error';

type ReauthPayload = {
  method: 'password' | 'webauthn';
  password?: string;
  otp_code?: string;
  recovery_code?: string;
  mfa_method?: 'webauthn';
  webauthn_auth?: AuthenticationResponseJSON;
  webauthn_auth_challenge?: string;
  webauthn_auth_challenge_hmac?: string;
  shrimp: string;
};

type AxiosLikeError = {
  response?: {
    data?: unknown;
  };
};

/* eslint-disable max-lines-per-function */
export function useReauth() {
  const $api = useApi();
  const csrfStore = useCsrfStore();

  const offer = ref<ReauthOfferResponse | null>(null);
  const mfaMethods = ref<string[]>([]);
  const isLoading = ref(false);
  const error = ref<string | null>(null);
  const errorCode = ref<string | null>(null);
  const webauthnSupported = ref(
    typeof window !== 'undefined' && typeof window.PublicKeyCredential === 'function'
  );

  function clearError() {
    error.value = null;
    errorCode.value = null;
  }

  function setError(message: string, code?: string): ReauthResult {
    error.value = message;
    errorCode.value = code ?? null;
    return 'error';
  }

  function errorMessage(err: unknown, fallback: string): string {
    const responseData = (err as AxiosLikeError).response?.data;
    if (
      responseData &&
      typeof responseData === 'object' &&
      'error' in responseData &&
      typeof responseData.error === 'string'
    ) {
      return responseData.error;
    }
    return err instanceof Error && err.message ? err.message : fallback;
  }

  async function fetchOffer(): Promise<ReauthOfferResponse | null> {
    clearError();
    isLoading.value = true;
    try {
      const response = await $api.get('/auth/reauth-offer');
      offer.value = reauthOfferResponseSchema.parse(response.data);
      return offer.value;
    } catch (err: unknown) {
      offer.value = null;
      setError(errorMessage(err, 'Unable to load re-authentication options.'));
      return null;
    } finally {
      isLoading.value = false;
    }
  }

  async function postReauth(payload: ReauthPayload): Promise<ReauthResponse> {
    try {
      const response = await $api.post('/auth/reauth', payload);
      return reauthResponseSchema.parse(response.data);
    } catch (err: unknown) {
      const responseData = (err as AxiosLikeError).response?.data;
      const parsed = reauthResponseSchema.safeParse(responseData);
      if (parsed.success) return parsed.data;
      throw err;
    }
  }

  async function completeWebauthn(
    challenge: ReauthWebauthnChallenge,
    payload: ReauthPayload
  ): Promise<ReauthResponse> {
    const assertion = await startAuthentication({
      optionsJSON: challenge.webauthn_auth as unknown as PublicKeyCredentialRequestOptionsJSON,
    });

    return postReauth({
      ...payload,
      webauthn_auth: assertion,
      webauthn_auth_challenge: challenge.webauthn_auth_challenge,
      webauthn_auth_challenge_hmac: challenge.webauthn_auth_challenge_hmac,
    });
  }

  async function processResponse(
    response: ReauthResponse,
    payload: ReauthPayload
  ): Promise<ReauthResult> {
    if ('webauthn_auth' in response) {
      const completion = await completeWebauthn(response, payload);
      return processResponse(completion, payload);
    }
    if ('success' in response) {
      mfaMethods.value = [];
      return 'success';
    }
    if ('mfa_required' in response) {
      mfaMethods.value = response.mfa_methods;
      return 'mfa_required';
    }
    return setError(response.error, response.error_code);
  }

  async function submit(payload: ReauthPayload): Promise<ReauthResult> {
    clearError();
    isLoading.value = true;
    try {
      return await processResponse(await postReauth(payload), payload);
    } catch (err: unknown) {
      if (err instanceof DOMException && err.name === 'NotAllowedError') {
        return setError('Passkey authentication was cancelled.');
      }
      return setError(errorMessage(err, 'Re-authentication failed.'));
    } finally {
      isLoading.value = false;
    }
  }

  function submitPassword(password: string, otpCode?: string, recoveryCode?: string) {
    return submit({
      method: 'password',
      password,
      ...(otpCode ? { otp_code: otpCode } : {}),
      ...(recoveryCode ? { recovery_code: recoveryCode } : {}),
      shrimp: csrfStore.shrimp,
    });
  }

  function submitPasswordWebauthn(password: string) {
    if (!webauthnSupported.value) {
      return Promise.resolve(setError('Passkeys are not supported by this browser.'));
    }
    return submit({
      method: 'password',
      password,
      mfa_method: 'webauthn',
      shrimp: csrfStore.shrimp,
    });
  }

  function submitWebauthn() {
    if (!webauthnSupported.value) {
      return Promise.resolve(setError('Passkeys are not supported by this browser.'));
    }
    return submit({ method: 'webauthn', shrimp: csrfStore.shrimp });
  }

  return {
    offer,
    mfaMethods,
    isLoading,
    error,
    errorCode,
    webauthnSupported,
    clearError,
    fetchOffer,
    submitPassword,
    submitPasswordWebauthn,
    submitWebauthn,
  };
}
