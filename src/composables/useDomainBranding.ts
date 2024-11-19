// src/composables/useDomainBranding.ts
import { useWindowProps } from '@/composables/useWindowProps';
import { useDomainsStore } from '@/stores/domainsStore';
import { computed } from 'vue';

const {
  domain_branding,
  domain_strategy,
} = useWindowProps([
  'domain_branding',
  'domain_strategy',
]);

export const domainStrategy = domain_strategy;

export function useDomainBranding() {
  const domainsStore = useDomainsStore();

  return computed(() => {
    switch (domain_strategy.value) {
      case 'custom':
        if (domain_branding?.value) {
          return domainsStore.parseDomainBranding({ brand: domain_branding.value }).brand;
        }
        return domainsStore.defaultBranding;

      case 'subdomain':
      case 'canonical':
      case 'invalid':
      default:
        return domainsStore.defaultBranding;
    }
  });
}
