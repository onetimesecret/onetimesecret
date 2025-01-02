// src/stores/domainsStore.ts
import { ErrorHandlerOptions, useErrorHandler } from '@/composables/useErrorHandler';
import { UpdateDomainBrandRequest } from '@/schemas/api';
import { responseSchemas } from '@/schemas/api/responses';
import type { BrandSettings, CustomDomain } from '@/schemas/models';
import { createApi } from '@/utils/api';
import { AxiosInstance } from 'axios';
import { defineStore } from 'pinia';
import { computed, ref } from 'vue';

/**
 * Store for managing custom domains and their brand settings
 * Uses closure for dependency injection of API client and error handler
 */

/* eslint-disable max-lines-per-function */
export const useDomainsStore = defineStore('domains', () => {
  // State
  const isLoading = ref(false);
  const domains = ref<CustomDomain[]>([]);
  const _initialized = ref(false);

  // Private store instance vars (closure based DI)
  let _api: AxiosInstance | null = null;
  let _errorHandler: ReturnType<typeof useErrorHandler> | null = null;

  // Getters
  const recordCount = computed(() => domains.value.length);

  // Internal utilities
  function _ensureErrorHandler() {
    if (!_errorHandler) setupErrorHandler();
  }

  /**
   * Initialize error handling with optional custom API client and options
   */
  function setupErrorHandler(
    api: AxiosInstance = createApi(),
    options: ErrorHandlerOptions = {}
  ) {
    _api = api;
    _errorHandler = useErrorHandler({
      setLoading: (loading) => (isLoading.value = loading),
      notify: options.notify,
      log: options.log,
    });
  }

  /**
   * Add a new custom domain
   */
  async function addDomain(domain: string) {
    _ensureErrorHandler();

    return await _errorHandler!.withErrorHandling(async () => {
      const response = await _api!.post('/api/v2/account/domains/add', { domain });
      const validated = responseSchemas.customDomain.parse(response.data);
      domains.value.push(validated.record);
      return validated.record;
    });
  }

  /**
   * Load all domains if not already _initialized
   */
  async function refreshRecords() {
    if (_initialized.value) return;
    _ensureErrorHandler();

    return await _errorHandler!.withErrorHandling(async () => {
      const response = await _api!.get('/api/v2/account/domains');
      const validated = responseSchemas.customDomainList.parse(response.data);
      domains.value = validated.records;
      _initialized.value = true;
      return validated.records;
    });
  }

  /**
   * Update brand settings for a domain
   */
  async function updateDomainBrand(
    domain: string,
    brandUpdate: UpdateDomainBrandRequest
  ) {
    _ensureErrorHandler();

    return await _errorHandler!.withErrorHandling(async () => {
      const response = await _api!.put(
        `/api/v2/account/domains/${domain}/brand`,
        brandUpdate
      );
      const validated = responseSchemas.customDomain.parse(response.data);

      const domainIndex = domains.value.findIndex((d) => d.display_domain === domain);
      if (domainIndex !== -1) {
        domains.value[domainIndex] = validated.record;
      }
      return validated.record;
    });
  }

  /**
   * Delete a domain by name
   */
  async function deleteDomain(domainName: string) {
    _ensureErrorHandler();

    return await _errorHandler!.withErrorHandling(async () => {
      await _api!.post(`/api/v2/account/domains/${domainName}/remove`);
      domains.value = domains.value.filter(
        (domain) => domain.display_domain !== domainName
      );
    });
  }

  /**
   * Get brand settings for a domain
   */
  async function getBrandSettings(domain: string) {
    _ensureErrorHandler();

    return await _errorHandler!.withErrorHandling(async () => {
      const response = await _api!.get(`/api/v2/account/domains/${domain}/brand`);
      return responseSchemas.brandSettings.parse(response.data);
    });
  }

  /**
   * Update brand settings for a domain
   */
  async function updateBrandSettings(domain: string, settings: Partial<BrandSettings>) {
    _ensureErrorHandler();

    return await _errorHandler!.withErrorHandling(async () => {
      const response = await _api!.put(`/api/v2/account/domains/${domain}/brand`, {
        brand: settings,
      });
      return responseSchemas.brandSettings.parse(response.data);
    });
  }

  /**
   * Update an existing domain
   */
  async function updateDomain(domain: CustomDomain) {
    _ensureErrorHandler();

    return await _errorHandler!.withErrorHandling(async () => {
      const response = await _api!.put(
        `/api/v2/account/domains/${domain.display_domain}`,
        domain
      );
      const validated = responseSchemas.customDomain.parse(response.data);

      const domainIndex = domains.value.findIndex(
        (d) => d.display_domain === domain.display_domain
      );

      if (domainIndex !== -1) {
        domains.value[domainIndex] = validated.record;
      } else {
        domains.value.push(validated.record);
      }
      return validated.record;
    });
  }

  /**
   * Reset store state to initial values
   */
  function $reset() {
    isLoading.value = false;
    domains.value = [];
    _initialized.value = false;
  }

  return {
    // State
    isLoading,
    domains,
    _initialized,

    // Getters
    recordCount,

    // Actions
    setupErrorHandler,
    $reset,
    addDomain,
    refreshRecords,
    updateDomainBrand,
    deleteDomain,
    getBrandSettings,
    updateBrandSettings,
    updateDomain,
  };
});
