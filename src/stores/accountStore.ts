// src/stores/accountStore.ts

import type { Account } from '@/schemas/api/endpoints/account';
import { responseSchemas } from '@/schemas/api/responses';
import { AxiosInstance } from 'axios';
import { defineStore } from 'pinia';
import { inject, ref } from 'vue';

/* eslint-disable max-lines-per-function */
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

    const response = await $api.get('/api/v2/account', {
      signal: abortController.value.signal,
    });
    const validated = responseSchemas.account.parse(response.data);
    account.value = validated.record;
    return account.value;
  }

  async function updateLocale(locale: string) {
    const response = await $api.post('/api/v2/account/update-locale', { locale });
    await fetch();
    return response.data;
  }

  async function changePassword(password: string, newpassword: string, passwordconfirm: string) {
    const response = await $api.post('/api/v2/account/change-password', {
      password,
      newpassword,
      passwordconfirm,
    });
    return response.data;
  }

  async function generateApiToken() {
    const response = await $api.post('/api/v2/account/apitoken');
    const validated = responseSchemas.apiToken.parse(response.data);
    await fetch();
    return validated;
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
    abort,
    $reset,
  };
});
