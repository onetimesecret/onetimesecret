// src/shared/composables/useApi.ts

import type { AxiosInstance } from 'axios';
import { inject } from 'vue';

/**
 * Safely inject the Axios API instance provided via Vue's dependency injection.
 *
 * All composables and stores that need `$api` should call `useApi()` instead of
 * `inject('api') as AxiosInstance` directly. This avoids silent `undefined`
 * when the provider is missing (SSR, test setup, mounting outside AppProvider)
 * and surfaces a descriptive error immediately.
 */
export function useApi(): AxiosInstance {
  const $api = inject<AxiosInstance>('api');
  if (!$api) {
    throw new Error(
      'useApi(): No Axios instance found. ' +
      'Ensure the component is mounted inside a provider that calls ' +
      'app.provide("api", axiosInstance).'
    );
  }
  return $api;
}
