// src/shared/stores/colonelInfoStore.ts

import {
  type ColonelStatsDetails,
  type ColonelInfoDetails,
  type ColonelUser,
  type Pagination,
  type ColonelSecret,
  type DatabaseMetricsDetails,
  type RedisMetricsDetails,
  type BannedIP,
  type UsageExportDetails,
  type ColonelCustomDomain,
  type ColonelOrganization,
  type ColonelOrganizationsFilters,
  type InvestigateOrganizationResult,
  type QueueMetrics,
} from '@/schemas/api/account/responses/colonel';
import { responseSchemas } from '@/schemas/api/internal/responses';
import { gracefulParse } from '@/utils/schemaValidation';
import { useApi } from '@/shared/composables/useApi';
import { defineStore } from 'pinia';
import { reactive, ref } from 'vue';

// Use the imported type from schemas
export type ColonelStats = ColonelStatsDetails;

// eslint-disable-next-line max-lines-per-function -- Admin store with many related endpoints
export const useColonelInfoStore = defineStore('colonel', () => {
  const $api = useApi();

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
  const customDomains = ref<ColonelCustomDomain[]>([]);
  const customDomainsPagination = ref<Pagination | null>(null);
  const organizations = ref<ColonelOrganization[]>([]);
  const organizationsPagination = ref<Pagination | null>(null);
  const organizationsFilters = ref<ColonelOrganizationsFilters | null>(null);
  const usageExport = ref<UsageExportDetails | null>(null);
  const queueMetrics = ref<QueueMetrics | null>(null);
  const _initialized = ref(false);

  // Per-resource loading flags to prevent concurrent fetches from stomping each other
  const loading = reactive({
    info: false,
    stats: false,
    users: false,
    secrets: false,
    databaseMetrics: false,
    redisMetrics: false,
    bannedIPs: false,
    customDomains: false,
    organizations: false,
    usageExport: false,
    queueMetrics: false,
  });

  // Per-list-resource validation error state. Holds the schema name when
  // gracefulParse fails so views can distinguish "fetch returned nothing"
  // from "the response did not match the expected schema". Set to null on
  // each successful fetch.
  const usersFetchError = ref<string | null>(null);
  const secretsFetchError = ref<string | null>(null);
  const customDomainsFetchError = ref<string | null>(null);
  const organizationsFetchError = ref<string | null>(null);

  // Actions
  async function fetch() {
    loading.info = true;
    try {
      const response = await $api.get('/api/colonel/info');
      const result = gracefulParse(responseSchemas.colonelInfo, response.data, 'ColonelInfoResponse');
      if (!result.ok) {
        throw new Error('Unable to load colonel info. Please try again.');
      }
      details.value = result.data.details ?? null;
      // Also populate stats from the full response
      if (result.data.details) {
        stats.value = {
          counts: result.data.details.counts,
        };
      }
      return result.data.record;
    } catch (error) {
      console.error('Failed to fetch colonel info:', error);
      throw error;
    } finally {
      loading.info = false;
    }
  }

  // Lightweight stats-only fetch for dashboard
  async function fetchStats() {
    loading.stats = true;
    try {
      // Use the dedicated stats endpoint for better performance
      const response = await $api.get('/api/colonel/stats');
      const result = gracefulParse(responseSchemas.colonelStats, response.data, 'ColonelStatsResponse');
      if (!result.ok) {
        throw new Error('Unable to load colonel stats. Please try again.');
      }
      if (result.data.details) {
        stats.value = result.data.details;
      }
      return stats.value!;
    } catch (error) {
      console.error('Failed to fetch colonel stats:', error);
      // Fallback to null stats on error
      stats.value = null;
      throw error;
    } finally {
      loading.stats = false;
    }
  }

  // Fetch users list with optional pagination
  async function fetchUsers(page = 1, perPage = 50, roleFilter?: string) {
    loading.users = true;
    try {
      const params = new URLSearchParams();
      params.append('page', page.toString());
      params.append('per_page', perPage.toString());
      if (roleFilter) {
        params.append('role', roleFilter);
      }

      const response = await $api.get(`/api/colonel/users?${params.toString()}`);
      const result = gracefulParse(responseSchemas.colonelUsers, response.data, 'ColonelUsersResponse');
      if (!result.ok) {
        users.value = [];
        usersPagination.value = null;
        usersFetchError.value = 'ColonelUsersResponse';
        return null;
      }

      usersFetchError.value = null;
      if (result.data.details) {
        users.value = result.data.details.users;
        usersPagination.value = result.data.details.pagination;
      }

      return result.data.details!;
    } catch (error) {
      console.error('Failed to fetch colonel users:', error);
      users.value = [];
      usersPagination.value = null;
      throw error;
    } finally {
      loading.users = false;
    }
  }

  // Fetch secrets list with optional pagination
  async function fetchSecrets(page = 1, perPage = 50) {
    loading.secrets = true;
    try {
      const params = new URLSearchParams();
      params.append('page', page.toString());
      params.append('per_page', perPage.toString());

      const response = await $api.get(`/api/colonel/secrets?${params.toString()}`);
      const result = gracefulParse(responseSchemas.colonelSecrets, response.data, 'ColonelSecretsResponse');
      if (!result.ok) {
        secrets.value = [];
        secretsPagination.value = null;
        secretsFetchError.value = 'ColonelSecretsResponse';
        return null;
      }

      secretsFetchError.value = null;
      if (result.data.details) {
        secrets.value = result.data.details.secrets;
        secretsPagination.value = result.data.details.pagination;
      }

      return result.data.details!;
    } catch (error) {
      console.error('Failed to fetch colonel secrets:', error);
      secrets.value = [];
      secretsPagination.value = null;
      throw error;
    } finally {
      loading.secrets = false;
    }
  }

  // Fetch database metrics
  async function fetchDatabaseMetrics() {
    loading.databaseMetrics = true;
    try {
      const response = await $api.get('/api/colonel/system/database');
      const result = gracefulParse(responseSchemas.databaseMetrics, response.data, 'DatabaseMetricsResponse');
      if (!result.ok) {
        throw new Error('Unable to load database metrics. Please try again.');
      }

      if (result.data.details) {
        databaseMetrics.value = result.data.details;
      }

      return result.data.details!;
    } catch (error) {
      console.error('Failed to fetch database metrics:', error);
      databaseMetrics.value = null;
      throw error;
    } finally {
      loading.databaseMetrics = false;
    }
  }

  // Fetch Redis metrics
  async function fetchRedisMetrics() {
    loading.redisMetrics = true;
    try {
      const response = await $api.get('/api/colonel/system/redis');
      const result = gracefulParse(responseSchemas.redisMetrics, response.data, 'RedisMetricsResponse');
      if (!result.ok) {
        throw new Error('Unable to load Redis metrics. Please try again.');
      }

      if (result.data.details) {
        redisMetrics.value = result.data.details;
      }

      return result.data.details!;
    } catch (error) {
      console.error('Failed to fetch Redis metrics:', error);
      redisMetrics.value = null;
      throw error;
    } finally {
      loading.redisMetrics = false;
    }
  }

  // Fetch banned IPs list
  async function fetchBannedIPs() {
    loading.bannedIPs = true;
    try {
      const response = await $api.get('/api/colonel/banned-ips');
      const result = gracefulParse(responseSchemas.bannedIPs, response.data, 'BannedIPsResponse');
      if (!result.ok) {
        throw new Error('Unable to load banned IPs. Please try again.');
      }

      if (result.data.details) {
        currentIP.value = result.data.details.current_ip;
        bannedIPs.value = result.data.details.banned_ips;
      }

      return result.data.details!;
    } catch (error) {
      console.error('Failed to fetch banned IPs:', error);
      bannedIPs.value = [];
      currentIP.value = null;
      throw error;
    } finally {
      loading.bannedIPs = false;
    }
  }

  // Ban an IP address
  async function banIP(ipAddress: string, reason?: string) {
    try {
      await $api.post('/api/colonel/banned-ips', {
        ip_address: ipAddress,
        reason: reason || '',
      });

      // Refresh the banned IPs list (handles its own loading state)
      await fetchBannedIPs();
    } catch (error) {
      console.error('Failed to ban IP:', error);
      throw error;
    }
  }

  // Unban an IP address
  async function unbanIP(ipAddress: string) {
    try {
      await $api.delete(`/api/colonel/banned-ips/${encodeURIComponent(ipAddress)}`);

      // Refresh the banned IPs list (handles its own loading state)
      await fetchBannedIPs();
    } catch (error) {
      console.error('Failed to unban IP:', error);
      throw error;
    }
  }

  // Fetch custom domains list with optional pagination
  async function fetchCustomDomains(page = 1, perPage = 50) {
    loading.customDomains = true;
    try {
      const params = new URLSearchParams();
      params.append('page', page.toString());
      params.append('per_page', perPage.toString());

      const response = await $api.get(`/api/colonel/domains?${params.toString()}`);
      const result = gracefulParse(responseSchemas.customDomains, response.data, 'ColonelCustomDomainsResponse');
      if (!result.ok) {
        customDomains.value = [];
        customDomainsPagination.value = null;
        customDomainsFetchError.value = 'ColonelCustomDomainsResponse';
        return null;
      }

      customDomainsFetchError.value = null;
      if (result.data.details) {
        customDomains.value = result.data.details.domains;
        customDomainsPagination.value = result.data.details.pagination;
      }

      return result.data.details!;
    } catch (error) {
      console.error('Failed to fetch custom domains:', error);
      customDomains.value = [];
      customDomainsPagination.value = null;
      throw error;
    } finally {
      loading.customDomains = false;
    }
  }

  // Fetch organizations list with optional pagination and filters
  async function fetchOrganizations(
    page = 1,
    perPage = 50,
    statusFilter?: string,
    syncStatusFilter?: string
  ) {
    loading.organizations = true;
    try {
      const params = new URLSearchParams();
      params.append('page', page.toString());
      params.append('per_page', perPage.toString());
      if (statusFilter) {
        params.append('status', statusFilter);
      }
      if (syncStatusFilter) {
        params.append('sync_status', syncStatusFilter);
      }

      const response = await $api.get(`/api/colonel/organizations?${params.toString()}`);
      const result = gracefulParse(responseSchemas.colonelOrganizations, response.data, 'ColonelOrganizationsResponse');
      if (!result.ok) {
        organizations.value = [];
        organizationsPagination.value = null;
        organizationsFilters.value = null;
        organizationsFetchError.value = 'ColonelOrganizationsResponse';
        return null;
      }

      organizationsFetchError.value = null;
      if (result.data.details) {
        organizations.value = result.data.details.organizations;
        organizationsPagination.value = result.data.details.pagination;
        organizationsFilters.value = result.data.details.filters;
      }

      return result.data.details!;
    } catch (error) {
      console.error('Failed to fetch organizations:', error);
      organizations.value = [];
      organizationsPagination.value = null;
      organizationsFilters.value = null;
      throw error;
    } finally {
      loading.organizations = false;
    }
  }

  // Investigate organization billing state by comparing local data with Stripe
  async function investigateOrganization(extId: string): Promise<InvestigateOrganizationResult> {
    try {
      const response = await $api.post(`/api/colonel/organizations/${extId}/investigate`);
      const result = gracefulParse(responseSchemas.investigateOrganization, response.data, 'InvestigateOrganizationResponse');
      if (!result.ok) {
        throw new Error('Unable to investigate organization. Please try again.');
      }
      return result.data.record;
    } catch (error) {
      console.error('Failed to investigate organization:', error);
      throw error;
    }
  }

  // Fetch usage export data
  async function fetchUsageExport(startDate?: number, endDate?: number) {
    loading.usageExport = true;
    try {
      const params = new URLSearchParams();
      if (startDate) {
        params.append('start_date', startDate.toString());
      }
      if (endDate) {
        params.append('end_date', endDate.toString());
      }

      const response = await $api.get(`/api/colonel/usage/export?${params.toString()}`);
      const result = gracefulParse(responseSchemas.usageExport, response.data, 'UsageExportResponse');
      if (!result.ok) {
        throw new Error('Unable to load usage export. Please try again.');
      }

      if (result.data.details) {
        usageExport.value = result.data.details;
      }

      return result.data.details!;
    } catch (error) {
      console.error('Failed to fetch usage export:', error);
      usageExport.value = null;
      throw error;
    } finally {
      loading.usageExport = false;
    }
  }

  // Fetch queue metrics
  async function fetchQueueMetrics() {
    loading.queueMetrics = true;
    try {
      const response = await $api.get('/api/colonel/queue');
      const result = gracefulParse(responseSchemas.queueMetrics, response.data, 'QueueMetricsResponse');
      if (!result.ok) {
        throw new Error('Unable to load queue metrics. Please try again.');
      }

      if (result.data.details) {
        queueMetrics.value = result.data.details;
      }

      return result.data.details!;
    } catch (error) {
      console.error('Failed to fetch queue metrics:', error);
      queueMetrics.value = null;
      throw error;
    } finally {
      loading.queueMetrics = false;
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
    organizations.value = [];
    organizationsPagination.value = null;
    organizationsFilters.value = null;
    usageExport.value = null;
    queueMetrics.value = null;
    usersFetchError.value = null;
    secretsFetchError.value = null;
    customDomainsFetchError.value = null;
    organizationsFetchError.value = null;
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
    organizations.value = [];
    organizationsPagination.value = null;
    organizationsFilters.value = null;
    usageExport.value = null;
    queueMetrics.value = null;
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
    organizations,
    organizationsPagination,
    organizationsFilters,
    usageExport,
    queueMetrics,
    loading,
    usersFetchError,
    secretsFetchError,
    customDomainsFetchError,
    organizationsFetchError,

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
    fetchOrganizations,
    investigateOrganization,
    fetchUsageExport,
    fetchQueueMetrics,
    dispose,
    $reset,
  };
});
