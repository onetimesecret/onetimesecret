// src/services/window-state-validation.spec.ts

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { z } from 'zod/v4';
import { WindowService } from '@/services/window.service';
import { setupWindowState } from '../setupWindow';
import type { OnetimeWindow } from '@/types/declarations/window';

// Create a comprehensive Zod schema for window state validation
const WindowStateSchema = z.object({
  // Core Authentication & User Data
  authenticated: z.boolean(),
  custid: z.string(),
  cust: z.object({
    identifier: z.string(),
    custid: z.string(),
    email: z.string().nullable(),
    role: z.string(),
    verified: z.boolean().nullable(),
    last_login: z.string().nullable(),
    locale: z.string(),
    updated: z.string().nullable(),
    created: z.string().nullable(),
    stripe_customer_id: z.string().nullable(),
    stripe_subscription_id: z.string().nullable(),
    stripe_checkout_email: z.string().nullable(),
    plan: z.object({
      planid: z.string().nullable(),
      source: z.string()
    }),
    secrets_created: z.string(),
    secrets_burned: z.string(),
    secrets_shared: z.string(),
    emails_sent: z.string(),
    active: z.boolean()
  }).nullable(),
  email: z.string(),
  customer_since: z.string().optional(),
  domains_enabled: z.boolean(),
  plans_enabled: z.boolean(),
  regions_enabled: z.boolean(),
  i18n_enabled: z.boolean(),

  // Configuration Sections
  authentication: z.object({
    enabled: z.boolean(),
    signin: z.boolean(),
    signup: z.boolean(),
    autoverify: z.boolean()
  }),

  secret_options: z.object({
    default_ttl: z.number(),
    ttl_options: z.array(z.number())
  }),

  regions: z.object({
    enabled: z.boolean(),
    current_jurisdiction: z.string(),
    identifier: z.string().optional(),
    jurisdictions: z.array(z.object({
      enabled: z.boolean(),
      identifier: z.string(),
      display_name: z.string(),
      domain: z.string(),
      icon: z.object({
        collection: z.string(),
        name: z.string()
      })
    })).optional()
  }),

  ui: z.object({
    enabled: z.boolean(),
    header: z.object({
      enabled: z.boolean(),
      branding: z.object({
        logo: z.object({
          url: z.string(),
          alt: z.string(),
          href: z.string()
        }),
        site_name: z.string().optional()
      }).optional(),
      navigation: z.object({
        enabled: z.boolean()
      }).optional()
    }).optional(),
    footer_links: z.object({
      enabled: z.boolean(),
      groups: z.array(z.object({
        name: z.string().optional(),
        i18n_key: z.string().optional(),
        links: z.array(z.object({
          text: z.string().optional(),
          i18n_key: z.string().optional(),
          url: z.string(),
          external: z.boolean().optional(),
          icon: z.string().optional()
        }))
      }))
    }).optional()
  }),

  diagnostics: z.object({
    sentry: z.object({
      dsn: z.string(),
      enabled: z.boolean().optional(),
      sampleRate: z.number().nullable().optional(),
      maxBreadcrumbs: z.number().nullable().optional(),
      logErrors: z.boolean(),
      trackComponents: z.boolean()
    })
  }),

  // Feature Flags
  d9s_enabled: z.boolean(),
  frontend_development: z.boolean().optional(),

  // System Information
  ot_version: z.string(),
  ot_version_long: z.string(),
  ruby_version: z.string(),
  shrimp: z.string(),
  nonce: z.string().optional(),

  // Host Information
  site_host: z.string(),
  frontend_host: z.string(),
  baseuri: z.string(),
  incoming_recipient: z.string(),

  // Domain & Branding
  canonical_domain: z.string(),
  display_domain: z.string(),
  domain_strategy: z.enum(['canonical', 'subdomain', 'custom', 'invalid']),
  domain_id: z.string(),
  domain_branding: z.object({
    allow_public_homepage: z.boolean(),
    button_text_light: z.boolean(),
    corner_style: z.string(),
    font_family: z.string(),
    instructions_post_reveal: z.string(),
    instructions_pre_reveal: z.string(),
    instructions_reveal: z.string(),
    primary_color: z.string()
  }),
  domain_logo: z.object({
    content_type: z.string(),
    encoded: z.string(),
    filename: z.string()
  }),
  custom_domains: z.array(z.string()).optional(),

  // Internationalization
  locale: z.string(),
  default_locale: z.string(),
  supported_locales: z.array(z.string()),
  fallback_locale: z.union([
    z.string(),
    z.array(z.string()),
    z.record(z.string(), z.array(z.string()))
  ]),

  // Business Logic
  is_paid: z.boolean(),
  user_type: z.string(),

  // UI State
  messages: z.array(z.object({
    type: z.enum(['success', 'error', 'info']),
    content: z.string()
  })),
  global_banner: z.string().optional(),

  // Required fields from interface
  enjoyTheVue: z.boolean(),
  features: z.object({
    markdown: z.boolean()
  }),
  available_jurisdictions: z.array(z.string()),

  // Optional fields from interface
  apitoken: z.string().optional(),
  stripe_customer: z.any().optional(),
  stripe_subscriptions: z.array(z.any()).optional()
});

type WindowState = z.infer<typeof WindowStateSchema>;

describe('Window State Zod Validation', () => {
  let originalWindow: typeof window;

  beforeEach(() => {
    originalWindow = window;
  });

  afterEach(() => {
    window = originalWindow;
  });

  describe('Schema validation with real data', () => {
    beforeEach(() => {
      // Set up a comprehensive mock that should pass validation
      setupWindowState({
        // Core Authentication & User Data
        authenticated: false,
        custid: 'anon',
        cust: {
          identifier: 'anon',
          custid: 'anon',
          email: null,
          role: 'customer',
          verified: null,
          last_login: null,
          locale: '',
          updated: null,
          created: null,
          stripe_customer_id: null,
          stripe_subscription_id: null,
          stripe_checkout_email: null,
          plan: {
            planid: null,
            source: 'parts_unknown'
          },
          secrets_created: '0',
          secrets_burned: '0',
          secrets_shared: '0',
          emails_sent: '0',
          active: false
        },
        email: '',

        // Configuration Sections
        authentication: {
          enabled: true,
          signin: true,
          signup: true,
          autoverify: false
        },

        secret_options: {
          default_ttl: 604800.0,
          ttl_options: [60, 300, 1800, 3600, 14400, 43200, 86400, 259200, 604800, 1209600, 2592000]
        },

        regions: {
          enabled: true,
          current_jurisdiction: 'EU',
          identifier: 'EU',
          jurisdictions: [
            {
              enabled: true,
              identifier: 'EU',
              display_name: 'European Union',
              domain: 'eu.onetimesecret.com',
              icon: {
                collection: 'fa6-solid',
                name: 'earth-europe'
              }
            }
          ]
        },

        ui: {
          enabled: true,
          header: {
            enabled: true,
            branding: {
              logo: {
                url: 'DefaultLogo',
                alt: 'Share a Secret One-Time',
                href: '/'
              },
              site_name: 'One-Time Secret'
            },
            navigation: {
              enabled: true
            }
          },
          footer_links: {
            enabled: false,
            groups: []
          }
        },

        diagnostics: {
          sentry: {
            dsn: 'https://example@sentry.io/123',
            enabled: false,
            logErrors: true,
            trackComponents: true
          }
        },

        // Feature Flags
        d9s_enabled: true,
        domains_enabled: true,
        regions_enabled: true,
        plans_enabled: true,
        i18n_enabled: true,
        frontend_development: true,

        // System Information
        ot_version: '0.22.3',
        ot_version_long: '0.22.3 (e16fe4ac)',
        ruby_version: 'ruby-341',
        shrimp: 'test-csrf-token',
        nonce: 'test-nonce-123',

        // Host Information
        site_host: 'dev.onetime.dev',
        frontend_host: 'http://localhost:5173',
        baseuri: 'https://dev.onetimesecret.com',
        incoming_recipient: '',

        // Domain & Branding
        canonical_domain: 'dev.onetime.dev',
        display_domain: 'dev.onetime.dev',
        domain_strategy: 'canonical' as const,
        domain_id: '',
        domain_branding: {
          allow_public_homepage: false,
          button_text_light: true,
          corner_style: 'rounded',
          font_family: 'sans',
          instructions_post_reveal: '',
          instructions_pre_reveal: '',
          instructions_reveal: '',
          primary_color: '#36454F'
        },
        domain_logo: {
          content_type: 'image/png',
          encoded: '',
          filename: ''
        },
        custom_domains: [],

        // Internationalization
        locale: 'en',
        default_locale: 'en',
        supported_locales: ['bg', 'da_DK', 'de', 'de_AT', 'el_GR', 'en', 'es', 'fr_CA', 'fr_FR', 'it_IT', 'ja', 'ko', 'mi_NZ', 'nl', 'tr', 'uk', 'pl', 'pt_BR', 'sv_SE'],
        fallback_locale: {
          'fr-CA': ['fr_CA', 'fr_FR', 'en'],
          'fr': ['fr_FR', 'fr_CA', 'en'],
          'de-AT': ['de_AT', 'de', 'en'],
          'de': ['de', 'de_AT', 'en'],
          'it': ['it_IT', 'en'],
          'pt': ['pt_BR', 'en'],
          'default': ['en']
        },

        // Business Logic
        is_paid: false,

        // UI State
        messages: [],

        // Required fields
        enjoyTheVue: true,
        features: {
          markdown: true
        },
        available_jurisdictions: ['EU', 'US'],

        user_type: 'authenticated'
      } as OnetimeWindow);
    });

    it('validates complete window state structure', () => {
      const state = WindowService.getState();

      expect(() => {
        WindowStateSchema.parse(state);
      }).not.toThrow();
    });

    it('validates individual sections separately', () => {
      const state = WindowService.getState();

      // Test individual sections
      expect(() => {
        z.object({ authentication: WindowStateSchema.shape.authentication }).parse({
          authentication: state.authentication
        });
      }).not.toThrow();

      expect(() => {
        z.object({ secret_options: WindowStateSchema.shape.secret_options }).parse({
          secret_options: state.secret_options
        });
      }).not.toThrow();

      expect(() => {
        z.object({ regions: WindowStateSchema.shape.regions }).parse({
          regions: state.regions
        });
      }).not.toThrow();

      expect(() => {
        z.object({ ui: WindowStateSchema.shape.ui }).parse({
          ui: state.ui
        });
      }).not.toThrow();
    });

    it('provides detailed validation errors for invalid data', () => {
      // Set up invalid data
      setupWindowState({
        authenticated: 'not-a-boolean' as any,
        ot_version: null as any,
        secret_options: {
          default_ttl: 'not-a-number' as any,
          ttl_options: 'not-an-array' as any
        }
      } as any);

      const state = WindowService.getState();

      expect(() => {
        WindowStateSchema.parse(state);
      }).toThrow();

      // Test that we get specific error information
      try {
        WindowStateSchema.parse(state);
      } catch (error) {
        expect(error).toBeInstanceOf(z.ZodError);
        const zodError = error as z.ZodError;
        expect(zodError.issues.length).toBeGreaterThan(0);
        expect(zodError.issues.some(issue => issue.path.includes('authenticated'))).toBe(true);
      }
    });
  });

  describe('Runtime type checking integration', () => {
    it('can be used to validate WindowService responses', () => {
      setupWindowState({
        authenticated: false,
        ot_version: '0.22.3',
        locale: 'en',
        secret_options: {
          default_ttl: 604800.0,
          ttl_options: [60, 3600, 86400]
        }
      } as any);

      // This demonstrates how you could use Zod for runtime validation
      const validateWindowProperty = <K extends keyof WindowState>(
        key: K,
        value: unknown
      ): value is WindowState[K] => {
        const propertySchema = WindowStateSchema.shape[key];
        return propertySchema.safeParse(value).success;
      };

      expect(validateWindowProperty('authenticated', WindowService.get('authenticated'))).toBe(true);
      expect(validateWindowProperty('ot_version', WindowService.get('ot_version'))).toBe(true);
      expect(validateWindowProperty('locale', WindowService.get('locale'))).toBe(true);

      // This should fail
      expect(validateWindowProperty('authenticated', 'not-a-boolean')).toBe(false);
    });

    it('validates partial window state updates', () => {
      const partialUpdateSchema = WindowStateSchema.partial();

      const partialUpdate = {
        authenticated: true,
        locale: 'fr',
        shrimp: 'new-csrf-token'
      };

      expect(() => {
        partialUpdateSchema.parse(partialUpdate);
      }).not.toThrow();
    });
  });

  describe('Schema compatibility with TypeScript interface', () => {
    it('covers all required fields from OnetimeWindow interface', () => {
      // This test ensures our Zod schema stays in sync with the TypeScript interface
      const requiredFields = [
        'authenticated', 'custid', 'cust', 'email',
        'authentication', 'secret_options', 'regions', 'ui',
        'ot_version', 'ot_version_long', 'ruby_version', 'shrimp',
        'site_host', 'frontend_host',
        'canonical_domain', 'display_domain', 'domain_strategy',
        'locale', 'default_locale', 'supported_locales', 'fallback_locale',
        'is_paid', 'messages'
      ];

      const schemaKeys = Object.keys(WindowStateSchema.shape);

      requiredFields.forEach(field => {
        expect(schemaKeys).toContain(field);
      });
    });

    it('handles optional fields correctly', () => {
      const optionalFields = [
        'apitoken', 'customer_since', 'custom_domains', 'global_banner',
        'stripe_customer', 'stripe_subscriptions'
      ];

      optionalFields.forEach(field => {
        if (field in WindowStateSchema.shape) {
          const fieldSchema = WindowStateSchema.shape[field as keyof typeof WindowStateSchema.shape];
          // Check if the field is optional by testing with undefined
          expect(fieldSchema.safeParse(undefined).success).toBe(true);
        }
      });
    });
  });

  describe('Edge cases and error scenarios', () => {
    it('handles missing required fields', () => {
      // Set minimal state directly without fixture to test validation failure
      (window as any).onetime = {
        authenticated: false
        // Missing many required fields that should cause validation to fail
      };

      const state = WindowService.getState();
      const result = WindowStateSchema.safeParse(state);

      expect(result.success).toBe(false);
      if (!result.success) {
        expect(result.error.issues.length).toBeGreaterThan(0);
      }
    });

    it('validates nested object requirements', () => {
      setupWindowState({
        authentication: {
          enabled: true
          // Missing required fields: signin, signup, autoverify
        }
      } as any);

      const state = WindowService.getState();
      const result = WindowStateSchema.safeParse(state);

      expect(result.success).toBe(false);
    });

    it('validates array contents', () => {
      setupWindowState({
        secret_options: {
          default_ttl: 604800,
          ttl_options: [60, 'invalid', 86400] // Contains invalid string
        }
      } as any);

      const state = WindowService.getState();
      const result = WindowStateSchema.safeParse(state);

      expect(result.success).toBe(false);
    });
  });
});
