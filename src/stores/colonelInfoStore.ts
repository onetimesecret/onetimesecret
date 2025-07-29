// src/stores/colonelInfoStore.ts

import { responseSchemas, type ColonelInfoDetails } from '@/schemas/api';
import { type SystemSettingsDetails, type ColonelStatsDetails } from '@/schemas/api/endpoints/colonel';
import { AxiosInstance } from 'axios';
import { defineStore, PiniaCustomProperties } from 'pinia';
import { inject, ref } from 'vue';

// Use the imported type from schemas
export type ColonelStats = ColonelStatsDetails;

/**
 * Type definition for ColonelInfoStore.
 */
export type ColonelInfoStore = {
  // State
  _initialized: boolean;
  record: {} | null; // response is empty object
  details: ColonelInfoDetails;
  stats: ColonelStats | null;
  config: SystemSettingsDetails | null;

  // Actions
  fetchInfo: () => Promise<ColonelInfoDetails>;
  fetchStats: () => Promise<ColonelStats>;
  fetchConfig: () => Promise<SystemSettingsDetails>;
  updateConfig: (config: SystemSettingsDetails) => Promise<void>;
  dispose: () => void;
  $reset: () => void;
} & PiniaCustomProperties;

export const useColonelInfoStore = defineStore('colonel', () => {
  const $api = inject('api') as AxiosInstance;

  // State
  const record = ref<{} | null>(null);
  const details = ref<ColonelInfoDetails | null>(null);
  const stats = ref<ColonelStats | null>(null);
  const _initialized = ref(false);
  const isLoading = ref(false);

  // Actions
  async function fetch() {
    isLoading.value = true;
    try {
      const response = await $api.get('/api/v2/colonel/info');
      const validated = responseSchemas.colonelInfo.parse(response.data);
      details.value = validated.details as any;
      // Also populate stats from the full response
      if (validated.details) {
        stats.value = {
          counts: (validated.details as any).counts
        };
      }
      return validated.record;
    } catch (error) {
      console.error('Failed to fetch colonel info:', error);
      throw error;
    } finally {
      isLoading.value = false;
    }
  }

  // Lightweight stats-only fetch for dashboard
  async function fetchStats() {
    isLoading.value = true;
    try {
      // Use the dedicated stats endpoint for better performance
      const response = await $api.get('/api/v2/colonel/stats');
      const validated = responseSchemas.colonelStats.parse(response.data);
      if (validated.details) {
        stats.value = validated.details as any;
      }
      return stats.value!;
    } catch (error) {
      console.error('Failed to fetch colonel stats:', error);
      // Fallback to null stats on error
      stats.value = null;
      throw error;
    } finally {
      isLoading.value = false;
    }
  }

  function dispose() {
    record.value = null;
    details.value = null;
    stats.value = null;
  }

  /**
   * Reset store state to initial values
   */
  function $reset() {
    record.value = null;
    details.value = null;
    stats.value = null;
    _initialized.value = false;
  }

  // Expose store interface
  return {
    // State
    record,
    details,
    stats,
    isLoading,

    // Actions
    fetch,
    fetchStats,
    dispose,
    $reset,
  };
});
