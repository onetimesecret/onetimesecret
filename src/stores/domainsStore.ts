// src/stores/domainsStore.ts
//
import { UpdateDomainBrandRequest } from '@/schemas/api';
import { responseSchemas } from '@/schemas/api/responses';
import type { BrandSettings, CustomDomain, CustomDomainDetails } from '@/schemas/models';
import { defineStore, PiniaCustomProperties } from 'pinia';
import { ref, Ref } from 'vue';

/**
 * Store for managing custom domains and their brand settings
 * Uses closure for dependency injection of API client and error handler
 */

/**
 * Custom type for the DomainsStore, including plugin-injected properties.
 */
export type DomainsStore = {
  // State
  _initialized: boolean;
  records: CustomDomain[];
  details: CustomDomainDetails | null;
  count: number | null;

  // Getters
  recordCount: number;
  initialized: boolean;

  // Actions
  addDomain: (domain: string) => Promise<CustomDomain>;
  fetchList: () => Promise<void>;
  getDomain: (domainName: string) => Promise<CustomDomain>;
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
  // State
  const _initialized = ref(false);
  const records: Ref<CustomDomain[] | null> = ref(null);
  const details: Ref<CustomDomainDetails | null> = ref(null);
  const count = ref<number | null>(null);

  // Getters
  const initialized = _initialized.value;
  const recordCount = count.value ?? 0;

  function init(this: DomainsStore) {
    if (_initialized.value) return { initialized };

    _initialized.value = true;
    return { initialized };
  }

  /**
   * Add a new custom domain
   */
  async function addDomain(this: DomainsStore, domain: string) {
    const response = await this.$api.post('/api/v2/domains/add', { domain });
    const validated = responseSchemas.customDomain.parse(response.data);
    if (!records.value) records.value = [];
    records.value.push(validated.record);
    return validated.record;
  }

  /**
   * Load all domains if not already _initialized
   */
  async function fetchList(this: DomainsStore) {
    const response = await this.$api.get('/api/v2/domains');
    const validated = responseSchemas.customDomainList.parse(response.data);
    records.value = validated.records ?? [];
    details.value = validated.details ?? {};
    count.value = validated.count ?? 0;

    return validated;
  }

  async function getDomain(this: DomainsStore, domainName: string) {
    const response = await this.$api.get(`/api/v2/domains/${domainName}`);
    const validated = responseSchemas.customDomain.parse(response.data);
    return validated.record;
  }

  async function refreshRecords(this: DomainsStore, force = false) {
    if (!force && _initialized.value) return;

    await this.fetchList();
    _initialized.value = true;
  }

  /**
   * Delete a domain by name
   */
  async function deleteDomain(this: DomainsStore, domainName: string) {
    await this.$api.post(`/api/v2/domains/${domainName}/remove`);
    if (!records.value) return;
    records.value = records.value.filter(
      (domain) => domain.display_domain !== domainName
    );
  }

  /**
   * Get brand settings for a domain
   */
  async function getBrandSettings(this: DomainsStore, domain: string) {
    const response = await this.$api.get(`/api/v2/domains/${domain}/brand`);
    return responseSchemas.brandSettings.parse(response.data);
  }

  /**
   * Update brand settings for a domain
   */
  async function updateBrandSettings(
    this: DomainsStore,
    domain: string,
    settings: Partial<BrandSettings>
  ) {
    const response = await this.$api.put(`/api/v2/domains/${domain}/brand`, {
      brand: settings,
    });
    return responseSchemas.brandSettings.parse(response.data);
  }

  /**
   * Update brand settings for a domain
   */
  async function updateDomainBrand(
    this: DomainsStore,
    domain: string,
    brandUpdate: UpdateDomainBrandRequest
  ) {
    const response = await this.$api.put(`/api/v2/domains/${domain}/brand`, brandUpdate);
    const validated = responseSchemas.customDomain.parse(response.data);
    if (!records.value) return validated.record;

    const domainIndex = records.value.findIndex((d) => d.display_domain === domain);
    if (domainIndex !== -1) {
      records.value[domainIndex] = validated.record;
    }
    return validated.record;
  }

  /**
   * Update an existing domain
   */
  async function updateDomain(this: DomainsStore, domain: CustomDomain) {
    const response = await this.$api.put(
      `/api/v2/domains/${domain.display_domain}`,
      domain
    );
    const validated = responseSchemas.customDomain.parse(response.data);

    if (!records.value) records.value = [];
    const domainIndex = records.value.findIndex(
      (d) => d.display_domain === domain.display_domain
    );

    if (domainIndex !== -1) {
      records.value[domainIndex] = validated.record;
    } else {
      records.value.push(validated.record);
    }
    return validated.record;
  }

  /**
   * Reset store state to initial values
   */
  function $reset(this: DomainsStore) {
    records.value = [];
    _initialized.value = false;
  }

  return {
    init,

    // State
    records,
    details,
    count,

    // Getters
    recordCount,
    initialized,

    // Actions
    addDomain,
    fetchList,
    refreshRecords,
    updateDomainBrand,
    deleteDomain,
    getDomain,
    getBrandSettings,
    updateBrandSettings,
    updateDomain,
    $reset,
  };
});
