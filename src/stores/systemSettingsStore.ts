// stores/systemSettingsStore.ts

import { responseSchemas } from '@/schemas/api';
import { systemSettingsSchema, type SystemSettingsDetails } from '@/schemas/api/endpoints/colonel';
import { AxiosInstance } from 'axios';
import { defineStore, PiniaCustomProperties } from 'pinia';
import { inject, ref } from 'vue';
import { z } from 'zod';

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
  const $api = inject('api') as AxiosInstance;

  // State
  const record = ref<{} | null>(null);
  const details = ref<SystemSettingsDetails | null>(null);
  const _initialized = ref(false);

  /**
   * Fetch system settings from the API
   * @returns Validated configuration object
   */
  async function fetch() {
    const response = await $api.get('/api/v2/colonel/config');

    try {
      const validated = responseSchemas.systemSettings.parse(response.data);
      details.value = validated.details;
    } catch (validationError) {
      console.warn('System settings validation warning:', validationError);
      // Gracefully handle validation errors by using response data directly
      // This allows for partial configurations and new fields not yet in schema
      details.value = response.data.details || {};
    }

    return response.data;
  }

  /**
   * Update system settings
   * @param newConfig Updated configuration object
   */
  async function update(newConfig: SystemSettingsDetails) {
    // Validate the config before sending to API, but allow partial configurations
    try {
      // Use partial validation to allow incomplete config objects
      systemSettingsSchema.partial().parse(newConfig);
    } catch (validationError) {
      if (validationError instanceof z.ZodError) {
        const firstError = validationError.errors[0];
        throw new Error(`Validation error: ${firstError.path.join('.')} - ${firstError.message}`);
      }
      throw validationError;
    }

    const response = await $api.post('/api/v2/colonel/config', { config: newConfig });

    try {
      const validated = responseSchemas.systemSettings.parse(response.data);
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
