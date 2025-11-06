// src/stores/domainsStore.ts

import { PiniaPluginOptions } from '@/plugins/pinia';
import { UpdateDomainBrandRequest } from '@/schemas/api/v3';
import { responseSchemas } from '@/schemas/api/v3/responses';
import type {
  BrandSettings,
  CustomDomain,
  CustomDomainDetails,
  ImageProps,
} from '@/schemas/models';
import { loggingService } from '@/services/logging.service';
import { AxiosError, AxiosInstance } from 'axios';
import { defineStore, PiniaCustomProperties } from 'pinia';
import { computed, inject, ref, Ref } from 'vue';

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
  updateDomain: (domain: CustomDomain) => Promise<CustomDomain>;
  verifyDomain: (domainName: string) => Promise<CustomDomain>;
  deleteDomain: (domainName: string) => Promise<void>;

  uploadLogo: (domain: string, file: File) => Promise<void>;
  fetchLogo: (domain: string) => Promise<ImageProps>;
  removeLogo: (domain: string) => Promise<void>;

  refreshRecords: () => Promise<CustomDomain[]>;
  getBrandSettings: (domain: string) => Promise<BrandSettings>;
  updateDomainBrand: (
    domain: string,
    brandUpdate: UpdateDomainBrandRequest
  ) => Promise<CustomDomain>;
  updateBrandSettings: (domain: string, settings: Partial<BrandSettings>) => Promise<BrandSettings>;

  reset: () => void;
} & PiniaCustomProperties;

/* eslint-disable max-lines-per-function */
export const useDomainsStore = defineStore('domains', () => {
  const $api = inject('api') as AxiosInstance;

  // State
  const _initialized = ref(false);
  const records: Ref<CustomDomain[] | null> = ref(null);
  const details: Ref<CustomDomainDetails | null> = ref(null);
  const count = ref<number | null>(null);

  // Getters
  const initialized = _initialized.value;
  const recordCount = () => count.value ?? 0;
  const domains = computed(() => records.value ?? []);

  interface StoreOptions extends PiniaPluginOptions {}

  function init(options?: StoreOptions) {
    if (_initialized.value) return { initialized };

    if (options?.api) loggingService.warn('API instance provided in options, ignoring.');

    _initialized.value = true;
    return { initialized };
  }

  /**
   * Add a new custom domain
   */
  async function addDomain(domain: string) {
    const response = await $api.post('/api/account/domains/add', { domain });
    const validated = responseSchemas.customDomain.parse(response.data);
    if (!records.value) records.value = [];
    records.value.push(validated.record);
    return validated.record;
  }

  /**
   * Load all domains if not already _initialized
   */
  async function fetchList() {
    const response = await $api.get('/api/account/domains');
    const validated = responseSchemas.customDomainList.parse(response.data);
    records.value = validated.records ?? [];
    details.value = validated.details ?? {};
    count.value = validated.count ?? 0;

    return validated;
  }

  async function getDomain(domainName: string) {
    const response = await $api.get(`/api/account/domains/${domainName}`);
    const validated = responseSchemas.customDomain.parse(response.data);
    return validated;
  }

  async function verifyDomain(domainName: string) {
    const response = await $api.post(`/api/account/domains/${domainName}/verify`, {
      domain: domainName,
    });
    const validated = responseSchemas.customDomain.parse(response.data);
    return validated;
  }

  async function uploadLogo(domain: string, file: File) {
    const formData = new FormData();
    formData.append('image', file);

    const response = await $api.post(`/api/account/domains/${domain}/logo`, formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });

    // Validate upload response
    const validated = responseSchemas.imageProps.parse(response.data);
    return validated.record;
  }

  async function fetchLogo(domain: string): Promise<ImageProps | null> {
    try {
      const response = await $api.get(`/api/account/domains/${domain}/logo`);
      // Use the existing schema to validate the response
      const validated = responseSchemas.imageProps.parse(response.data);
      return validated.record;
    } catch (error: unknown) {
      // Handle 404 or other expected errors silently
      if ((error as AxiosError).response?.status === 404) {
        console.debug(`[domainsStore] No logo found for domain: ${domain}`);
        return null;
      }
      throw error;
    }
  }

  async function removeLogo(domain: string) {
    await $api.delete(`/api/account/domains/${domain}/logo`);
  }

  async function refreshRecords(force = false) {
    if (!force && _initialized.value) return;

    await fetchList();
    _initialized.value = true;
  }

  /**
   * Delete a domain by name
   */
  async function deleteDomain(domainName: string) {
    await $api.post(`/api/account/domains/${domainName}/remove`);
    if (!records.value) return;
    records.value = records.value.filter((domain) => domain.display_domain !== domainName);
  }

  /**
   * Get brand settings for a domain
   */
  // Ensure getBrandSettings always returns valid data
  async function getBrandSettings(domain: string): Promise<BrandSettings> {
    const response = await $api.get(`/api/account/domains/${domain}/brand`);
    const validated = responseSchemas.brandSettings.parse(response.data);
    return validated.record;
  }

  /**
   * Update brand settings for a domain
   */
  async function updateBrandSettings(domain: string, settings: Partial<BrandSettings>) {
    const response = await $api.put(`/api/account/domains/${domain}/brand`, {
      brand: settings,
    });
    return responseSchemas.brandSettings.parse(response.data);
  }

  /**
   * Update brand settings for a domain
   */
  async function updateDomainBrand(domain: string, brandUpdate: UpdateDomainBrandRequest) {
    const response = await $api.put(`/api/account/domains/${domain}/brand`, brandUpdate);
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
  async function updateDomain(domain: CustomDomain) {
    const response = await $api.put(`/api/account/domains/${domain.display_domain}`, domain);
    const validated = responseSchemas.customDomain.parse(response.data);

    if (!records.value) records.value = [];
    const domainIndex = records.value.findIndex((d) => d.display_domain === domain.display_domain);

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
  function $reset() {
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
    domains,

    // Actions
    addDomain,
    deleteDomain,
    getDomain,
    verifyDomain,
    updateDomain,

    updateDomainBrand,
    getBrandSettings,
    updateBrandSettings,

    uploadLogo,
    fetchLogo,
    removeLogo,

    fetchList,
    refreshRecords,
    $reset,
  };
});
