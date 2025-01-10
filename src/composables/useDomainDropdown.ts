//  src/composables/useDomainDropdown.ts

import { WindowService } from '@/services/window.service';
import { ref, watch } from 'vue';

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

  const getSavedDomain = () => {
    const savedDomain = localStorage.getItem('selectedDomain');
    return savedDomain && availableDomains.value.includes(savedDomain)
      ? savedDomain
      : availableDomains.value[0];
  };

  const selectedDomain = ref(getSavedDomain());

  watch(selectedDomain, (newDomain) => {
    localStorage.setItem('selectedDomain', newDomain);
  });

  const updateSelectedDomain = (domain: string) => {
    selectedDomain.value = domain;
  };

  return {
    availableDomains: availableDomains.value,
    selectedDomain,
    domainsEnabled,
    updateSelectedDomain,
  };
}
