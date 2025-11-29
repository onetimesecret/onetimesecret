// src/stores/accountStore.ts

import type { Account } from '@/schemas/api/account/endpoints/account';
import { responseSchemas } from '@/schemas/api/v3/responses';
import { AxiosInstance } from 'axios';
import { defineStore } from 'pinia';
import { inject, ref } from 'vue';

export const useAccountStore = defineStore('account', () => {
  const $api = inject('api') as AxiosInstance;

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

    const response = await $api.get('/api/account/account', {
      signal: abortController.value.signal,
    });
    const validated = responseSchemas.account.parse(response.data);
    account.value = validated.record;
    return account.value;
  }

  async function updateLocale(locale: string) {
    const response = await $api.post('/api/account/account/update-locale', { locale });
    await fetch();
    return response.data;
  }

  async function changePassword(password: string, newpassword: string, passwordconfirm: string) {
    const response = await $api.post('/api/account/account/change-password', {
      password,
      newpassword,
      passwordconfirm,
    });
    return response.data;
  }

  async function generateApiToken() {
    const response = await $api.post('/api/account/account/apitoken');
    const validated = responseSchemas.apiToken.parse(response.data);
    await fetch();
    return validated;
  }

  async function updateNotificationPreference(field: string, value: boolean) {
    const response = await $api.post('/api/account/account/update-notification-preference', {
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
