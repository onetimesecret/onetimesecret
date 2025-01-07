// tests/unit/fixtures/domains.fixture.ts
import type { CustomDomain } from '@/schemas/models';

export const mockDomainsOld: Record<string, CustomDomain> = {
  'domain-1': {
    identifier: 'domain-1',
    name: 'example.com',
    status: 'verified',
    createdAt: '2024-01-01T00:00:00Z',
    updatedAt: '2024-01-01T00:00:00Z',
  },
  'domain-2': {
    identifier: 'domain-2',
    name: 'test.com',
    status: 'pending',
    createdAt: '2024-01-02T00:00:00Z',
    updatedAt: '2024-01-02T00:00:00Z',
  },
};

export const newDomainDataOld = {
  name: 'new-domain.com',
  identifier: 'domain-3',
  status: 'pending',
  createdAt: '2024-01-03T00:00:00Z',
  updatedAt: '2024-01-03T00:00:00Z',
} as const;

const BASE_DOMAIN = {
  identifier: '',
  domainid: '',
  custid: 'cust-123',
  _original_value: '',
  subdomain: '',
  trd: '',
  is_apex: false,
  verified: false,
} as const;

export const mockDomains: Record<string, CustomDomain> = {
  'domain-1': {
    ...BASE_DOMAIN,
    identifier: 'domain-1',
    domainid: 'did-1',
    display_domain: 'example.com',
    base_domain: 'example.com',
    tld: 'com',
    sld: 'example',
    _original_value: 'example.com',
    txt_validation_host: '_validate.example.com',
    txt_validation_value: 'validate123',
    created: new Date('2024-01-01T00:00:00Z'),
    updated: new Date('2024-01-01T00:00:00Z'),
    verified: true,
    is_apex: true,
    brand: {
      primary_color: '#ff4400',
      font_family: 'Poppins, sans-serif',
      corner_style: 'sharp',
      button_text_light: false,
    },
  },
  'domain-2': {
    ...BASE_DOMAIN,
    identifier: 'domain-2',
    domainid: 'did-2',
    display_domain: 'test.com',
    base_domain: 'test.com',
    tld: 'com',
    sld: 'test',
    _original_value: 'test.com',
    txt_validation_host: '_validate.test.com',
    txt_validation_value: 'validate456',
    created: new Date('2024-01-02T00:00:00Z'),
    updated: new Date('2024-01-02T00:00:00Z'),
    brand: {
      primary_color: '#007bff',
      font_family: 'Roboto, sans-serif',
      corner_style: 'rounded',
      button_text_light: true,
    },
  },
};

export const newDomainData: CustomDomain = {
  ...BASE_DOMAIN,
  identifier: 'domain-3',
  domainid: 'did-3',
  display_domain: 'new-domain.com',
  base_domain: 'new-domain.com',
  tld: 'com',
  sld: 'new-domain',
  _original_value: 'new-domain.com',
  txt_validation_host: '_validate.new-domain.com',
  txt_validation_value: 'validate789',
  created: new Date('2024-01-03T00:00:00Z'),
  updated: new Date('2024-01-03T00:00:00Z'),
  brand: {
    primary_color: '#007bff',
    font_family: 'Roboto, sans-serif',
    corner_style: 'rounded',
    button_text_light: true,
  },
};
