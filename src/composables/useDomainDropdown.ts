// src/composables/useDomainDropdown.ts

import { WindowService } from '@/services/window.service';
import { ref } from 'vue';

// Create a single shared ref for selectedDomain
const selectedDomain = ref('');
const isLoading = ref(false);

export function useDomainDropdown() {
  const { domains_enabled: domainsEnabled, site_host: defaultDomain } = WindowService.getMultiple([
    'domains_enabled',
    'site_host',
  ]);

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
        : availableDomains.value[0]    ;
  }

  const updateSelectedDomain = (domain: string) => {
    selectedDomain.value = domain;
    localStorage.setItem('selectedDomain', domain);
  };

  const addDomain = (domain: string) => {
    if (!availableDomains.value.includes(domain)) {
      availableDomains.value = [...availableDomains.value, domain];

      if (!selectedDomain.value) {
        updateSelectedDomain(domain);
      }
    }
  };

  const removeDomain = (domain: string) => {
    availableDomains.value = availableDomains.value.filter((domain) => domain !== domain);

    if (selectedDomain.value === domain && availableDomains.value.length) {
      updateSelectedDomain(availableDomains.value[0]);
    }
  };

  return {
    availableDomains: availableDomains.value,
    selectedDomain,
    domainsEnabled,
    updateSelectedDomain,
    addDomain,
    removeDomain,
    isLoading,
  };
}
