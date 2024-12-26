import type { BrandSettings } from '@/schemas/models/domain';

export const mockDefaultBranding: BrandSettings = {
  primary_color: '#007bff',
  font_family: 'Roboto, sans-serif',
  corner_style: 'rounded',
  button_text_light: true,
};

export const mockCustomBranding: BrandSettings = {
  primary_color: '#ff4400',
  font_family: 'Poppins, sans-serif',
  corner_style: 'sharp',
  button_text_light: false,
};

export const mockDomains = {
  'domain-1': {
    id: 'domain-1',
    name: 'example.com',
    brand: mockCustomBranding,
  },
  'domain-2': {
    id: 'domain-2',
    name: 'default.com',
    brand: mockDefaultBranding,
  },
};
