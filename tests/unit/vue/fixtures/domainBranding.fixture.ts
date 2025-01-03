import type { BrandSettings } from '@/schemas/models/domain';

export const mockDefaultBranding: BrandSettings = {
  primary_color: '#007bff',
  font_family: 'sans',
  corner_style: 'rounded',
  button_text_light: true,
  allow_public_homepage: false,
  allow_public_api: false,
};

export const mockCustomBrandingRed: BrandSettings = {
  primary_color: '#ff4400',
  font_family: 'sans',
  corner_style: 'square',
  button_text_light: false,
  allow_public_homepage: false,
  allow_public_api: false,
};

export const mockCustomBrandingViolet: BrandSettings = {
  primary_color: '#8A2BE2',
  font_family: 'mono',
  corner_style: 'pill',
  button_text_light: true,
  allow_public_homepage: true,
  allow_public_api: true,
  description: 'Custom purple theme with monospace font',
  instructions_pre_reveal: 'Click below to view your secret',
  instructions_post_reveal: 'Secret has been revealed and destroyed',
};

export const mockDomains = {
  'domain-1': {
    id: 'domain-1',
    name: 'example.com',
    brand: mockCustomBrandingRed,
  },
  'domain-2': {
    id: 'domain-2',
    name: 'default.com',
    brand: mockDefaultBranding,
  },
};
