// src/stores/mutableConfigStore.ts

import { responseSchemas } from '@/schemas/api';
import { mutableConfigSchema, type MutableConfigDetails } from '@/schemas/api/endpoints/colonel';
import { AxiosInstance } from 'axios';
import { defineStore, PiniaCustomProperties } from 'pinia';
import { inject, ref } from 'vue';
import { z } from 'zod/v4';

/**
 * Type definition for MutableConfigStore.
 */
export type MutableConfigStore = {
  // State
  _initialized: boolean;
  record: {} | null; // response is empty object
  details: MutableConfigDetails;

  // Actions
  fetch: () => Promise<MutableConfigDetails>;
  update: (config: MutableConfigDetails) => Promise<void>;
  dispose: () => void;
  $reset: () => void;
} & PiniaCustomProperties;

export const useMutableConfigStore = defineStore('colonel', () => {
  const $api = inject('api') as AxiosInstance;

  // State
  const record = ref<{} | null>(null);
  const details = ref<MutableConfigDetails | null>(null);
  const _initialized = ref(false);

  /**
   * Fetch mutable config from the API
   * @returns Validated configuration object
   */
  async function fetch() {
    const response = await $api.get('/api/v2/colonel/config');

    try {
      const validated = responseSchemas.mutableConfig.parse(response.data);
      details.value = validated.details as MutableConfigDetails | null;
    } catch (validationError) {
      console.warn('Mutable Config validation warning:', validationError);
      // Gracefully handle validation errors by using response data directly
      // This allows for partial configurations and new fields not yet in schema
      details.value = (response.data.details || null) as MutableConfigDetails | null;
    }

    return response.data;
  }

  /**
   * Update mutable config
   * @param newConfig Updated configuration object
   */
  async function update(newConfig: MutableConfigDetails) {
    // Validate the config before sending to API, but allow partial configurations
    try {
      // Use partial validation to allow incomplete config objects
      mutableConfigSchema.partial().parse(newConfig);
    } catch (validationError) {
      if (validationError instanceof z.ZodError) {
        const firstError = validationError.issues[0];
        throw new Error(`Validation error: ${firstError.path.join('.')} - ${firstError.message}`);
      }
      throw validationError;
    }

    const response = await $api.post('/api/v2/colonel/config', { config: newConfig });

    try {
      const validated = responseSchemas.mutableConfig.parse(response.data);
      record.value = validated.record;
      details.value = validated.details as MutableConfigDetails | null;
      return validated;
    } catch (validationError) {
      console.warn('Response validation warning:', validationError);
      // Fallback to using response data directly if validation fails
      record.value = response.data.record || {};
      details.value = (response.data.details || null) as MutableConfigDetails | null;
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
