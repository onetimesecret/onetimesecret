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
            ...parseDomainBranding(domain_branding.value)
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

interface BrokenBrandSettings {
  primary_color: string;
  instructions_pre_reveal: string;
  instructions_reveal: string;
  instructions_post_reveal: string;
  button_text_light: string; // This is a string in the incoming data
  font_family: string;
  corner_style: string;
}

function parseDomainBranding(data: BrokenBrandSettings): BrandSettings {
  return {
    primary_color: data.primary_color,
    instructions_pre_reveal: data.instructions_pre_reveal,
    instructions_reveal: data.instructions_reveal,
    instructions_post_reveal: data.instructions_post_reveal,
    button_text_light: data.button_text_light === 'true',
    font_family: data.font_family,
    corner_style: data.corner_style,
  };
}
