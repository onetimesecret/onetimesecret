// src/tests/fixtures/window.fixture.ts
import { OnetimeWindow } from '@/types/declarations/window';
import { vi } from 'vitest';

const setIntervalMock = vi.fn().mockReturnValue(123);
const clearIntervalMock = vi.fn();

export const stateFixture: OnetimeWindow = {
  setInterval: setIntervalMock,
  clearInterval: clearIntervalMock,

  authenticated: false,
  baseuri: 'https://dev.onetimesecret.com',
  cust: null,
  custid: '',
  domains_enabled: false,
  email: 'test@example.com',
  frontend_host: 'https://dev.onetimesecret.com',

  fallback_locale: 'en',
  default_locale: 'en',
  locale: 'en',
  supported_locales: ['en', 'es', 'fr'],

  ot_version: '0.20.0',
  ot_version_long: '0.20.0 (abcd)',
  billing_enabled: true,
  regions_enabled: true,
  ruby_version: 'ruby-335',
  shrimp: 'test-shrimp-token',
  site_host: 'dev.onetimesecret.com',
  stripe_customer: undefined,
  stripe_subscriptions: undefined,
  authentication: {
    enabled: true,
    signup: true,
    signin: true,
    autoverify: false,
  },
  secret_options: {
    default_ttl: 604800.0,
    ttl_options: [60, 3600, 86400, 604800, 1209600, 2592000],
  },
  regions: {
    identifier: 'EU',
    enabled: true,
    current_jurisdiction: 'EU',
    jurisdictions: [
      {
        enabled: true,
        identifier: 'EU',
        display_name: 'European Union',
        domain: 'eu.onetimesecret.com',
        icon: {
          collection: 'fa6-solid',
          name: 'earth-europe',
        },
      },
      {
        enabled: true,
        identifier: 'US',
        display_name: 'United States',
        domain: 'us.onetimesecret.com',
        icon: {
          collection: 'fa6-solid',
          name: 'earth-americas',
        },
      },
    ],
  },
  available_jurisdictions: ['EU', 'US'],
  enjoyTheVue: true,
  canonical_domain: 'dev.onetimesecret.com',
  domain_strategy: 'canonical',
  domain_id: '',
  display_domain: 'dev.onetimesecret.com',
  domain_branding: {
    allow_public_homepage: false,
    button_text_light: true,
    corner_style: 'rounded',
    font_family: 'sans',
    instructions_post_reveal: '',
    instructions_pre_reveal: '',
    instructions_reveal: '',
    primary_color: '#36454F',
  },
  domain_logo: {
    content_type: 'image/png',
    encoded: '',
    filename: '',
  },
  messages: [],
} as const;

// Export the window fixture with the new structure
export const windowFixture = {
  __ONETIME_STATE__: stateFixture,
} as OnetimeWindow & typeof globalThis;
