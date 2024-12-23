// src/stores/domainsStore.ts

import { useStoreError } from '@/composables/useStoreError';
import { ApiError, UpdateDomainBrandRequest } from '@/schemas/api';
import { responseSchemas } from '@/schemas/api/responses';
import type { BrandSettings, CustomDomain } from '@/schemas/models';
import { createApi } from '@/utils/api';
import { defineStore } from 'pinia';

const api = createApi();

interface DomainsState {
  isLoading: boolean;
  error: ApiError | null;
  domains: CustomDomain[];
  defaultBranding: BrandSettings;
}

export const useDomainsStore = defineStore('domains', {
  state: (): DomainsState => ({
    isLoading: false,
    error: null,
    domains: [],
    defaultBranding: {} as BrandSettings,
  }),

  actions: {
    handleError(error: unknown): ApiError {
      const { handleError } = useStoreError();
      this.error = handleError(error);
      return this.error;
    },

    async refreshDomains() {
      this.isLoading = true;
      try {
        const response = await api.get('/api/v2/account/domains');
        const validated = responseSchemas.customDomainList.parse(response.data);
        this.domains = validated.records;
      } catch (error) {
        this.handleError(error);
      } finally {
        this.isLoading = false;
      }
    },

    async updateDomainBrand(domain: string, brandUpdate: UpdateDomainBrandRequest) {
      try {
        const response = await api.put(
          `/api/v2/account/domains/${domain}/brand`,
          brandUpdate
        );
        const validated = responseSchemas.customDomain.parse(response.data);

        const domainIndex = this.domains.findIndex((d) => d.display_domain === domain);
        if (domainIndex !== -1) {
          this.domains[domainIndex] = validated.record;
        }
        return validated.record;
      } catch (error) {
        this.handleError(error);
      }
    },

    async addDomain(domain: string) {
      try {
        const response = await api.post('/api/v2/account/domains/add', { domain });
        const validated = responseSchemas.customDomain.parse(response.data);
        this.domains.push(validated.record);
        return validated.record;
      } catch (error) {
        this.handleError(error);
      }
    },

    async deleteDomain(domainName: string) {
      try {
        await api.post(`/api/v2/account/domains/${domainName}/remove`);
        this.domains = this.domains.filter(
          (domain) => domain.display_domain !== domainName
        );
      } catch (error) {
        this.handleError(error);
      }
    },

    async getBrandSettings(domain: string) {
      try {
        const response = await api.get(`/api/v2/account/domains/${domain}/brand`);
        return responseSchemas.brandSettings.parse(response.data);
      } catch (error) {
        this.handleError(error);
      }
    },

    async updateBrandSettings(domain: string, settings: Partial<BrandSettings>) {
      try {
        const response = await api.put(`/api/v2/account/domains/${domain}/brand`, {
          brand: settings,
        });
        return responseSchemas.brandSettings.parse(response.data);
      } catch (error) {
        this.handleError(error);
      }
    },

    async toggleHomepageAccess(domain: CustomDomain) {
      const newHomepageStatus = !domain.brand?.allow_public_homepage;
      const domainIndex = this.domains.findIndex(
        (d) => d.display_domain === domain.display_domain
      );

      try {
        const response = await api.put(
          `/api/v2/account/domains/${domain.display_domain}/brand`,
          {
            brand: { allow_public_homepage: newHomepageStatus },
          }
        );
        const validated = responseSchemas.customDomain.parse(response.data);

        if (domainIndex !== -1) {
          this.domains[domainIndex] = validated.record;
        }
        return newHomepageStatus;
      } catch (error) {
        // Revert on error
        if (domainIndex !== -1) {
          this.domains[domainIndex] = domain;
        }
        this.handleError(error);
      }
    },

    async updateDomain(domain: CustomDomain) {
      try {
        const response = await api.put(
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
      } catch (error) {
        this.handleError(error);
      }
    },
  },
});
