// src/stores/domainsStore.ts
import { ErrorHandlerOptions, useErrorHandler } from '@/composables/useErrorHandler';
import { UpdateDomainBrandRequest } from '@/schemas/api';
import { responseSchemas } from '@/schemas/api/responses';
import type { BrandSettings, CustomDomain } from '@/schemas/models';
import { createApi } from '@/utils/api';
import { AxiosInstance } from 'axios';
import { defineStore } from 'pinia';

interface StoreState {
  isLoading: boolean;
  domains: CustomDomain[];
  initialized: boolean;
}

export const useDomainsStore = defineStore('domains', {
  state: (): StoreState => ({
    isLoading: false,
    domains: [] as CustomDomain[],
    initialized: false,
  }),

  getters: {
    recordCount: (state) => state.domains.length,
  },

  actions: {
    // Inject API client through closure
    _api: null as AxiosInstance | null,
    _errorHandler: null as ReturnType<typeof useErrorHandler> | null,

    _ensureErrorHandler() {
      if (!this._errorHandler) this.setupErrorHandler();
    },

    // Allow passing options during initialization
    setupErrorHandler(
      api: AxiosInstance = createApi(),
      options: ErrorHandlerOptions = {}
    ) {
      this._api = api;
      this._errorHandler = useErrorHandler({
        setLoading: (isLoading) => {
          this.isLoading = isLoading;
        },
        notify: options.notify, // Allow UI layer to handle notifications if provided
        log: options.log, // Allow custom logging if provided
      });
    },

    async addDomain(domain: string) {
      this._ensureErrorHandler();

      return await this._errorHandler!.withErrorHandling(async () => {
        const response = await this._api!.post('/api/v2/account/domains/add', { domain });
        const validated = responseSchemas.customDomain.parse(response.data);
        this.domains.push(validated.record);
        return validated.record;
      });
    },

    async refreshRecords() {
      if (this.initialized) return; // prevent repeated calls when 0 domains
      this._ensureErrorHandler();

      return await this._errorHandler!.withErrorHandling(async () => {
        const response = await this._api!.get('/api/v2/account/domains');
        const validated = responseSchemas.customDomainList.parse(response.data);
        this.domains = validated.records;
        return validated.records;
      });
    },

    async updateDomainBrand(domain: string, brandUpdate: UpdateDomainBrandRequest) {
      this._ensureErrorHandler();

      return await this._errorHandler!.withErrorHandling(async () => {
        const response = await this._api!.put(
          `/api/v2/account/domains/${domain}/brand`,
          brandUpdate
        );
        const validated = responseSchemas.customDomain.parse(response.data);

        const domainIndex = this.domains.findIndex((d) => d.display_domain === domain);
        if (domainIndex !== -1) {
          this.domains[domainIndex] = validated.record;
        }
        return validated.record;
      });
    },

    async deleteDomain(domainName: string) {
      this._ensureErrorHandler();

      return await this._errorHandler!.withErrorHandling(async () => {
        await this._api!.post(`/api/v2/account/domains/${domainName}/remove`);
        this.domains = this.domains.filter(
          (domain) => domain.display_domain !== domainName
        );
      });
    },

    async getBrandSettings(domain: string) {
      this._ensureErrorHandler();

      return await this._errorHandler!.withErrorHandling(async () => {
        const response = await this._api!.get(`/api/v2/account/domains/${domain}/brand`);
        return responseSchemas.brandSettings.parse(response.data);
      });
    },

    async updateBrandSettings(domain: string, settings: Partial<BrandSettings>) {
      this._ensureErrorHandler();

      return await this._errorHandler!.withErrorHandling(async () => {
        const response = await this._api!.put(`/api/v2/account/domains/${domain}/brand`, {
          brand: settings,
        });
        return responseSchemas.brandSettings.parse(response.data);
      });
    },

    async updateDomain(domain: CustomDomain) {
      this._ensureErrorHandler();

      return await this._errorHandler!.withErrorHandling(async () => {
        const response = await this._api!.put(
          `/api/v2/account/domains/${domain.display_domain}`,
          domain
        );
        const validated = responseSchemas.customDomain.parse(response.data);

        const domainIndex = this.domains.findIndex(
          (d) => d.display_domain === domain.display_domain
        );

        if (domainIndex !== -1) {
          this.domains[domainIndex] = validated.record;
        } else {
          this.domains.push(validated.record);
        }
        return validated.record;
      });
    },
  },
});
