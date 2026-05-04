// src/tests/fixtures/domainBranding.fixture.ts
//
// Brand settings test fixtures, neutralized per #3049 — no OTS branding.
//
// Type source: BrandSettingsCanonical (22-field canonical contract).
// v2 shape (`@/schemas/shapes/v2/custom-domain`) is intentionally not used
// here because it lacks the 7 new fields (`product_name`, `product_domain`,
// `support_email`, `footer_text`, `logo_url`, `logo_dark_url`, `favicon_url`).

import type { BrandSettingsCanonical } from '@/schemas/contracts/custom-domain';

export const mockDefaultBranding: BrandSettingsCanonical = {
  primary_color: '#3B82F6',
  product_name: 'My App',
  product_domain: 'app.example.test',
  support_email: 'support@example.test',
  footer_text: null,
  logo_url: null,
  logo_dark_url: null,
  favicon_url: null,
  font_family: 'sans',
  corner_style: 'rounded',
  button_text_light: true,
  allow_public_homepage: false,
  allow_public_api: false,
  locale: 'en',
  default_ttl: null,
  passphrase_required: false,
  notify_enabled: false,
  description: undefined,
  instructions_pre_reveal: null,
  instructions_reveal: null,
  instructions_post_reveal: null,
  colour: undefined,
};

export const mockCustomBrandingRed: BrandSettingsCanonical = {
  primary_color: '#FF4400',
  product_name: 'Acme Vault',
  product_domain: 'secrets.acme.test',
  support_email: 'help@acme.test',
  footer_text: 'Powered by Acme',
  logo_url: 'https://acme.test/logo.svg',
  logo_dark_url: 'https://acme.test/logo-dark.svg',
  favicon_url: 'https://acme.test/favicon.ico',
  font_family: 'sans',
  corner_style: 'square',
  button_text_light: false,
  allow_public_homepage: false,
  allow_public_api: false,
  locale: 'en',
  default_ttl: null,
  passphrase_required: false,
  notify_enabled: false,
  description: undefined,
  instructions_pre_reveal: null,
  instructions_reveal: null,
  instructions_post_reveal: null,
  colour: undefined,
};

export const mockCustomBrandingViolet: BrandSettingsCanonical = {
  primary_color: '#8A2BE2',
  product_name: 'Violet Notes',
  product_domain: 'notes.violet.test',
  support_email: 'hello@violet.test',
  footer_text: null,
  logo_url: null,
  logo_dark_url: null,
  favicon_url: null,
  font_family: 'mono',
  corner_style: 'pill',
  button_text_light: true,
  allow_public_homepage: true,
  allow_public_api: true,
  locale: 'en',
  default_ttl: null,
  passphrase_required: false,
  notify_enabled: false,
  description: 'Custom purple theme with monospace font',
  instructions_pre_reveal: 'Click below to view your secret',
  instructions_reveal: null,
  instructions_post_reveal: 'Secret has been revealed and destroyed',
  colour: undefined,
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
