// src/stores/colonelInfoStore.ts

import {
  type SystemSettingsDetails,
  type ColonelStatsDetails,
  type ColonelInfoDetails,
  type ColonelUsersDetails,
  type ColonelUser,
  type Pagination,
} from '@/schemas/api/account/endpoints/colonel';
import { responseSchemas } from '@/schemas/api/v3';
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
  users: ColonelUser[];
  usersPagination: Pagination | null;

  // Actions
  fetchInfo: () => Promise<ColonelInfoDetails>;
  fetchStats: () => Promise<ColonelStats>;
  fetchUsers: (page?: number, perPage?: number, roleFilter?: string) => Promise<ColonelUsersDetails>;
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
  const users = ref<ColonelUser[]>([]);
  const usersPagination = ref<Pagination | null>(null);
  const _initialized = ref(false);
  const isLoading = ref(false);

  // Actions
  async function fetch() {
    isLoading.value = true;
    try {
      const response = await $api.get('/api/colonel/info');
      const validated = responseSchemas.colonelInfo.parse(response.data);
      details.value = validated.details as any;
      // Also populate stats from the full response
      if (validated.details) {
        stats.value = {
          counts: (validated.details as any).counts,
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
      const response = await $api.get('/api/colonel/stats');
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

  // Fetch users list with optional pagination
  async function fetchUsers(page = 1, perPage = 50, roleFilter?: string) {
    isLoading.value = true;
    try {
      const params = new URLSearchParams();
      params.append('page', page.toString());
      params.append('per_page', perPage.toString());
      if (roleFilter) {
        params.append('role', roleFilter);
      }

      const response = await $api.get(`/api/colonel/users?${params.toString()}`);
      const validated = responseSchemas.colonelUsers.parse(response.data);

      if (validated.details) {
        users.value = validated.details.users;
        usersPagination.value = validated.details.pagination;
      }

      return validated.details!;
    } catch (error) {
      console.error('Failed to fetch colonel users:', error);
      users.value = [];
      usersPagination.value = null;
      throw error;
    } finally {
      isLoading.value = false;
    }
  }

  function dispose() {
    record.value = null;
    details.value = null;
    stats.value = null;
    users.value = [];
    usersPagination.value = null;
  }

  /**
   * Reset store state to initial values
   */
  function $reset() {
    record.value = null;
    details.value = null;
    stats.value = null;
    users.value = [];
    usersPagination.value = null;
    _initialized.value = false;
  }

  // Expose store interface
  return {
    // State
    record,
    details,
    stats,
    users,
    usersPagination,
    isLoading,

    // Actions
    fetch,
    fetchStats,
    fetchUsers,
    dispose,
    $reset,
  };
});
