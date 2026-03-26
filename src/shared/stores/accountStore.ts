// src/shared/stores/accountStore.ts

import type { Account } from '@/schemas/api/account/responses/account';
import { responseSchemas } from '@/schemas/api/v3/responses';
import { gracefulParse } from '@/utils/schemaValidation';
import { useApi } from '@/shared/composables/useApi';
import { defineStore } from 'pinia';
import { ref } from 'vue';

export const useAccountStore = defineStore('account', () => {
  const $api = useApi();

  // State
  const account = ref<Account | null>(null);
  const abortController = ref<AbortController | null>(null);

  // Actions
  function abort() {
    if (abortController.value) {
      abortController.value.abort();
      abortController.value = null;
    }
  }

  async function fetch() {
    abort();
    abortController.value = new AbortController();

    const response = await $api.get('/api/account', {
      signal: abortController.value.signal,
    });
    const result = gracefulParse(responseSchemas.account, response.data, 'AccountResponse');
    if (!result.ok) {
      throw new Error('Unable to load account. Please try again.');
    }
    account.value = result.data.record;
    return account.value;
  }

  async function updateLocale(locale: string) {
    const response = await $api.post('/api/account/update-locale', { locale });
    await fetch();
    return response.data;
  }

  async function changePassword(password: string, newpassword: string, passwordconfirm: string) {
    const response = await $api.post('/api/account/change-password', {
      password,
      newpassword,
      passwordconfirm,
    });
    return response.data;
  }

  async function generateApiToken() {
    const response = await $api.post('/api/account/apitoken');
    const result = gracefulParse(responseSchemas.apiToken, response.data, 'ApiTokenResponse');
    if (!result.ok) {
      throw new Error('Unable to generate API token. Please try again.');
    }
    await fetch();
    return result.data;
  }

  async function updateNotificationPreference(field: string, value: boolean) {
    const response = await $api.post('/api/account/update-notification-preference', {
      field,
      value,
    });
    // NOTE: We refetch the full account rather than merging the response locally.
    // This guarantees consistency but costs an extra request. If this becomes a
    // pattern worth optimizing, consider having update endpoints return the full
    // object or implementing optimistic local merges across the codebase.
    await fetch();
    return response.data;
  }

  function $reset() {
    abort();
    account.value = null;
  }

  return {
    // State
    account,

    // Actions
    fetch,
    updateLocale,
    changePassword,
    generateApiToken,
    updateNotificationPreference,
    abort,
    $reset,
  };
});
