// src/stores/domainsStore.ts
import { AsyncHandlerOptions, useAsyncHandler } from '@/composables/useAsyncHandler';
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

  let $errorHandler: ReturnType<typeof useAsyncHandler> | null = null;

  // Getters
  const isInitialized = computed(() => _initialized.value);
  const recordCount = computed(() => domains.value.length);

  function init(api?: AxiosInstance) {
    if (_initialized.value) return { isInitialized };

    _initialized.value = true;


    return { isInitialized };
  }


  /**
   * Add a new custom domain
   */
  async function addDomain(domain: string) {

    return await $errorHandler!.withErrorHandling(async () => {
      const response = await $api!.post('/api/v2/account/domains/add', { domain });
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

    return await $errorHandler!.withErrorHandling(async () => {
      const response = await $api!.get('/api/v2/account/domains');
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

    return await $errorHandler.withErrorHandling(async () => {
      const response = await $api!.put(
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

    return await $errorHandler!.withErrorHandling(async () => {
      await $api!.post(`/api/v2/account/domains/${domainName}/remove`);
      domains.value = domains.value.filter(
        (domain) => domain.display_domain !== domainName
      );
    });
  }

  /**
   * Get brand settings for a domain
   */
  async function getBrandSettings(domain: string) {

    return await $errorHandler!.withErrorHandling(async () => {
      const response = await $api!.get(`/api/v2/account/domains/${domain}/brand`);
      return responseSchemas.brandSettings.parse(response.data);
    });
  }

  /**
   * Update brand settings for a domain
   */
  async function updateBrandSettings(domain: string, settings: Partial<BrandSettings>) {

    return await $errorHandler!.withErrorHandling(async () => {
      const response = await $api!.put(`/api/v2/account/domains/${domain}/brand`, {
        brand: settings,
      });
      return responseSchemas.brandSettings.parse(response.data);
    });
  }

  /**
   * Update an existing domain
   */
  async function updateDomain(domain: CustomDomain) {

    return await $errorHandler!.withErrorHandling(async () => {
      const response = await $api!.put(
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
    init,

    // State
    isLoading,
    domains,
    _initialized,

    // Getters
    recordCount,

    // Actions
    setupAsyncHandler,
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
