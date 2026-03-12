// src/tests/fixtures/domains.fixture.ts

import type { CustomDomain } from '@/schemas/models';

const BASE_DOMAIN = {
  identifier: '',
  domainid: '',
  extid: '',
  custid: 'cust-123',
  subdomain: '',
  trd: '',
  is_apex: false,
  verified: false,
} as const;

const BRAND_DOMAIN1 = {
  primary_color: '#ff4400',
  font_family: 'sans',
  corner_style: 'square',
  button_text_light: false,
  allow_public_api: false,
  allow_public_homepage: false,
  locale: 'en',
  notify_enabled: false,
  passphrase_required: false,
} as const;

const BRAND_DOMAIN2 = {
  primary_color: '#007bff',
  font_family: 'sans',
  corner_style: 'rounded',
  button_text_light: true,
  allow_public_api: false,
  allow_public_homepage: false,
  locale: 'en',
  notify_enabled: false,
  passphrase_required: false,
} as const;

// V3 API wire format (Unix epoch seconds for timestamps)
export const mockDomainsRaw: Record<string, Record<string, unknown>> = {
  'domain-1': {
    ...BASE_DOMAIN,
    identifier: 'domain-1',
    domainid: 'did-1',
    extid: 'dm-ext-1',
    display_domain: 'example.com',
    base_domain: 'example.com',
    tld: 'com',
    sld: 'example',
    txt_validation_host: '_validate.example.com',
    txt_validation_value: 'validate123',
    created: 1704067200,     // 2024-01-01T00:00:00Z
    updated: 1704067200,
    verified: true,
    is_apex: true,
    brand: { ...BRAND_DOMAIN1 },
    vhost: {},
  },
  'domain-2': {
    ...BASE_DOMAIN,
    identifier: 'domain-2',
    domainid: 'did-2',
    extid: 'dm-ext-2',
    display_domain: 'test.com',
    base_domain: 'test.com',
    tld: 'com',
    sld: 'test',
    txt_validation_host: '_validate.test.com',
    txt_validation_value: 'validate456',
    created: 1704153600,     // 2024-01-02T00:00:00Z
    updated: 1704153600,
    brand: { ...BRAND_DOMAIN2 },
    vhost: {},
  },
};

// Transformed format (after V3 Zod parse) — used for assertions
export const mockDomains: Record<string, CustomDomain> = {
  'domain-1': {
    ...BASE_DOMAIN,
    identifier: 'domain-1',
    domainid: 'did-1',
    extid: 'dm-ext-1',
    display_domain: 'example.com',
    base_domain: 'example.com',
    tld: 'com',
    sld: 'example',
    txt_validation_host: '_validate.example.com',
    txt_validation_value: 'validate123',
    created: new Date(1704067200 * 1000),
    updated: new Date(1704067200 * 1000),
    verified: true,
    is_apex: true,
    brand: { ...BRAND_DOMAIN1 },
    vhost: {},
  },
  'domain-2': {
    ...BASE_DOMAIN,
    identifier: 'domain-2',
    domainid: 'did-2',
    extid: 'dm-ext-2',
    display_domain: 'test.com',
    base_domain: 'test.com',
    tld: 'com',
    sld: 'test',
    txt_validation_host: '_validate.test.com',
    txt_validation_value: 'validate456',
    created: new Date(1704153600 * 1000),
    updated: new Date(1704153600 * 1000),
    brand: { ...BRAND_DOMAIN2 },
    vhost: {},
  },
};

export const newDomainDataRaw = {
  ...BASE_DOMAIN,
  identifier: 'domain-3',
  domainid: 'did-3',
  extid: 'dm-ext-3',
  display_domain: 'new-domain.com',
  base_domain: 'new-domain.com',
  tld: 'com',
  sld: 'new-domain',
  txt_validation_host: '_validate.new-domain.com',
  txt_validation_value: 'validate789',
  created: 1704240000,       // 2024-01-03T00:00:00Z
  updated: 1704240000,
  brand: { ...BRAND_DOMAIN2 },
  vhost: {},
};

export const newDomainData: CustomDomain = {
  ...BASE_DOMAIN,
  identifier: 'domain-3',
  domainid: 'did-3',
  extid: 'dm-ext-3',
  display_domain: 'new-domain.com',
  base_domain: 'new-domain.com',
  tld: 'com',
  sld: 'new-domain',
  txt_validation_host: '_validate.new-domain.com',
  txt_validation_value: 'validate789',
  created: new Date(1704240000 * 1000),
  updated: new Date(1704240000 * 1000),
  brand: { ...BRAND_DOMAIN2 },
  vhost: {},
};
