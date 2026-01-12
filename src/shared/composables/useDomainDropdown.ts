// src/shared/composables/useDomainDropdown.ts

import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { storeToRefs } from 'pinia';
import { ref } from 'vue';

// Create a single shared ref for selectedDomain
const selectedDomain = ref('');
const isLoading = ref(false);

export function useDomainDropdown() {
  const bootstrapStore = useBootstrapStore();
  const { domains_enabled: domainsEnabled, site_host, custom_domains } = storeToRefs(bootstrapStore);

  // Build initial available domains from store values
  const defaultDomain = site_host.value;
  const initialDomains = custom_domains.value ?? [];
  const availableDomains = ref(
    defaultDomain && !initialDomains.includes(defaultDomain)
      ? [...initialDomains, defaultDomain]
      : [...initialDomains]
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

  const addDomain = (domain: string) => {
    if (!availableDomains.value.includes(domain)) {
      availableDomains.value = [...availableDomains.value, domain];

      if (!selectedDomain.value) {
        updateSelectedDomain(domain);
      }
    }
  };

  const removeDomain = (domain: string) => {
    availableDomains.value = availableDomains.value.filter((d) => d !== domain);

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
