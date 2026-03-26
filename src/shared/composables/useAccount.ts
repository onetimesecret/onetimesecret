// src/shared/composables/useAccount.ts

/**
 * Account information composable
 * Handles fetching and managing user account data
 */

import { accountInfoResponseSchema, type AccountInfoResponse } from '@/schemas/api/auth/responses/auth';
import type { AccountInfo } from '@/types/auth';
import { ref } from 'vue';

import { useApi } from '@/shared/composables/useApi';

export function useAccount() {
  const $api = useApi();

  const accountInfo = ref<AccountInfo | null>(null);
  const isLoading = ref(false);
  const error = ref<string | null>(null);

  /**
   * Clears error state
   */
  function clearError() {
    error.value = null;
  }

  /**
   * Fetches account information from backend
   *
   * @returns Account info object or null on error
   */
  async function fetchAccountInfo(): Promise<AccountInfo | null> {
    clearError();
    isLoading.value = true;

    try {
      const response = await $api.get<AccountInfoResponse>('/auth/account');
      const validated = accountInfoResponseSchema.parse(response.data);

      accountInfo.value = validated;
      return validated;
    } catch (err: unknown) {
      const axiosErr = err as { response?: { data?: { error?: string } } };
      error.value = axiosErr?.response?.data?.error || 'Failed to load account information';
      return null;
    } finally {
      isLoading.value = false;
    }
  }

  /**
   * Refreshes account information
   * Alias for fetchAccountInfo for clarity in usage
   */
  async function refreshAccountInfo(): Promise<void> {
    await fetchAccountInfo();
  }

  return {
    accountInfo,
    isLoading,
    error,
    fetchAccountInfo,
    refreshAccountInfo,
    clearError,
  };
}
