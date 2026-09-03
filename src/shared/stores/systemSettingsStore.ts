// src/shared/stores/systemSettingsStore.ts

import { responseSchemas } from '@/schemas/api/internal/responses';
import type { SystemSettingsDetails } from '@/schemas/contracts/config';
import { useApi } from '@/shared/composables/useApi';
import { gracefulParse } from '@/utils/schemaValidation';
import { defineStore, PiniaCustomProperties } from 'pinia';
import { ref } from 'vue';

/**
 * Type definition for SystemSettingsStore.
 */
export type SystemSettingsStore = {
  // State
  _initialized: boolean;
  record: {} | null; // response is empty object
  details: SystemSettingsDetails;

  // Actions
  fetch: () => Promise<SystemSettingsDetails>;
  dispose: () => void;
  $reset: () => void;
} & PiniaCustomProperties;

export const useSystemSettingsStore = defineStore('systemSettings', () => {
  const $api = useApi();

  // State
  const record = ref<{} | null>(null);
  const details = ref<SystemSettingsDetails | null>(null);
  const _initialized = ref(false);

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
    record.value = null;
    details.value = null;
  }

  /**
   * Reset store state to initial values
   */
  function $reset() {
    record.value = null;
    details.value = null;
    _initialized.value = false;
  }

  // Expose store interface
  return {
    // State
    record,
    details,

    // Actions
    fetch,
    dispose,
    $reset,
  };
});
