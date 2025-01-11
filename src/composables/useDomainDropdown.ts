//  src/composables/useDomainDropdown.ts

import { WindowService } from '@/services/window.service';
import { ref } from 'vue';

// Create a single shared ref for selectedDomain
const selectedDomain = ref('');

export function useDomainDropdown() {
  const { domains_enabled: domainsEnabled, site_host: defaultDomain } =
    WindowService.getMultiple(['form_fields', 'domains_enabled', 'site_host']);

  const availableDomains = ref(
    (() => {
      const domains = WindowService.get('custom_domains') ?? [];
      return defaultDomain && !domains.includes(defaultDomain)
        ? [...domains, defaultDomain]
        : domains;
    })()
  );

  // Initialize selectedDomain only if it hasn't been set
  if (!selectedDomain.value) {
    const savedDomain = localStorage.getItem('selectedDomain');
    selectedDomain.value =
      savedDomain && availableDomains.value.includes(savedDomain)
        ? savedDomain
        : availableDomains.value[0];
  }

  const updateSelectedDomain = (domain: string) => {
    selectedDomain.value = domain;
    localStorage.setItem('selectedDomain', domain);
  };

  return {
    availableDomains: availableDomains.value,
    selectedDomain,
    domainsEnabled,
    updateSelectedDomain,
  };
}
