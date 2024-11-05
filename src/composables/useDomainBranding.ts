// src/composables/useDomainBranding.ts
import { computed } from 'vue';
import { BrandSettings } from '@/types/onetime';

import { useWindowProps } from '@/composables/useWindowProps';

const {
  domain_branding,
  domain_strategy,
} = useWindowProps([
  'domain_branding',
  'domain_strategy',
]);


export const domainStrategy = domain_strategy;

// Default branding settings
export const defaultBranding: BrandSettings = {
  primary_color: '#dc4a22', // Default blue color
  instructions_pre_reveal: 'This secret requires confirmation before viewing.',
  instructions_reveal: 'The secret will be displayed below.',
  instructions_post_reveal: 'This secret has been destroyed and cannot be viewed again.',
  button_text_light: true,
  font_family: 'system-ui',
  corner_style: 'rounded',
};

export function useDomainBranding() {
  return computed((): BrandSettings => {
    switch (domain_strategy.value) {
      case 'custom':
        // For custom domains, merge default branding with custom branding if available
        if (domain_branding?.value) {
          return {
            ...defaultBranding,
            ...domain_branding.value
          };
        }
        return defaultBranding;

      case 'subdomain':
        // Subdomains might have their own branding in the future
        return defaultBranding;

      case 'canonical':
      case 'invalid':
      default:
        // Use default branding for canonical domain and invalid domains
        return defaultBranding;
    }
  });
}
