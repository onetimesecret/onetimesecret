// src/stores/domainsStore.ts

import { defineStore } from 'pinia';
import type { CustomDomain } from '@/types/onetime';
import { createApi } from '@/utils/api';

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
      this.domains = domains;
    },

    async refreshDomains() {
      this.isLoading = true;
      try {
        const response = await api.get('/api/v2/account/domains');
        this.domains = response.data.domains;
      } catch (error) {
        console.error('Failed to refresh domains:', error);
        throw error;
      } finally {
        this.isLoading = false;
      }
    },

    addDomain(domain: CustomDomain) {
      this.domains.push(domain);
    },

    removeDomain(domainToRemove: string) {
      this.domains = this.domains.filter(
        domain => domain.display_domain !== domainToRemove
      );
    },

    updateDomain(updatedDomain: CustomDomain) {
      this.domains = this.domains.map(domain =>
        domain.display_domain === updatedDomain.display_domain ? updatedDomain : domain
      );
    }
  }
});
