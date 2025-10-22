// src/composables/useMagicLink.ts
import { inject, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useCsrfStore } from '@/stores/csrfStore';
import type { AxiosInstance } from 'axios';

// Response types matching Rodauth JSON format
type MagicLinkSuccessResponse = {
  success: string;
};

type MagicLinkErrorResponse = {
  error: string;
  'field-error'?: [string, string];
};

type MagicLinkResponse = MagicLinkSuccessResponse | MagicLinkErrorResponse;

function isError(response: MagicLinkResponse): response is MagicLinkErrorResponse {
  return 'error' in response;
}

/**
 * Magic Link authentication composable
 *
 * Handles passwordless login via email links (Rodauth email_auth feature)
 *
 * @example
 * ```ts
 * const { requestMagicLink, sent, isLoading, error } = useMagicLink();
 *
 * // Request magic link
 * const success = await requestMagicLink('user@example.com');
 * if (success && sent.value) {
 *   // Show "check your email" message
 * }
 * ```
 */
export function useMagicLink() {
  const $api = inject('api') as AxiosInstance;
  const { t } = useI18n();
  const csrfStore = useCsrfStore();

  const isLoading = ref(false);
  const error = ref<string | null>(null);
  const fieldError = ref<[string, string] | null>(null);
  const sent = ref(false);

  /**
   * Clears error and sent state
   */
  function clearState() {
    error.value = null;
    fieldError.value = null;
    sent.value = false;
  }

  /**
   * Requests a magic link to be sent to the user's email
   *
   * @param email - User's email address
   * @returns true if request successful (link sent)
   */
  async function requestMagicLink(email: string): Promise<boolean> {
    clearState();
    isLoading.value = true;

    try {
      const response = await $api.post<MagicLinkResponse>('/auth/email-login-request', {
        login: email,
        shrimp: csrfStore.shrimp,
      });

      const data = response.data;

      if (isError(data)) {
        error.value = data.error;
        fieldError.value = data['field-error'] || null;
        return false;
      }

      // Success - magic link sent
      sent.value = true;
      return true;
    } catch (err: any) {
      // Handle error responses
      if (err.response?.data) {
        const errorData = err.response.data;
        error.value = errorData.error || t('auth.magicLink.requestFailed');
        fieldError.value = errorData['field-error'] || null;
      } else {
        error.value = t('auth.magicLink.networkError');
      }
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  return {
    // State
    isLoading,
    error,
    fieldError,
    sent,

    // Actions
    requestMagicLink,
    clearState,
  };
}
