// stores/colonelSettingsStore.ts

import { responseSchemas } from '@/schemas/api';
import { colonelConfigSchema, type ColonelSettingsDetails } from '@/schemas/api/endpoints/colonel';
import { AxiosInstance } from 'axios';
import { defineStore, PiniaCustomProperties } from 'pinia';
import { inject, ref } from 'vue';
import { z } from 'zod';

/**
 * Type definition for ColonelSettingsStore.
 */
export type ColonelSettingsStore = {
  // State
  _initialized: boolean;
  record: {} | null; // response is empty object
  details: ColonelSettingsDetails;

  // Actions
  fetch: () => Promise<ColonelSettingsDetails>;
  update: (config: ColonelSettingsDetails) => Promise<void>;
  dispose: () => void;
  $reset: () => void;
} & PiniaCustomProperties;

export const useColonelSettingsStore = defineStore('colonel', () => {
  const $api = inject('api') as AxiosInstance;

  // State
  const record = ref<{} | null>(null);
  const details = ref<ColonelSettingsDetails | null>(null);
  const _initialized = ref(false);

  /**
   * Fetch colonel configuration from the API
   * @returns Validated configuration object
   */
  async function fetch() {
    const response = await $api.get('/api/v2/colonel/config');

    try {
      const validated = responseSchemas.colonelConfig.parse(response.data);
      details.value = validated.details;
    } catch (validationError) {
      console.warn('Colonel config validation warning:', validationError);
      // Gracefully handle validation errors by using response data directly
      // This allows for partial configurations and new fields not yet in schema
      details.value = response.data.details || {};
    }

    return response.data;
  }

  /**
   * Update colonel configuration
   * @param newConfig Updated configuration object
   */
  async function update(newConfig: ColonelSettingsDetails) {
    // Validate the config before sending to API, but allow partial configurations
    try {
      // Use partial validation to allow incomplete config objects
      colonelConfigSchema.partial().parse(newConfig);
    } catch (validationError) {
      if (validationError instanceof z.ZodError) {
        const firstError = validationError.errors[0];
        throw new Error(`Validation error: ${firstError.path.join('.')} - ${firstError.message}`);
      }
      throw validationError;
    }

    const response = await $api.post('/api/v2/colonel/config', { config: newConfig });

    try {
      const validated = responseSchemas.colonelConfig.parse(response.data);
      record.value = validated.record;
      details.value = validated.details;
      return validated;
    } catch (validationError) {
      console.warn('Response validation warning:', validationError);
      // Fallback to using response data directly if validation fails
      record.value = response.data.record || {};
      details.value = response.data.details || {};
      return response.data;
    }
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
