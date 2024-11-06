// src/composables/useDomains.ts
import { computed } from 'vue';
import { useWindowProps } from '@/composables/useWindowProps';
import { useDomainsStore } from '@/stores/domainsStore';
import type { CustomDomain } from '@/types/onetime';

export function useDomains(initialDomains?: CustomDomain[]) {
  const { custom_domains } = useWindowProps(['custom_domains']);
  const domainsStore = useDomainsStore();

  // Initialize store with initialDomains if provided, otherwise use window props
  if (!domainsStore.domains.length) {
    if (initialDomains) {
      domainsStore.setDomains(initialDomains);
    } else if (custom_domains.value) {
      domainsStore.setDomains(custom_domains.value);
    }
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
