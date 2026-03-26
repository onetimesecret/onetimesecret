// src/shared/stores/systemSettingsStore.ts

import { systemSettingsSchema } from '@/schemas/api/account/responses/colonel';
import { type SystemSettingsDetails } from '@/schemas/contracts/config';
import { responseSchemas } from '@/schemas/api/internal/responses';
import { gracefulParse } from '@/utils/schemaValidation';
import { useApi } from '@/shared/composables/useApi';
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
  update: (config: SystemSettingsDetails) => Promise<void>;
  dispose: () => void;
  $reset: () => void;
} & PiniaCustomProperties;

export const useSystemSettingsStore = defineStore('colonel', () => {
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
    const result = gracefulParse(responseSchemas.systemSettings, response.data, 'SystemSettingsResponse');
    if (!result.ok) {
      details.value = response.data.details || {};
      return response.data;
    }
    details.value = result.data.details ?? null;

    return response.data;
  }

  /**
   * Update system settings
   * @param newConfig Updated configuration object
   */
  async function update(newConfig: SystemSettingsDetails) {
    // Validate the config before sending to API, but allow partial configurations
    const payloadResult = gracefulParse(systemSettingsSchema.partial(), newConfig, 'SystemSettingsPayload');
    if (!payloadResult.ok) {
      const firstError = payloadResult.error?.issues[0];
      throw new Error(
        firstError
          ? `Validation error: ${firstError.path.join('.')} - ${firstError.message}`
          : 'Invalid system settings data.'
      );
    }

    const response = await $api.post('/api/colonel/config', { config: newConfig });

    // Admin config schemas may lag behind server changes (see fetch above)
    const responseResult = gracefulParse(responseSchemas.systemSettings, response.data, 'SystemSettingsResponse');
    if (!responseResult.ok) {
      record.value = response.data.record || {};
      details.value = response.data.details || {};
      return response.data;
    }
    record.value = responseResult.data.record;
    details.value = responseResult.data.details ?? null;
    return responseResult.data;
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
    update,
    dispose,
    $reset,
  };
});
