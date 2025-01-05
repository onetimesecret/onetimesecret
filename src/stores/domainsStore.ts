// src/stores/domainsStore.ts
//
import { UpdateDomainBrandRequest } from '@/schemas/api';
import { responseSchemas } from '@/schemas/api/responses';
import type { BrandSettings, CustomDomain } from '@/schemas/models';
import { defineStore, PiniaCustomProperties } from 'pinia';
import { computed, ref } from 'vue';

/**
 * Store for managing custom domains and their brand settings
 * Uses closure for dependency injection of API client and error handler
 */

/**
 * Custom type for the DomainsStore, including plugin-injected properties.
 */
export type DomainsStore = {
  isLoading: boolean;
  domains: CustomDomain[];
  initialized: boolean;
  isInitialized: boolean;
  recordCount: number;
  init: () => void;
  addDomain: (domain: string) => Promise<CustomDomain>;
  refreshRecords: () => Promise<CustomDomain[]>;
  updateDomainBrand: (
    domain: string,
    brandUpdate: UpdateDomainBrandRequest
  ) => Promise<CustomDomain>;
  deleteDomain: (domainName: string) => Promise<void>;
  getBrandSettings: (domain: string) => Promise<BrandSettings>;
  updateBrandSettings: (
    domain: string,
    settings: Partial<BrandSettings>
  ) => Promise<BrandSettings>;
  updateDomain: (domain: CustomDomain) => Promise<CustomDomain>;
  reset: () => void;
} & PiniaCustomProperties;

/* eslint-disable max-lines-per-function */
export const useDomainsStore = defineStore('domains', () => {
  // Statell
  const isLoading = ref(false);
  const domains = ref<CustomDomain[]>([]);
  const _initialized = ref(false);

  // Getters
  const isInitialized = computed(() => _initialized.value);
  const recordCount = computed(() => domains.value.length);

  function init(this: DomainsStore) {
    if (_initialized.value) return { isInitialized };


    _initialized.value = true;
    console.debug('[init]', this.$api);
    return { isInitialized };
  }

  /**
   * Add a new custom domain
   */
  async function addDomain(this: DomainsStore, domain: string) {
    return await this.$asyncHandler.wrap(async () => {
      const response = await this.$api.post('/api/v2/account/domains/add', { domain });
      const validated = responseSchemas.customDomain.parse(response.data);
      domains.value.push(validated.record);
      return validated.record;
    });
  }

  /**
   * Load all domains if not already _initialized
   */
  async function refreshRecords(this: DomainsStore) {
    if (_initialized.value) return;

    return await this.$asyncHandler.wrap(async () => {
      const response = await this.$api.get('/api/v2/account/domains');
      const validated = responseSchemas.customDomainList.parse(response.data);
      domains.value = validated.records;
      return validated.records;
    });
  }

  /**
   * Delete a domain by name
   */
  async function deleteDomain(this: DomainsStore, domainName: string) {
    return await this.$asyncHandler.wrap(async () => {
      await this.$api.post(`/api/v2/account/domains/${domainName}/remove`);
      domains.value = domains.value.filter(
        (domain) => domain.display_domain !== domainName
      );
    });
  }

  /**
   * Get brand settings for a domain
   */
  async function getBrandSettings(this: DomainsStore, domain: string) {
    return await this.$asyncHandler.wrap(async () => {
      const response = await this.$api.get(`/api/v2/account/domains/${domain}/brand`);
      return responseSchemas.brandSettings.parse(response.data);
    });
  }

  /**
   * Update brand settings for a domain
   */
  async function updateBrandSettings(
    this: DomainsStore,
    domain: string,
    settings: Partial<BrandSettings>
  ) {
    return await this.$asyncHandler.wrap(async () => {
      const response = await this.$api.put(`/api/v2/account/domains/${domain}/brand`, {
        brand: settings,
      });
      return responseSchemas.brandSettings.parse(response.data);
    });
  }

  /**
   * Update brand settings for a domain
   */
  async function updateDomainBrand(
    this: DomainsStore,
    domain: string,
    brandUpdate: UpdateDomainBrandRequest
  ) {
    return await this.$asyncHandler.wrap(async () => {
      const response = await this.$api.put(
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
   * Update an existing domain
   */
  async function updateDomain(this: DomainsStore, domain: CustomDomain) {
    return await this.$asyncHandler.wrap(async () => {
      const response = await this.$api.put(
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
  function $reset(this: DomainsStore) {
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
