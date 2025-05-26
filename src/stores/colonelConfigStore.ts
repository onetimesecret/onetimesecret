// stores/colonelConfigStore.ts

import { responseSchemas } from '@/schemas/api';
import { colonelConfigSchema, type ColonelConfigDetails } from '@/schemas/api/endpoints/colonel';
import { AxiosInstance } from 'axios';
import { defineStore, PiniaCustomProperties } from 'pinia';
import { inject, ref } from 'vue';
import { z } from 'zod';

/**
 * Type definition for ColonelConfigStore.
 */
export type ColonelConfigStore = {
  // State
  _initialized: boolean;
  record: {} | null; // response is empty object
  details: ColonelConfigDetails;

  // Actions
  fetch: () => Promise<ColonelConfigDetails>;
  update: (config: ColonelConfigDetails) => Promise<void>;
  dispose: () => void;
  $reset: () => void;
} & PiniaCustomProperties;

export const useColonelConfigStore = defineStore('colonel', () => {
  const $api = inject('api') as AxiosInstance;

  // State
  const record = ref<{} | null>(null);
  const details = ref<ColonelConfigDetails | null>(null);
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
    } catch (ZodError) {
      console.error('Colonel config validation error:', ZodError);
      details.value = response.data.details;
    }

    return response.data;
  }

  /**
   * Update colonel configuration
   * @param newConfig Updated configuration object
   */
  async function update(newConfig: ColonelConfigDetails) {
    // Validate the config before sending to API
    try {
      colonelConfigSchema.parse(newConfig);
    } catch (validationError) {
      if (validationError instanceof z.ZodError) {
        const firstError = validationError.errors[0];
        throw new Error(`Validation error: ${firstError.path.join('.')} - ${firstError.message}`);
      }
      throw validationError;
    }

    const response = await $api.post('/api/v2/colonel/config', { config: newConfig });

    const validated = responseSchemas.metadata.parse(response.data);
    record.value = validated.record;

    // Update local state with the received config if available, otherwise use what we sent
    details.value = validated.details;
    return validated;
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
