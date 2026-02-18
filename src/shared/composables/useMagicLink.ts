// src/shared/composables/useMagicLink.ts

import { useAuthStore } from '@/shared/stores/authStore';
import { useCsrfStore } from '@/shared/stores/csrfStore';
import type { AxiosInstance } from 'axios';
import { inject, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';

import { extractError } from './helpers/magicLinkHelpers';

type MagicLinkSuccessResponse = { success: string };
type MagicLinkErrorResponse = { error: string; 'field-error'?: [string, string] };
type MagicLinkResponse = MagicLinkSuccessResponse | MagicLinkErrorResponse;

function isError(response: MagicLinkResponse): response is MagicLinkErrorResponse {
  return 'error' in response;
}

/** Magic Link authentication composable */
/* eslint-disable max-lines-per-function */
export function useMagicLink() {
  const $api = inject('api') as AxiosInstance;
  const { t } = useI18n();
  const router = useRouter();
  const authStore = useAuthStore();
  const csrfStore = useCsrfStore();
  const isLoading = ref(false);
  const error = ref<string | null>(null);
  const fieldError = ref<[string, string] | null>(null);
  const sent = ref(false);

  function clearState() {
    error.value = null;
    fieldError.value = null;
    sent.value = false;
  }

  async function doMagicLinkRequest(email: string): Promise<boolean> {
    const response = await $api.post<MagicLinkResponse>(
      '/auth/email-login-request',
      { login: email, shrimp: csrfStore.shrimp }
    );
    if (isError(response.data)) {
      error.value = response.data.error;
      fieldError.value = response.data['field-error'] || null;
      return false;
    }
    sent.value = true;
    return true;
  }

  async function requestMagicLink(email: string): Promise<boolean> {
    clearState();
    isLoading.value = true;
    try {
      return await doMagicLinkRequest(email);
    } catch (err: any) {
      // On 403 (CSRF token rejection), the Axios error interceptor already
      // refreshed the token from the response header. Retry once.
      if (err.response?.status === 403) {
        try {
          return await doMagicLinkRequest(email);
        } catch (_retryErr: any) {
          error.value = t('web.auth.magicLink.sessionExpired');
          return false;
        }
      }
      const [errMsg, fieldErr] = extractError(err, t, 'web.auth.magicLink.requestFailed');
      error.value = errMsg;
      fieldError.value = fieldErr;
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  async function verifyMagicLink(key: string): Promise<boolean> {
    clearState();
    isLoading.value = true;
    try {
      const response = await $api.post<MagicLinkResponse>(
        '/auth/email-login',
        { key, shrimp: csrfStore.shrimp }
      );
      if (isError(response.data)) {
        error.value = response.data.error;
        fieldError.value = response.data['field-error'] || null;
        return false;
      }
      await authStore.setAuthenticated(true);
      await router.push('/');
      return true;
    } catch (err: any) {
      const [errMsg, fieldErr] = extractError(err, t, 'web.auth.magicLink.loginFailed');
      error.value = errMsg;
      fieldError.value = fieldErr;
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  return {
    isLoading,
    error,
    fieldError,
    sent,
    requestMagicLink,
    verifyMagicLink,
    clearState,
  };
}
