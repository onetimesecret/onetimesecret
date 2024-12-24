// src/stores/domainsStore.ts

import { useStoreError } from '@/composables/useStoreError';
import { ApiError, UpdateDomainBrandRequest } from '@/schemas/api';
import { responseSchemas } from '@/schemas/api/responses';
import type { BrandSettings, CustomDomain } from '@/schemas/models';
import { useNotificationsStore } from '@/stores/notifications';
import { createApi } from '@/utils/api';
import { defineStore } from 'pinia';

const api = createApi();

interface DomainsState {
  isLoading: boolean;
  error: ApiError | null;
  domains: CustomDomain[];
}

export const useDomainsStore = defineStore('domains', {
  state: (): DomainsState => ({
    isLoading: false,
    error: null,
    domains: [] as CustomDomain[],
  }),

  actions: {
    handleError(error: unknown): ApiError {
      const { handleError } = useStoreError();
      this.error = handleError(error);
      return this.error;
    },

    async refreshDomains() {
      return await this.withLoading(async () => {
        const response = await api.get('/api/v2/account/domains');
        const validated = responseSchemas.customDomainList.parse(response.data);
        this.domains = validated.records;
        return validated.records;
      });
    },

    async updateDomainBrand(domain: string, brandUpdate: UpdateDomainBrandRequest) {
      return await this.withLoading(async () => {
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
      });
    },

    async addDomain(domain: string) {
      const notifications = useNotificationsStore();

      return await this.withLoading(async () => {
        const response = await api.post('/api/v2/account/domains/add', { domain });
        const validated = responseSchemas.customDomain.parse(response.data);
        this.domains.push(validated.record);
        notifications.show(`Added domain ${domain}`, 'success');
        return validated.record;
      });
    },

    async deleteDomain(domainName: string) {
      return await this.withLoading(async () => {
        await api.post(`/api/v2/account/domains/${domainName}/remove`);
        this.domains = this.domains.filter(
          (domain) => domain.display_domain !== domainName
        );
      });
    },

    async getBrandSettings(domain: string) {
      return await this.withLoading(async () => {
        const response = await api.get(`/api/v2/account/domains/${domain}/brand`);
        return responseSchemas.brandSettings.parse(response.data);
      });
    },

    async updateBrandSettings(domain: string, settings: Partial<BrandSettings>) {
      return await this.withLoading(async () => {
        const response = await api.put(`/api/v2/account/domains/${domain}/brand`, {
          brand: settings,
        });
        return responseSchemas.brandSettings.parse(response.data);
      });
    },

    async toggleHomepageAccess(domain: CustomDomain) {
      return await this.withLoading(async () => {
        const newHomepageStatus = !domain.brand?.allow_public_homepage;
        const domainIndex = this.domains.findIndex(
          (d) => d.display_domain === domain.display_domain
        );

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
      });
    },

    async updateDomain(domain: CustomDomain) {
      return await this.withLoading(async () => {
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
      });
    },
  },
});
