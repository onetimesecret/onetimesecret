import type { UpdateDomainBrandRequest } from '@/types/api/requests';
import type { UpdateDomainBrandResponse, CustomDomainRecordsApiResponse } from '@/types/api/responses';
import type { BrandSettings, CustomDomain } from '@/types/custom_domains';
import { createApi } from '@/utils/api';
import { defineStore } from 'pinia';

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
    defaultBranding: {
      primary_color: '#dc4a22',
      instructions_pre_reveal: 'This secret requires confirmation before viewing.',
      instructions_reveal: 'The secret will be displayed below.',
      instructions_post_reveal: 'This secret has been destroyed and cannot be viewed again.',
      button_text_light: true,
      font_family: 'system-ui',
      corner_style: 'rounded',
      allow_public_homepage: false,
      allow_public_api: false,
    }
  }),

  actions: {
    parseDomainBranding(domain: CustomDomain): CustomDomain {
      if (!domain.brand) return domain;

      return {
        ...domain,
        brand: {
          ...this.defaultBranding,
          primary_color: domain.brand.primary_color,
          instructions_pre_reveal: domain.brand.instructions_pre_reveal,
          instructions_reveal: domain.brand.instructions_reveal,
          instructions_post_reveal: domain.brand.instructions_post_reveal,
          button_text_light: domain.brand.button_text_light,
          font_family: domain.brand.font_family,
          corner_style: domain.brand.corner_style,
          allow_public_homepage: domain.brand.allow_public_homepage,
          allow_public_api: domain.brand.allow_public_api,
        }
      };
    },

    setDomains(domains: CustomDomain[]) {
      this.domains = domains?.map(domain => this.parseDomainBranding(domain)) || [];
    },

    async refreshDomains() {
      this.isLoading = true;
      try {
        console.debug('[DomainsStore] Attempting to fetch domains');
        const response = await api.get<CustomDomainRecordsApiResponse>('/api/v2/account/domains');
        console.debug('[DomainsStore] API Response:', {
          status: response.status,
          data: response.data
        });

        // Parse branding when setting domains
        this.domains = response.data.records?.map(domain => this.parseDomainBranding(domain)) || [];
      } catch (error) {
        console.error('[DomainsStore] Failed to refresh domains:', error);
        this.domains = []; // Ensure domains is always an array

        // More detailed error logging
        if (error instanceof Error) {
          console.error('[DomainsStore] Error details:', {
            message: error.message,
            name: error.name,
            stack: error.stack
          });
        }

        throw error;
      } finally {
        this.isLoading = false;
      }
    },

    async deleteDomain(domainName: string) {
      try {
        await api.post(`/api/v2/account/domains/${domainName}/remove`);
        this.removeDomainFromList(domainName);
      } catch (error) {
        console.error('Failed to delete domain:', error);
        throw error;
      }
    },

    async toggleHomepageAccess(domain: CustomDomain) {
      const newHomepageStatus = !domain?.brand?.allow_public_homepage;

      // Optimistically update the UI
      const domainIndex = this.domains.findIndex(
        d => d.display_domain === domain.display_domain
      );

      if (domainIndex !== -1) {
        const optimisticUpdate = this.parseDomainBranding({
          ...domain,
          brand: {
            ...(domain.brand || {}),
            allow_public_homepage: newHomepageStatus
          }
        });

        this.domains = [
          ...this.domains.slice(0, domainIndex),
          optimisticUpdate,
          ...this.domains.slice(domainIndex + 1)
        ];
      }

      try {
        const updateRequest: UpdateDomainBrandRequest = {
          brand: { allow_public_homepage: newHomepageStatus }
        };

        const response = await api.put<UpdateDomainBrandResponse>(
          `/api/v2/account/domains/${domain.display_domain}/brand`,
          updateRequest
        );

        // Update with the server response
        const updatedDomain = this.parseDomainBranding(
          response.data?.result || {
            ...domain,
            brand: {
              ...(domain.brand || {}),
              allow_public_homepage: newHomepageStatus
            }
          }
        );

        // Update the store with the server response
        if (domainIndex !== -1) {
          this.domains = [
            ...this.domains.slice(0, domainIndex),
            updatedDomain,
            ...this.domains.slice(domainIndex + 1)
          ];
        }

        return newHomepageStatus;
      } catch (error) {
        // Revert the optimistic update on error
        if (domainIndex !== -1) {
          this.domains = [
            ...this.domains.slice(0, domainIndex),
            domain,
            ...this.domains.slice(domainIndex + 1)
          ];
        }
        console.error('Failed to toggle homepage access:', error);
        throw error;
      }
    }
    ,

    addDomain(domain: CustomDomain) {
      if (!this.domains) {
        this.domains = [];
      }
      // Parse branding when adding domain
      this.domains.push(this.parseDomainBranding(domain));
    },

    removeDomainFromList(domainToRemove: string) {
      // Ensure domains is an array before filtering
      this.domains = (this.domains || []).filter(
        domain => domain.display_domain !== domainToRemove
      );
    },

    updateDomain(updatedDomain: CustomDomain) {
      if (!this.domains) {
        this.domains = [];
      }

      // Parse branding when updating domain
      const parsedDomain = this.parseDomainBranding(updatedDomain);
      const domainIndex = this.domains.findIndex(
        domain => domain.display_domain === updatedDomain.display_domain
      );

      if (domainIndex !== -1) {
        this.domains = [
          ...this.domains.slice(0, domainIndex),
          parsedDomain,
          ...this.domains.slice(domainIndex + 1)
        ];
      } else {
        this.domains.push(parsedDomain);
      }
    }
  }
});
