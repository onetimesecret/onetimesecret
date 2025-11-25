// src/stores/colonelInfoStore.ts

import {
  type SystemSettingsDetails,
  type ColonelStatsDetails,
  type ColonelInfoDetails,
  type ColonelUsersDetails,
  type ColonelUser,
  type Pagination,
  type ColonelSecretsDetails,
  type ColonelSecret,
  type DatabaseMetricsDetails,
  type RedisMetricsDetails,
  type BannedIPsDetails,
  type BannedIP,
  type UsageExportDetails,
  type CustomDomainsDetails,
  type CustomDomain,
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
  secrets: ColonelSecret[];
  secretsPagination: Pagination | null;
  databaseMetrics: DatabaseMetricsDetails | null;
  redisMetrics: RedisMetricsDetails | null;
  bannedIPs: BannedIP[];
  usageExport: UsageExportDetails | null;

  // Actions
  fetchInfo: () => Promise<ColonelInfoDetails>;
  fetchStats: () => Promise<ColonelStats>;
  fetchUsers: (page?: number, perPage?: number, roleFilter?: string) => Promise<ColonelUsersDetails>;
  fetchSecrets: (page?: number, perPage?: number) => Promise<ColonelSecretsDetails>;
  fetchDatabaseMetrics: () => Promise<DatabaseMetricsDetails>;
  fetchRedisMetrics: () => Promise<RedisMetricsDetails>;
  fetchBannedIPs: () => Promise<BannedIPsDetails>;
  banIP: (ipAddress: string, reason?: string) => Promise<void>;
  unbanIP: (ipAddress: string) => Promise<void>;
  fetchUsageExport: (startDate?: number, endDate?: number) => Promise<UsageExportDetails>;
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
  const secrets = ref<ColonelSecret[]>([]);
  const secretsPagination = ref<Pagination | null>(null);
  const databaseMetrics = ref<DatabaseMetricsDetails | null>(null);
  const redisMetrics = ref<RedisMetricsDetails | null>(null);
  const bannedIPs = ref<BannedIP[]>([]);
  const currentIP = ref<string | null>(null);
  const customDomains = ref<CustomDomain[]>([]);
  const customDomainsPagination = ref<Pagination | null>(null);
  const usageExport = ref<UsageExportDetails | null>(null);
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

  // Fetch secrets list with optional pagination
  async function fetchSecrets(page = 1, perPage = 50) {
    isLoading.value = true;
    try {
      const params = new URLSearchParams();
      params.append('page', page.toString());
      params.append('per_page', perPage.toString());

      const response = await $api.get(`/api/colonel/secrets?${params.toString()}`);
      const validated = responseSchemas.colonelSecrets.parse(response.data);

      if (validated.details) {
        secrets.value = validated.details.secrets;
        secretsPagination.value = validated.details.pagination;
      }

      return validated.details!;
    } catch (error) {
      console.error('Failed to fetch colonel secrets:', error);
      secrets.value = [];
      secretsPagination.value = null;
      throw error;
    } finally {
      isLoading.value = false;
    }
  }

  // Fetch database metrics
  async function fetchDatabaseMetrics() {
    isLoading.value = true;
    try {
      const response = await $api.get('/api/colonel/system/database');
      const validated = responseSchemas.databaseMetrics.parse(response.data);

      if (validated.details) {
        databaseMetrics.value = validated.details;
      }

      return validated.details!;
    } catch (error) {
      console.error('Failed to fetch database metrics:', error);
      databaseMetrics.value = null;
      throw error;
    } finally {
      isLoading.value = false;
    }
  }

  // Fetch Redis metrics
  async function fetchRedisMetrics() {
    isLoading.value = true;
    try {
      const response = await $api.get('/api/colonel/system/redis');
      const validated = responseSchemas.redisMetrics.parse(response.data);

      if (validated.details) {
        redisMetrics.value = validated.details;
      }

      return validated.details!;
    } catch (error) {
      console.error('Failed to fetch Redis metrics:', error);
      redisMetrics.value = null;
      throw error;
    } finally {
      isLoading.value = false;
    }
  }

  // Fetch banned IPs list
  async function fetchBannedIPs() {
    isLoading.value = true;
    try {
      const response = await $api.get('/api/colonel/banned-ips');
      const validated = responseSchemas.bannedIPs.parse(response.data);

      if (validated.details) {
        currentIP.value = validated.details.current_ip;
        bannedIPs.value = validated.details.banned_ips;
      }

      return validated.details!;
    } catch (error) {
      console.error('Failed to fetch banned IPs:', error);
      bannedIPs.value = [];
      currentIP.value = null;
      throw error;
    } finally {
      isLoading.value = false;
    }
  }

  // Ban an IP address
  async function banIP(ipAddress: string, reason?: string) {
    isLoading.value = true;
    try {
      await $api.post('/api/colonel/banned-ips', {
        ip_address: ipAddress,
        reason: reason || '',
      });

      // Refresh the banned IPs list
      await fetchBannedIPs();
    } catch (error) {
      console.error('Failed to ban IP:', error);
      throw error;
    } finally {
      isLoading.value = false;
    }
  }

  // Unban an IP address
  async function unbanIP(ipAddress: string) {
    isLoading.value = true;
    try {
      await $api.delete(`/api/colonel/banned-ips/${encodeURIComponent(ipAddress)}`);

      // Refresh the banned IPs list
      await fetchBannedIPs();
    } catch (error) {
      console.error('Failed to unban IP:', error);
      throw error;
    } finally {
      isLoading.value = false;
    }
  }

  // Fetch custom domains list with optional pagination
  async function fetchCustomDomains(page = 1, perPage = 50) {
    isLoading.value = true;
    try {
      const params = new URLSearchParams();
      params.append('page', page.toString());
      params.append('per_page', perPage.toString());

      const response = await $api.get(`/api/colonel/domains?${params.toString()}`);
      const validated = responseSchemas.customDomains.parse(response.data);

      if (validated.details) {
        customDomains.value = validated.details.domains;
        customDomainsPagination.value = validated.details.pagination;
      }

      return validated.details!;
    } catch (error) {
      console.error('Failed to fetch custom domains:', error);
      customDomains.value = [];
      customDomainsPagination.value = null;
      throw error;
    } finally {
      isLoading.value = false;
    }
  }

  // Fetch usage export data
  async function fetchUsageExport(startDate?: number, endDate?: number) {
    isLoading.value = true;
    try {
      const params = new URLSearchParams();
      if (startDate) {
        params.append('start_date', startDate.toString());
      }
      if (endDate) {
        params.append('end_date', endDate.toString());
      }

      const response = await $api.get(`/api/colonel/usage/export?${params.toString()}`);
      const validated = responseSchemas.usageExport.parse(response.data);

      if (validated.details) {
        usageExport.value = validated.details;
      }

      return validated.details!;
    } catch (error) {
      console.error('Failed to fetch usage export:', error);
      usageExport.value = null;
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
    secrets.value = [];
    secretsPagination.value = null;
    databaseMetrics.value = null;
    redisMetrics.value = null;
    bannedIPs.value = [];
    currentIP.value = null;
    usageExport.value = null;
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
    secrets.value = [];
    secretsPagination.value = null;
    databaseMetrics.value = null;
    redisMetrics.value = null;
    bannedIPs.value = [];
    currentIP.value = null;
    usageExport.value = null;
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
    secrets,
    secretsPagination,
    databaseMetrics,
    redisMetrics,
    bannedIPs,
    currentIP,
    customDomains,
    customDomainsPagination,
    usageExport,
    isLoading,

    // Actions
    fetch,
    fetchStats,
    fetchUsers,
    fetchSecrets,
    fetchDatabaseMetrics,
    fetchRedisMetrics,
    fetchBannedIPs,
    banIP,
    unbanIP,
    fetchCustomDomains,
    fetchUsageExport,
    dispose,
    $reset,
  };
});
