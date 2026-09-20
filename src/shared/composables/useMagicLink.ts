// src/shared/composables/useMagicLink.ts

import { useAuthStore } from '@/shared/stores/authStore';
import { useCsrfStore } from '@/shared/stores/csrfStore';
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';

import { ensureAuthenticated } from '@/shared/composables/authCompletion';
import { useApi } from '@/shared/composables/useApi';
import { usePostAuthRedirect } from '@/shared/composables/usePostAuthRedirect';

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
  const $api = useApi();
  const { t } = useI18n();
  const authStore = useAuthStore();
  const csrfStore = useCsrfStore();
  const { navigateAfterAuth } = usePostAuthRedirect();
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
    } catch (err: unknown) {
      // On 403 (CSRF token rejection), the Axios error interceptor already
      // refreshed the token from the response header. Retry once.
      if ((err as { response?: { status?: number } })?.response?.status === 403) {
        try {
          return await doMagicLinkRequest(email);
        } catch (_retryErr: unknown) {
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
      // #4497 item 8: setAuthenticated returns the RefreshOutcome. Only
      // navigate to the (protected) post-auth destination when the snapshot
      // was applied AND the status is `authenticated`. Retry verification —
      // never re-POST the single-use magic-link key.
      const outcome = await ensureAuthenticated(authStore, 'magic-link');
      if (outcome === 'superseded') return false; // Newer coordinator run owns this.
      if (outcome !== 'applied') {
        // TODO: [#4497 item 8] confirm error UX with design — reusing the
        // sessionExpired copy since the failure mode is functionally the
        // same (verification could not be completed).
        error.value = t('web.auth.magicLink.sessionExpired');
        return false;
      }
      // A magic link is a PRIMARY factor: the session is live, so honour the
      // same destination precedence as a password login (billing intent >
      // validated ?redirect > '/') instead of dumping the user on the
      // dashboard and losing whatever they were trying to reach.
      await navigateAfterAuth();
      return true;
    } catch (err: unknown) {
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
