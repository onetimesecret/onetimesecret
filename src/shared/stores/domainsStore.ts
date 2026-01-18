// src/shared/stores/domainsStore.ts

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
  addDomain: (domain: string, orgId?: string) => Promise<{ record: CustomDomain; details?: CustomDomainDetails }>;
  fetchList: () => Promise<void>;
  getDomain: (extid: string) => Promise<CustomDomain>;
  verifyDomain: (extid: string) => Promise<CustomDomain>;
  deleteDomain: (extid: string) => Promise<void>;

  uploadLogo: (extid: string, file: File) => Promise<void>;
  fetchLogo: (extid: string) => Promise<ImageProps>;
  removeLogo: (extid: string) => Promise<void>;

  refreshRecords: () => Promise<CustomDomain[]>;
  getBrandSettings: (extid: string) => Promise<BrandSettings>;
  updateDomainBrand: (
    extid: string,
    brandUpdate: UpdateDomainBrandRequest
  ) => Promise<CustomDomain>;
  updateBrandSettings: (extid: string, settings: Partial<BrandSettings>) => Promise<BrandSettings>;

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
   *
   * @param domain - The domain name to add
   * @param orgId - Optional organization ID. If provided, adds domain for that org.
   *                If not provided, uses the organization from session context.
   * @returns Object containing the domain record and details (including domain_context if set by server)
   */
  async function addDomain(domain: string, orgId?: string) {
    const payload: { domain: string; org_id?: string } = { domain };
    if (orgId) payload.org_id = orgId;
    const response = await $api.post('/api/domains/add', payload);
    const validated = responseSchemas.customDomain.parse(response.data);
    if (!records.value) records.value = [];
    records.value.push(validated.record);
    return { record: validated.record, details: validated.details };
  }

  /**
   * Load all domains for an organization
   *
   * @param orgId - Optional organization ID. If provided, fetches domains for that org.
   *                If not provided, uses the organization from session context.
   */
  async function fetchList(orgId?: string) {
    const params = orgId ? { org_id: orgId } : {};
    const response = await $api.get('/api/domains', { params });
    const validated = responseSchemas.customDomainList.parse(response.data);
    records.value = validated.records ?? [];
    details.value = validated.details ?? {};
    count.value = validated.count ?? 0;

    return validated;
  }

  async function getDomain(extid: string) {
    const response = await $api.get(`/api/domains/${extid}`);
    const validated = responseSchemas.customDomain.parse(response.data);
    return validated;
  }

  async function verifyDomain(extid: string) {
    const response = await $api.post(`/api/domains/${extid}/verify`);
    const validated = responseSchemas.customDomain.parse(response.data);
    return validated;
  }

  async function uploadLogo(extid: string, file: File) {
    const formData = new FormData();
    formData.append('image', file);

    const response = await $api.post(`/api/domains/${extid}/logo`, formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });

    // Validate upload response
    const validated = responseSchemas.imageProps.parse(response.data);
    return validated.record;
  }

  async function fetchLogo(extid: string): Promise<ImageProps | null> {
    try {
      const response = await $api.get(`/api/domains/${extid}/logo`);
      // Use the existing schema to validate the response
      const validated = responseSchemas.imageProps.parse(response.data);
      return validated.record;
    } catch (error: unknown) {
      // Handle 404 or other expected errors silently
      if ((error as AxiosError).response?.status === 404) {
        console.debug(`[domainsStore] No logo found for extid: ${extid}`);
        return null;
      }
      throw error;
    }
  }

  async function removeLogo(extid: string) {
    await $api.delete(`/api/domains/${extid}/logo`);
  }

  async function refreshRecords(force = false) {
    if (!force && _initialized.value) return;

    await fetchList();
    _initialized.value = true;
  }

  /**
   * Delete a domain by extid
   */
  async function deleteDomain(extid: string) {
    await $api.post(`/api/domains/${extid}/remove`);
    if (!records.value) return;
    records.value = records.value.filter((domain) => domain.extid !== extid);
  }

  /**
   * Get brand settings for a domain
   */
  // Ensure getBrandSettings always returns valid data
  async function getBrandSettings(extid: string): Promise<BrandSettings> {
    const response = await $api.get(`/api/domains/${extid}/brand`);
    const validated = responseSchemas.brandSettings.parse(response.data);
    return validated.record;
  }

  /**
   * Update brand settings for a domain
   */
  async function updateBrandSettings(extid: string, settings: Partial<BrandSettings>) {
    const response = await $api.put(`/api/domains/${extid}/brand`, {
      brand: settings,
    });
    return responseSchemas.brandSettings.parse(response.data);
  }

  /**
   * Update brand settings for a domain via PUT /:extid/brand endpoint
   *
   * Unlike updateBrandSettings() which returns only brand settings,
   * this function returns the full domain object and updates store state.
   */
  async function updateDomainBrand(extid: string, brandUpdate: UpdateDomainBrandRequest) {
    const response = await $api.put(`/api/domains/${extid}/brand`, brandUpdate);
    const validated = responseSchemas.customDomain.parse(response.data);
    if (!records.value) return validated.record;

    const domainIndex = records.value.findIndex((d) => d.extid === extid);
    if (domainIndex !== -1) {
      records.value[domainIndex] = validated.record;
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
