// src/stores/domainsStore.ts

import { createApiError, zodErrorToApiError } from '@/schemas';
import { UpdateDomainBrandRequest } from '@/schemas/api';
import { responseSchemas } from '@/schemas/api/responses';
import type { BrandSettings, CustomDomain } from '@/schemas/models';
import { createApi } from '@/utils/api';
import { defineStore } from 'pinia';
import { z } from 'zod';

const api = createApi();

interface DomainsState {
  domains: CustomDomain[];
  isLoading: boolean;
  defaultBranding: BrandSettings;
}

export const useDomainsStore = defineStore('domains', {
  state: (): DomainsState => ({
    domains: [],
    isLoading: false,
    defaultBranding: {} as BrandSettings,
  }),

  actions: {
    handleApiError(error: unknown): never {
      if (error instanceof z.ZodError) {
        throw zodErrorToApiError(error);
      }
      throw createApiError(
        'SERVER',
        'SERVER_ERROR',
        error instanceof Error ? error.message : 'Unknown error occurred'
      );
    },

    async refreshDomains() {
      this.isLoading = true;
      try {
        const response = await api.get('/api/v2/account/domains');
        const validated = responseSchemas.customDomainList.parse(response.data);
        this.domains = validated.records;
      } catch (error) {
        this.handleApiError(error);
      } finally {
        this.isLoading = false;
      }
    },

    async updateDomainBrand(domain: string, brandUpdate: UpdateDomainBrandRequest) {
      try {
        const response = await api.put(`/api/v2/account/domains/${domain}/brand`, brandUpdate);
        const validated = responseSchemas.customDomain.parse(response.data);

        const domainIndex = this.domains.findIndex((d) => d.display_domain === domain);
        if (domainIndex !== -1) {
          this.domains[domainIndex] = validated.record;
        }
        return validated.record;
      } catch (error) {
        this.handleApiError(error);
      }
    },

    async addDomain(domain: string) {
      try {
        const response = await api.post('/api/v2/account/domains/add', { domain });
        const validated = responseSchemas.customDomain.parse(response.data);
        this.domains.push(validated.record);
        return validated.record;
      } catch (error) {
        this.handleApiError(error);
      }
    },

    async deleteDomain(domainName: string) {
      try {
        await api.post(`/api/v2/account/domains/${domainName}/remove`);
        this.domains = this.domains.filter((domain) => domain.display_domain !== domainName);
      } catch (error) {
        this.handleApiError(error);
      }
    },

    async getBrandSettings(domain: string) {
      try {
        const response = await api.get(`/api/v2/account/domains/${domain}/brand`);
        return responseSchemas.brandSettings.parse(response.data);
      } catch (error) {
        this.handleApiError(error);
      }
    },

    async updateBrandSettings(domain: string, settings: Partial<BrandSettings>) {
      try {
        const response = await api.put(`/api/v2/account/domains/${domain}/brand`, {
          brand: settings,
        });
        return responseSchemas.brandSettings.parse(response.data);
      } catch (error) {
        this.handleApiError(error);
      }
    },

    async toggleHomepageAccess(domain: CustomDomain) {
      const newHomepageStatus = !domain.brand?.allow_public_homepage;
      const domainIndex = this.domains.findIndex((d) => d.display_domain === domain.display_domain);

      try {
        const response = await api.put(`/api/v2/account/domains/${domain.display_domain}/brand`, {
          brand: { allow_public_homepage: newHomepageStatus },
        });
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
        this.handleApiError(error);
      }
    },

    async updateDomain(domain: CustomDomain) {
      try {
        const response = await api.put(`/api/v2/account/domains/${domain.display_domain}`, domain);
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
        this.handleApiError(error);
      }
    },
  },
});
