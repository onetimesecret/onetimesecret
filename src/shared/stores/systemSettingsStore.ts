// src/shared/stores/systemSettingsStore.ts

import { responseSchemas } from '@/schemas/api/internal/responses';
import type { SystemSettingsDetails } from '@/schemas/contracts/config';
import { useApi } from '@/shared/composables/useApi';
import { gracefulParse } from '@/utils/schemaValidation';
import { defineStore, PiniaCustomProperties } from 'pinia';
import { ref } from 'vue';

/**
 * Type definition for SystemSettingsStore.
 *
 * Read-only: the colonel config write path was removed, so this store only
 * holds the fetched `details` (no `record`, no write/initialized flags).
 */
export type SystemSettingsStore = {
  // State
  details: SystemSettingsDetails;

  // Actions
  fetch: () => Promise<SystemSettingsDetails>;
  dispose: () => void;
  $reset: () => void;
} & PiniaCustomProperties;

export const useSystemSettingsStore = defineStore('systemSettings', () => {
  const $api = useApi();

  // State
  const details = ref<SystemSettingsDetails | null>(null);

  /**
   * Fetch system settings from the API
   * @returns Validated configuration object
   */
  async function fetch() {
    const response = await $api.get('/api/colonel/config');

    // Admin config schemas may lag behind server changes, so validation
    // failures degrade to raw data rather than blocking the admin UI.
    const result = gracefulParse(
      responseSchemas.systemSettings,
      response.data,
      'SystemSettingsResponse'
    );
    if (!result.ok) {
      details.value = response.data.details || {};
      return response.data;
    }
    details.value = result.data.details ?? null;

    return response.data;
  }

  function dispose() {
    details.value = null;
  }

  /**
   * Reset store state to initial values
   */
  function $reset() {
    details.value = null;
  }

  // Expose store interface
  return {
    // State
    details,

    // Actions
    fetch,
    dispose,
    $reset,
  };
});
