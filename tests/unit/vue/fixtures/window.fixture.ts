// tests/unit/vue/fixtures/window.fixture.ts
import { OnetimeWindow } from '@/types/declarations/window';
import { ValidKeys as UserTypes } from '@/schemas/config/shared/user_types';
// import { vi } from 'vitest';

// const setIntervalMock = vi.fn().mockReturnValue(123);
// const clearIntervalMock = vi.fn();

export const stateFixture: OnetimeWindow = {
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
  plans_enabled: true,
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
  available_plans: {},
  // plan: {
  //   identifier: 'basic',
  //   planid: 'basic',
  //   price: 0,
  //   discount: 0,
  //   options: {
  //     ttl: 604800.0,
  //     size: 100000,
  //     api: false,
  //     name: 'Anonymous',
  //   },
  // },
  user_type: UserTypes.authenticated,
  is_paid: false,
  default_planid: 'anonymous',
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
  incoming_recipient: 'incoming@solutious.com',
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
  i18n_enabled: true,
  d9s_enabled: false,
  diagnostics: {
    sentry: {
      dsn: '', // Default DSN for testing purposes
      enabled: false,
      logErrors: true,
      trackComponents: true,
    },
  },
  features: {
    markdown: true,
  },
  ui: {
    // UiInterface has 'enabled' as mandatory, header and footer_links are optional.
    enabled: true,
  },
} as const;

// Export the window fixture with the new structure
export const windowFixture = {
  onetime: stateFixture,
} as unknown as Window;
