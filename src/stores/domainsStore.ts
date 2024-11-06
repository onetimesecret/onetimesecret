import type { UpdateDomainBrandRequest } from '@/types/api/requests';
import type { UpdateDomainBrandResponse } from '@/types/api/responses';
import type { CustomDomain } from '@/types/onetime';
import { createApi } from '@/utils/api';
import { defineStore } from 'pinia';

const api = createApi();

interface DomainsState {
  domains: CustomDomain[];
  isLoading: boolean;
}

export const useDomainsStore = defineStore('domains', {
  state: (): DomainsState => ({
    domains: [],
    isLoading: false
  }),

  actions: {
    setDomains(domains: CustomDomain[]) {
      this.domains = domains || [];
    },

    async refreshDomains() {
      this.isLoading = true;
      try {
        console.log('[DomainsStore] Attempting to fetch domains');
        const response = await api.get('/api/v2/account/domains');
        console.log('[DomainsStore] API Response:', {
          status: response.status,
          data: response.data
        });

        // Detailed logging of domains
        if (response.data && response.data.domains) {
          console.log('[DomainsStore] Domains received:', response.data.domains.length);
          console.log('[DomainsStore] First domain (if any):',
            response.data.domains.length > 0 ? response.data.domains[0] : 'No domains');
        } else {
          console.warn('[DomainsStore] No domains found in response');
        }

        this.domains = response.data.domains || [];
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
        this.removeDomain(domainName);
      } catch (error) {
        console.error('Failed to delete domain:', error);
        throw error;
      }
    },

    async toggleHomepageAccess(domain: CustomDomain) {
      const newHomepageStatus = !domain?.brand?.allow_public_homepage;

      try {
        const updateRequest: UpdateDomainBrandRequest = {
          brand: { allow_public_homepage: newHomepageStatus }
        };

        const response = await api.put<UpdateDomainBrandResponse>(
          `/api/v2/account/domains/${domain.display_domain}/brand`,
          updateRequest
        );

        // Use the response data if available
        const updatedDomain = response.data?.domain || {
          ...domain,
          brand: domain.brand ? {
            ...domain.brand,
            allow_public_homepage: newHomepageStatus
          } : { allow_public_homepage: newHomepageStatus }
        };

        // Ensure we always have a valid domains array
        if (!this.domains) {
          this.domains = [];
        }

        // Update the domain in the store
        const domainIndex = this.domains.findIndex(
          d => d.display_domain === domain.display_domain
        );

        if (domainIndex !== -1) {
          // Replace the domain at the found index
          this.domains = [
            ...this.domains.slice(0, domainIndex),
            updatedDomain,
            ...this.domains.slice(domainIndex + 1)
          ];
        } else {
          // If domain not found, add it to the array
          this.domains.push(updatedDomain);
        }

        return newHomepageStatus;
      } catch (error) {
        console.error('Failed to toggle homepage access:', error);
        throw error;
      }
    },

    addDomain(domain: CustomDomain) {
      // Ensure domains is an array before pushing
      if (!this.domains) {
        this.domains = [];
      }
      this.domains.push(domain);
    },

    removeDomain(domainToRemove: string) {
      // Ensure domains is an array before filtering
      this.domains = (this.domains || []).filter(
        domain => domain.display_domain !== domainToRemove
      );
    },

    updateDomain(updatedDomain: CustomDomain) {
      // Ensure domains is an array before mapping
      if (!this.domains) {
        this.domains = [];
      }

      // Find and replace the domain
      const domainIndex = this.domains.findIndex(
        domain => domain.display_domain === updatedDomain.display_domain
      );

      if (domainIndex !== -1) {
        // Create a new array with the updated domain
        this.domains = [
          ...this.domains.slice(0, domainIndex),
          updatedDomain,
          ...this.domains.slice(domainIndex + 1)
        ];
      } else {
        // If domain not found, add it to the array
        this.domains.push(updatedDomain);
      }
    }
  }
});
