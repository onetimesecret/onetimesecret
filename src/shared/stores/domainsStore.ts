// src/shared/stores/domainsStore.ts

import { PiniaPluginOptions } from '@/plugins/pinia';
import { UpdateDomainBrandRequest } from '@/schemas/api/domains/requests';
import type {
  PutEmailConfigRequest,
  PatchEmailConfigRequest,
} from '@/schemas/api/domains/requests/email-config';
import {
  getEmailConfigResponseSchema,
  putEmailConfigResponseSchema,
  patchEmailConfigResponseSchema,
  deleteEmailConfigResponseSchema,
  validateEmailConfigResponseSchema,
  type DeleteEmailConfigResponse,
  type ValidateEmailConfigResponse,
} from '@/schemas/api/domains/responses/email-config';
import {
  homepageConfigResponseSchema,
  type HomepageConfigResponse,
} from '@/schemas/api/domains/responses/homepage-config';
import {
  testEmailConfigResponseSchema,
  type TestEmailConfigResponse,
} from '@/schemas/api/domains/responses/test-email-config';
import { responseSchemas, type CustomDomainDetails } from '@/schemas/api/v3/responses';
import type { CustomDomainEmailConfig } from '@/schemas/shapes/domains/email-config';
import type {
  BrandSettings,
  CustomDomain,
  ImageProps,
} from '@/schemas/shapes/v3';
import { loggingService } from '@/services/logging.service';
import { gracefulParse, strictParse } from '@/utils/schemaValidation';
import axios, { AxiosError, AxiosInstance } from 'axios';
import { defineStore, PiniaCustomProperties } from 'pinia';
import { computed, inject, ref, Ref } from 'vue';

/**
 * Store for managing custom domains and their brand settings
 * Uses closure for dependency injection of API client and error handler
 */

/**
 * Options for refreshing domain records
 */
export interface RefreshRecordsOptions {
  /** Organization ID to fetch domains for. If not provided, uses session context. */
  orgId?: string;
  /** Force refresh even if already initialized (default: false) */
  force?: boolean;
}

/**
 * Custom type for the DomainsStore, including plugin-injected properties.
 */
export type DomainsStore = {
  // State
  _initialized: boolean;
  _currentOrgId: string | null;
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

  refreshRecords: (options?: RefreshRecordsOptions) => Promise<void>;
  getBrandSettings: (extid: string) => Promise<BrandSettings>;
  updateDomainBrand: (
    extid: string,
    brandUpdate: UpdateDomainBrandRequest
  ) => Promise<CustomDomain>;
  updateBrandSettings: (extid: string, settings: Partial<BrandSettings>) => Promise<BrandSettings>;

  // Homepage config
  getHomepageConfig: (extid: string) => Promise<HomepageConfigResponse>;
  putHomepageConfig: (extid: string, enabled: boolean) => Promise<HomepageConfigResponse>;

  // Email config
  getEmailConfig: (extid: string) => Promise<CustomDomainEmailConfig | null>;
  putEmailConfig: (extid: string, payload: PutEmailConfigRequest) => Promise<CustomDomainEmailConfig>;
  patchEmailConfig: (extid: string, payload: PatchEmailConfigRequest) => Promise<CustomDomainEmailConfig>;
  deleteEmailConfig: (extid: string) => Promise<DeleteEmailConfigResponse>;
  validateEmailConfig: (extid: string) => Promise<ValidateEmailConfigResponse>;
  testEmailConfig: (extid: string) => Promise<TestEmailConfigResponse>;

  reset: () => void;
} & PiniaCustomProperties;

/* eslint-disable max-lines-per-function */
export const useDomainsStore = defineStore('domains', () => {
  const $api = inject('api') as AxiosInstance;

  // State
  const _initialized = ref(false);
  const _currentOrgId = ref<string | null>(null);
  const records: Ref<CustomDomain[] | null> = ref(null);
  const details: Ref<CustomDomainDetails | null> = ref(null);
  const count = ref<number | null>(null);

  // Getters
  const initialized = computed(() => _initialized.value);
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
    const result = gracefulParse(responseSchemas.customDomain, response.data, 'CustomDomainResponse');
    if (!result.ok) {
      throw new Error('Unable to add domain. Please try again.');
    }
    if (!records.value) records.value = [];
    records.value.push(result.data.record);
    return { record: result.data.record, details: result.data.details };
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
    const result = gracefulParse(responseSchemas.customDomainList, response.data, 'CustomDomainListResponse');
    if (!result.ok) {
      records.value = [];
      details.value = {};
      count.value = 0;
      return null;
    }
    records.value = result.data.records ?? [];
    details.value = result.data.details ?? {};
    count.value = result.data.count ?? 0;

    return result.data;
  }

  async function getDomain(extid: string) {
    const response = await $api.get(`/api/domains/${extid}`);
    const result = gracefulParse(responseSchemas.customDomain, response.data, 'CustomDomainResponse');
    if (!result.ok) {
      throw new Error('Unable to load domain. Please try again.');
    }
    return result.data;
  }

  async function verifyDomain(extid: string) {
    const response = await $api.post(`/api/domains/${extid}/verify`);
    const result = gracefulParse(responseSchemas.customDomain, response.data, 'CustomDomainResponse');
    if (!result.ok) {
      throw new Error('Unable to verify domain. Please try again.');
    }
    return result.data;
  }

  async function uploadLogo(extid: string, file: File) {
    const formData = new FormData();
    formData.append('image', file);

    const response = await $api.post(`/api/domains/${extid}/logo`, formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });

    // Validate upload response
    const result = gracefulParse(responseSchemas.imageProps, response.data, 'ImagePropsResponse');
    if (!result.ok) {
      throw new Error('Unable to upload logo. Please try again.');
    }
    return result.data.record;
  }

  async function fetchLogo(extid: string): Promise<ImageProps | null> {
    try {
      const response = await $api.get(`/api/domains/${extid}/logo`);
      // Use the existing schema to validate the response
      const result = gracefulParse(responseSchemas.imageProps, response.data, 'ImagePropsResponse');
      if (!result.ok) {
        throw new Error('Unable to load logo. Please try again.');
      }
      return result.data.record;
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

  /**
   * Refresh domain records
   *
   * SECURITY: This function tracks which organization the cached data belongs to.
   * When the orgId changes (user navigates to a different org), we MUST re-fetch
   * to prevent cross-organization data leakage.
   */
  async function refreshRecords(options: RefreshRecordsOptions = {}) {
    const { orgId, force = false } = options;

    // SECURITY FIX: Detect org context change to prevent cross-org data leakage.
    // Previously, this only checked _initialized which caused domains from org A
    // to be displayed when viewing org B's page.
    // NOTE: Normalize undefined to null for consistent comparison since we store null
    const normalizedOrgId = orgId ?? null;
    const orgChanged = normalizedOrgId !== _currentOrgId.value;

    if (!force && _initialized.value && !orgChanged) return;

    try {
      await fetchList(orgId);
      _currentOrgId.value = normalizedOrgId;
      _initialized.value = true;
    } catch (error) {
      loggingService.warn(`[domainsStore] Failed to refresh domain records: ${error}`);
    }
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
    const result = gracefulParse(responseSchemas.brandSettings, response.data, 'BrandSettingsResponse');
    if (!result.ok) {
      throw new Error('Unable to load brand settings. Please try again.');
    }
    return result.data.record;
  }

  /**
   * Update brand settings for a domain
   */
  async function updateBrandSettings(extid: string, settings: Partial<BrandSettings>) {
    const response = await $api.put(`/api/domains/${extid}/brand`, {
      brand: settings,
    });
    const result = gracefulParse(responseSchemas.brandSettings, response.data, 'BrandSettingsResponse');
    if (!result.ok) {
      throw new Error('Unable to update brand settings. Please try again.');
    }
    return result.data;
  }

  /**
   * Update brand settings for a domain via PUT /:extid/brand endpoint
   *
   * Unlike updateBrandSettings() which returns only brand settings,
   * this function returns the full domain object and updates store state.
   */
  async function updateDomainBrand(extid: string, brandUpdate: UpdateDomainBrandRequest) {
    const response = await $api.put(`/api/domains/${extid}/brand`, brandUpdate);
    const result = gracefulParse(responseSchemas.customDomain, response.data, 'CustomDomainResponse');
    if (!result.ok) {
      throw new Error('Unable to update domain brand. Please try again.');
    }
    if (!records.value) return result.data.record;

    const domainIndex = records.value.findIndex((d) => d.extid === extid);
    if (domainIndex !== -1) {
      records.value[domainIndex] = result.data.record;
    }
    return result.data.record;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Homepage configuration
  // ─────────────────────────────────────────────────────────────────────────

  /**
   * Get homepage configuration for a domain.
   */
  async function getHomepageConfig(extid: string): Promise<HomepageConfigResponse> {
    const response = await $api.get(`/api/domains/${extid}/homepage-config`);
    const result = gracefulParse(homepageConfigResponseSchema, response.data, 'HomepageConfigResponse');
    if (!result.ok) {
      throw new Error('Unable to load homepage configuration. Please try again.');
    }
    return result.data;
  }

  /**
   * Create or update homepage configuration for a domain.
   *
   * Updates both the domainsStore records array and the bootstrapStore's
   * homepage_config to keep all consumers (workspace views and identity store)
   * reactive without requiring a page reload.
   */
  async function putHomepageConfig(extid: string, enabled: boolean): Promise<HomepageConfigResponse> {
    const response = await $api.put(`/api/domains/${extid}/homepage-config`, { enabled });
    const result = gracefulParse(homepageConfigResponseSchema, response.data, 'HomepageConfigResponse');
    if (!result.ok) {
      throw new Error('Unable to update homepage configuration. Please try again.');
    }

    // Update the domain record in the domainsStore to keep workspace views reactive
    if (records.value && result.data.record) {
      const domainIndex = records.value.findIndex((d) => d.extid === extid);
      if (domainIndex !== -1) {
        records.value[domainIndex] = {
          ...records.value[domainIndex],
          homepage_config: result.data.record,
        };
      }
    }

    // Update bootstrapStore so identityStore (branded header/homepage) stays in sync
    // on custom domains without requiring a full page reload
    if (result.data.record) {
      const { useBootstrapStore } = await import('./bootstrapStore');
      const bootstrapStore = useBootstrapStore();
      bootstrapStore.$patch({ homepage_config: result.data.record });
    }

    return result.data;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Email configuration
  // ─────────────────────────────────────────────────────────────────────────

  /**
   * Get email configuration for a domain.
   *
   * Returns null when no email config exists (404 from API).
   * This is a valid "unconfigured" state, not an error.
   */
  async function getEmailConfig(extid: string): Promise<CustomDomainEmailConfig | null> {
    try {
      const response = await $api.get(`/api/domains/${extid}/email-config`);
      const result = gracefulParse(
        getEmailConfigResponseSchema,
        response.data,
        'GetEmailConfigResponse'
      );
      if (!result.ok) {
        return null;
      }
      return result.data.record;
    } catch (error: unknown) {
      if (axios.isAxiosError(error) && error.response?.status === 404) {
        return null;
      }
      throw error;
    }
  }

  /**
   * Create or fully replace email configuration for a domain (PUT).
   *
   * PUT semantics: the request body IS the new state.
   * All required fields must be provided.
   */
  async function putEmailConfig(
    extid: string,
    payload: PutEmailConfigRequest
  ): Promise<CustomDomainEmailConfig> {
    const response = await $api.put(`/api/domains/${extid}/email-config`, payload);
    const validated = strictParse(putEmailConfigResponseSchema, response.data);
    return validated.record;
  }

  /**
   * Partially update email configuration for a domain (PATCH).
   *
   * PATCH semantics: only provided fields are updated.
   * Omitted fields preserve existing values.
   */
  async function patchEmailConfig(
    extid: string,
    payload: PatchEmailConfigRequest
  ): Promise<CustomDomainEmailConfig> {
    const response = await $api.patch(`/api/domains/${extid}/email-config`, payload);
    const validated = strictParse(patchEmailConfigResponseSchema, response.data);
    return validated.record;
  }

  /**
   * Delete email configuration for a domain.
   *
   * Removes the email config entirely. The domain reverts to the
   * system default email configuration.
   */
  async function deleteEmailConfig(extid: string): Promise<DeleteEmailConfigResponse> {
    const response = await $api.delete(`/api/domains/${extid}/email-config`);
    return strictParse(deleteEmailConfigResponseSchema, response.data);
  }

  /**
   * Validate email configuration for a domain.
   *
   * Triggers DNS record verification and sender identity validation
   * for the domain's current email configuration. Returns the updated
   * config with refreshed verification_status and dns_records.
   */
  async function validateEmailConfig(extid: string): Promise<ValidateEmailConfigResponse> {
    const response = await $api.post(`/api/domains/${extid}/email-config/validate`);
    return strictParse(validateEmailConfigResponseSchema, response.data);
  }

  /**
   * Send a test email using the domain's saved email configuration.
   *
   * Works even when the email config is not yet enabled — useful for
   * verifying delivery before flipping the switch.
   */
  async function testEmailConfig(extid: string): Promise<TestEmailConfigResponse> {
    const response = await $api.post(`/api/domains/${extid}/email-config/test`);
    return strictParse(testEmailConfigResponseSchema, response.data);
  }

  /**
   * Reset store state to initial values
   *
   * SECURITY: Also clears the org context to ensure fresh fetch on next access.
   */
  function $reset() {
    records.value = [];
    _initialized.value = false;
    _currentOrgId.value = null;
  }

  return {
    init,

    // State
    records,
    details,
    count,
    _currentOrgId,

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

    // Homepage config
    getHomepageConfig,
    putHomepageConfig,

    // Email config
    getEmailConfig,
    putEmailConfig,
    patchEmailConfig,
    deleteEmailConfig,
    validateEmailConfig,
    testEmailConfig,

    fetchList,
    refreshRecords,
    $reset,
  };
});
