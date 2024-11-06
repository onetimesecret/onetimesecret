// src/composables/useDomains.ts

import { computed } from 'vue';
import { useWindowProps } from '@/composables/useWindowProps';
import { useDomainsStore } from '@/stores/domainsStore';
import type { CustomDomain } from '@/types/onetime';

export function useDomains() {
  const { custom_domains } = useWindowProps(['custom_domains']);
  const domainsStore = useDomainsStore();

  // Initialize store with window props data
  if (custom_domains.value && !domainsStore.domains.length) {
    domainsStore.setDomains(custom_domains.value);
  }

  // Computed property to get the domains from store
  const domains = computed<CustomDomain[]>(() => domainsStore.domains);
  const isLoading = computed(() => domainsStore.isLoading);

  return {
    domains,
    isLoading,
    refreshDomains: domainsStore.refreshDomains,
    addDomain: domainsStore.addDomain,
    removeDomain: domainsStore.removeDomain,
    updateDomain: domainsStore.updateDomain
  };
}
