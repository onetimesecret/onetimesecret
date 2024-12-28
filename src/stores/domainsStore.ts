// src/stores/domainsStore.ts

import { ApiError, UpdateDomainBrandRequest } from '@/schemas/api';
import { responseSchemas } from '@/schemas/api/responses';
import type { BrandSettings, CustomDomain } from '@/schemas/models';
import { createApi } from '@/utils/api';
import { AxiosInstance } from 'axios';
import { defineStore } from 'pinia';

interface StoreState {
  isLoading: boolean;
  error: ApiError | null;
  domains: CustomDomain[];
  initialized: boolean;
}

export const useDomainsStore = defineStore('domains', {
  state: (): StoreState => ({
    isLoading: false,
    error: null,
    domains: [] as CustomDomain[],
    initialized: false,
  }),

  getters: {
    recordCount: (state) => state.domains.length,
  },

  actions: {
    // Inject API client through closure
    _api: null as AxiosInstance | null,

    // Initialization action
    init(api: AxiosInstance = createApi()) {
      this._api = api;
    },

    async addDomain(domain: string) {
      return await this.withLoading(async () => {
        const response = await this._api!.post('/api/v2/account/domains/add', { domain });
        const validated = responseSchemas.customDomain.parse(response.data);
        this.domains.push(validated.record);
        return validated.record;
      });
    },

    async refreshRecords() {
      if (this.initialized) return; // prevent repeated calls when 0 domains
      return await this.withLoading(async () => {
        const response = await this._api!.get('/api/v2/account/domains');
        const validated = responseSchemas.customDomainList.parse(response.data);
        this.domains = validated.records;
        return validated.records;
      });
    },

    async updateDomainBrand(domain: string, brandUpdate: UpdateDomainBrandRequest) {
      return await this.withLoading(async () => {
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
      return await this.withLoading(async () => {
        await this._api!.post(`/api/v2/account/domains/${domainName}/remove`);
        this.domains = this.domains.filter(
          (domain) => domain.display_domain !== domainName
        );
      });
    },

    async getBrandSettings(domain: string) {
      return await this.withLoading(async () => {
        const response = await this._api!.get(`/api/v2/account/domains/${domain}/brand`);
        return responseSchemas.brandSettings.parse(response.data);
      });
    },

    async updateBrandSettings(domain: string, settings: Partial<BrandSettings>) {
      return await this.withLoading(async () => {
        const response = await this._api!.put(`/api/v2/account/domains/${domain}/brand`, {
          brand: settings,
        });
        return responseSchemas.brandSettings.parse(response.data);
      });
    },

    async updateDomain(domain: CustomDomain) {
      return await this.withLoading(async () => {
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
