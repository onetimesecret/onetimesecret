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



    async toggleHomepageAccess(domain: CustomDomain) {
      const newHomepageStatus = !domain?.brand?.allow_public_homepage;

      try {
        await api.put(`/api/v2/account/domains/${domain.display_domain}/brand`, {
          brand: { allow_public_homepage: newHomepageStatus }
        });

        // Ensure we maintain all required fields from the original brand settings
        if (domain.brand) {
          this.updateDomain({
            ...domain,
            brand: {
              primary_color: domain.brand.primary_color,
              instructions_pre_reveal: domain.brand.instructions_pre_reveal,
              instructions_reveal: domain.brand.instructions_reveal,
              instructions_post_reveal: domain.brand.instructions_post_reveal,
              button_text_light: domain.brand.button_text_light,
              font_family: domain.brand.font_family,
              corner_style: domain.brand.corner_style,
              allow_public_homepage: newHomepageStatus
            }
          });
        }

        return newHomepageStatus;
      } catch (error) {
        console.error('Failed to toggle homepage access:', error);
        throw error;
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
