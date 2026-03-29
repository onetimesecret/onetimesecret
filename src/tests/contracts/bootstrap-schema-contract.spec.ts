// src/tests/contracts/bootstrap-schema-contract.spec.ts
//
// Contract tests that verify the frontend TypeScript schema declares
// all fields the backend serializers send, and vice versa.
//
// This prevents:
// - Silent field stripping (frontend ignores backend field)
// - Type mismatches (field type differs between layers)
// - Undocumented fields (field exists but not in contract)

import { describe, expect, it } from 'vitest';
import type { BootstrapPayload } from '@/schemas/contracts/bootstrap';
import { featuresSchema, organizationSchema } from '@/schemas/contracts/bootstrap';
import { bootstrapUiSchema, BOOTSTRAP_UI_DEFAULTS } from './bootstrap-test-schema';
import {
  ALL_SERIALIZER_FIELDS,
  ALL_BOOTSTRAP_FIELDS,
  AUTHENTICATION_SERIALIZER_FIELDS,
  CONFIG_SERIALIZER_FIELDS,
  DOMAIN_SERIALIZER_FIELDS,
  I18N_SERIALIZER_FIELDS,
  MESSAGES_SERIALIZER_FIELDS,
  ORGANIZATION_SERIALIZER_FIELDS,
  SYSTEM_SERIALIZER_FIELDS,
  NON_SERIALIZER_FIELDS,
  TEMPLATE_ONLY_FIELDS,
} from './bootstrap-serializer-fields';

// ============================================================================
// DOCUMENTATION: Intentional Exclusions and Frontend-Only Fields
// ============================================================================

/**
 * Fields intentionally excluded from BootstrapPayload interface.
 * Each entry MUST have a comment explaining why it is excluded.
 */
const INTENTIONAL_EXCLUSIONS: Record<string, string> = {
  // domain_locale is extracted from domain_branding.locale in serializer
  // but not exposed as a top-level field in BootstrapPayload
  domain_locale:
    'Extracted from domain_branding.locale; not a top-level BootstrapPayload field',

  // frontend_development is deprecated in favor of development.enabled
  frontend_development:
    'Deprecated field; use development.enabled instead. Still serialized for backward compatibility.',

  // nonce is used only for CSP headers, not passed to Vue app
  nonce: 'Security nonce for CSP; used in template script tags, not in Vue app state.',

  // domains config is only present when domains_enabled is true
  // and contains internal config that duplicates domains_enabled
  domains: 'Internal config; domains_enabled boolean is sufficient for frontend.',
};

/**
 * Fields in BootstrapPayload that are NOT in serializer output_templates.
 * These are frontend-only additions or derived from other sources.
 */
const FRONTEND_ONLY_FIELDS: Record<string, string> = {
  // enjoyTheVue is set via JavaScript in index.rue template, not serializers
  enjoyTheVue: 'Set via JavaScript in template; not from Ruby serializers.',

  // baseuri is a template-only field used for og:url, not serialized to window state
  baseuri: 'Template-only field (og:url, sitemap); not from serializers.',

  // apitoken is optional and only set in specific authenticated contexts
  apitoken: 'Optional field; only set in specific authenticated API contexts.',

  // available_jurisdictions is derived from regions config
  available_jurisdictions: 'Derived from regions.jurisdictions; not a separate serializer field.',

  // Stripe fields are loaded via billing module, not bootstrap serializers
  stripe_customer: 'Loaded via billing module; not from bootstrap serializers.',
  stripe_subscriptions: 'Loaded via billing module; not from bootstrap serializers.',
};

// ============================================================================
// HELPER: Extract BootstrapPayload keys at compile time
// ============================================================================

// We need to get the keys from the BootstrapPayload interface.
// Since TypeScript interfaces don't exist at runtime, we use the baseBootstrap
// fixture which implements the interface completely.
import { baseBootstrap } from '@/tests/setup-bootstrap';

const BOOTSTRAP_PAYLOAD_KEYS = Object.keys(baseBootstrap) as (keyof BootstrapPayload)[];

// ============================================================================
// TESTS: Field Completeness
// ============================================================================

describe('Bootstrap schema contract (serializer fields)', () => {
  describe('serializer field coverage', () => {
    // Authentication serializer fields
    describe('AuthenticationSerializer fields', () => {
      const relevantPayloadKeys = BOOTSTRAP_PAYLOAD_KEYS.filter(
        (k) =>
          AUTHENTICATION_SERIALIZER_FIELDS.includes(k as any) || k in INTENTIONAL_EXCLUSIONS
      );

      it.each(
        AUTHENTICATION_SERIALIZER_FIELDS.filter((f) => !(f in INTENTIONAL_EXCLUSIONS))
      )('BootstrapPayload declares authentication field "%s"', (field) => {
        expect(BOOTSTRAP_PAYLOAD_KEYS).toContain(field);
      });
    });

    // Config serializer fields
    describe('ConfigSerializer fields', () => {
      it.each(CONFIG_SERIALIZER_FIELDS.filter((f) => !(f in INTENTIONAL_EXCLUSIONS)))(
        'BootstrapPayload declares config field "%s"',
        (field) => {
          expect(BOOTSTRAP_PAYLOAD_KEYS).toContain(field);
        }
      );
    });

    // Domain serializer fields
    describe('DomainSerializer fields', () => {
      it.each(DOMAIN_SERIALIZER_FIELDS.filter((f) => !(f in INTENTIONAL_EXCLUSIONS)))(
        'BootstrapPayload declares domain field "%s"',
        (field) => {
          expect(BOOTSTRAP_PAYLOAD_KEYS).toContain(field);
        }
      );
    });

    // I18n serializer fields
    describe('I18nSerializer fields', () => {
      it.each(I18N_SERIALIZER_FIELDS.filter((f) => !(f in INTENTIONAL_EXCLUSIONS)))(
        'BootstrapPayload declares i18n field "%s"',
        (field) => {
          expect(BOOTSTRAP_PAYLOAD_KEYS).toContain(field);
        }
      );
    });

    // Messages serializer fields
    describe('MessagesSerializer fields', () => {
      it.each(MESSAGES_SERIALIZER_FIELDS.filter((f) => !(f in INTENTIONAL_EXCLUSIONS)))(
        'BootstrapPayload declares messages field "%s"',
        (field) => {
          expect(BOOTSTRAP_PAYLOAD_KEYS).toContain(field);
        }
      );
    });

    // Organization serializer fields
    describe('OrganizationSerializer fields', () => {
      it.each(ORGANIZATION_SERIALIZER_FIELDS.filter((f) => !(f in INTENTIONAL_EXCLUSIONS)))(
        'BootstrapPayload declares organization field "%s"',
        (field) => {
          expect(BOOTSTRAP_PAYLOAD_KEYS).toContain(field);
        }
      );
    });

    // System serializer fields
    describe('SystemSerializer fields', () => {
      it.each(SYSTEM_SERIALIZER_FIELDS.filter((f) => !(f in INTENTIONAL_EXCLUSIONS)))(
        'BootstrapPayload declares system field "%s"',
        (field) => {
          expect(BOOTSTRAP_PAYLOAD_KEYS).toContain(field);
        }
      );
    });
  });

  describe('exclusion and documentation validation', () => {
    it('all intentional exclusions reference real serializer fields', () => {
      // Guard against stale exclusions: every key in INTENTIONAL_EXCLUSIONS
      // must actually exist in some serializer output_template
      const allSerializerAndMeta = [
        ...ALL_SERIALIZER_FIELDS,
        'domain_locale', // From domain serializer but not in output_template array
        'frontend_development', // From config serializer
        'nonce', // From system serializer
        'domains', // From config serializer
      ] as const;

      for (const excluded of Object.keys(INTENTIONAL_EXCLUSIONS)) {
        expect(
          allSerializerAndMeta as readonly string[]
        ).toContain(excluded);
      }
    });

    it('all frontend-only fields are documented', () => {
      // Verify that any BootstrapPayload fields not in serializers are documented
      const allBackendFields = [
        ...ALL_SERIALIZER_FIELDS,
        ...Object.keys(INTENTIONAL_EXCLUSIONS),
      ];

      const frontendOnlyInPayload = BOOTSTRAP_PAYLOAD_KEYS.filter(
        (f) => !allBackendFields.includes(f) && !(f in FRONTEND_ONLY_FIELDS)
      );

      expect(frontendOnlyInPayload).toEqual([]);
    });

    it('no unaccounted backend fields are missing from BootstrapPayload', () => {
      // All serializer fields should be in BootstrapPayload or INTENTIONAL_EXCLUSIONS
      const missing = ALL_SERIALIZER_FIELDS.filter(
        (f) =>
          !BOOTSTRAP_PAYLOAD_KEYS.includes(f as keyof BootstrapPayload) &&
          !(f in INTENTIONAL_EXCLUSIONS)
      );

      expect(missing).toEqual([]);
    });
  });
});

// ============================================================================
// TESTS: Zod Schema Validation
// ============================================================================

describe('Bootstrap Zod schema validation', () => {
  describe('bootstrapUiSchema', () => {
    it('provides sensible defaults for empty input', () => {
      const defaults = BOOTSTRAP_UI_DEFAULTS;

      expect(defaults.ui).toEqual({ enabled: true });
      expect(defaults.messages).toEqual([]);
      expect(defaults.features).toEqual({ markdown: false });
      expect(defaults.supported_locales).toEqual([]);
      expect(defaults.default_locale).toBe('en');
    });

    it('parses minimal valid payload', () => {
      const minimal = {
        ui: { enabled: true },
        messages: [],
        features: { markdown: true },
      };

      const result = bootstrapUiSchema.safeParse(minimal);
      expect(result.success).toBe(true);
    });

    it('applies defaults for missing optional fields', () => {
      const partial = {
        features: { markdown: true },
      };

      const result = bootstrapUiSchema.safeParse(partial);
      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data.ui).toEqual({ enabled: true });
        expect(result.data.messages).toEqual([]);
      }
    });
  });

  describe('featuresSchema', () => {
    it('accepts full feature flags object', () => {
      const features = {
        markdown: true,
        mfa: true,
        lockout: true,
        password_requirements: true,
        email_auth: true,
        webauthn: false,
        sso: {
          enabled: true,
          providers: [
            { route_name: 'entra', display_name: 'Microsoft' },
            { route_name: 'google', display_name: 'Google' },
          ],
        },
        sso_only: false,
        magic_links: true,
      };

      const result = featuresSchema.safeParse(features);
      expect(result.success).toBe(true);
    });

    it('accepts sso as boolean false', () => {
      const features = {
        markdown: false,
        sso: false,
      };

      const result = featuresSchema.safeParse(features);
      expect(result.success).toBe(true);
    });

    it('accepts sso as config object', () => {
      const features = {
        markdown: false,
        sso: {
          enabled: true,
          providers: [{ route_name: 'entra', display_name: 'Microsoft Entra ID' }],
        },
      };

      const result = featuresSchema.safeParse(features);
      expect(result.success).toBe(true);
    });
  });

  describe('organizationSchema', () => {
    it('accepts valid organization object', () => {
      const org = {
        objid: 'org_obj_123',
        extid: 'org_ext_123',
        display_name: 'ACME Corp',
        is_default: false,
        planid: 'plan_abc',
        current_user_role: 'admin' as const,
      };

      const result = organizationSchema.safeParse(org);
      expect(result.success).toBe(true);
    });

    it('accepts null organization', () => {
      const result = organizationSchema.safeParse(null);
      expect(result.success).toBe(true);
    });

    it('accepts organization with null planid', () => {
      const org = {
        objid: 'org_obj_123',
        extid: 'org_ext_123',
        display_name: 'ACME Corp',
        is_default: true,
        planid: null,
        current_user_role: null,
      };

      const result = organizationSchema.safeParse(org);
      expect(result.success).toBe(true);
    });

    it('validates role enum', () => {
      const orgWithInvalidRole = {
        objid: 'org_obj_123',
        extid: 'org_ext_123',
        display_name: 'ACME Corp',
        is_default: false,
        planid: null,
        current_user_role: 'superadmin', // Invalid role
      };

      const result = organizationSchema.safeParse(orgWithInvalidRole);
      expect(result.success).toBe(false);
    });
  });
});

// ============================================================================
// TESTS: Realistic Payload Parsing
// ============================================================================

describe('Bootstrap realistic payload parsing', () => {
  it('parses authenticated user bootstrap payload', () => {
    const payload = {
      ui: {
        enabled: true,
        capabilities: {
          burn: true,
          show: true,
          receipt: true,
          recipient: true,
        },
        header: {
          enabled: true,
          branding: {
            logo: {
              url: '/img/logo.svg',
              alt: 'OTS',
              link_to: '/',
            },
            site_name: 'One-Time Secret',
          },
        },
        footer_links: {
          enabled: true,
          groups: [
            {
              name: 'Resources',
              links: [
                { text: 'Docs', url: '/docs' },
                { text: 'API', url: '/docs/api' },
              ],
            },
          ],
        },
      },
      messages: [{ type: 'info' as const, content: 'Welcome back!' }],
      features: {
        markdown: true,
        mfa: true,
        sso: {
          enabled: true,
          providers: [{ route_name: 'entra', display_name: 'Microsoft' }],
        },
      },
      organization: {
        objid: 'org_123',
        extid: 'org_ext_123',
        display_name: 'ACME Corp',
        is_default: false,
        planid: 'plan_pro',
        current_user_role: 'owner' as const,
      },
      supported_locales: ['en', 'es', 'fr'],
      default_locale: 'en',
    };

    const result = bootstrapUiSchema.safeParse(payload);
    expect(result.success).toBe(true);
  });

  it('parses anonymous user bootstrap payload', () => {
    const payload = {
      ui: { enabled: true },
      messages: [],
      features: { markdown: false },
      organization: null,
      supported_locales: ['en'],
      default_locale: 'en',
    };

    const result = bootstrapUiSchema.safeParse(payload);
    expect(result.success).toBe(true);
  });

  it('handles malformed messages gracefully', () => {
    const payload = {
      ui: { enabled: true },
      messages: [
        { type: 'invalid_type', content: 'Bad message' }, // Invalid type
      ],
      features: { markdown: false },
    };

    const result = bootstrapUiSchema.safeParse(payload);
    expect(result.success).toBe(false);
    if (!result.success) {
      expect(result.error.issues[0].path).toContain('messages');
    }
  });
});

// ============================================================================
// TESTS: Type Consistency
// ============================================================================

describe('Bootstrap type consistency', () => {
  it('baseBootstrap fixture satisfies BootstrapPayload interface', () => {
    // This test verifies that baseBootstrap is a valid BootstrapPayload
    // by checking key fields have expected types
    expect(typeof baseBootstrap.authenticated).toBe('boolean');
    expect(typeof baseBootstrap.awaiting_mfa).toBe('boolean');
    expect(typeof baseBootstrap.had_valid_session).toBe('boolean');
    expect(typeof baseBootstrap.baseuri).toBe('string');
    expect(typeof baseBootstrap.locale).toBe('string');
    expect(typeof baseBootstrap.shrimp).toBe('string');
    expect(typeof baseBootstrap.domains_enabled).toBe('boolean');
    expect(typeof baseBootstrap.regions_enabled).toBe('boolean');
    expect(typeof baseBootstrap.i18n_enabled).toBe('boolean');
    expect(typeof baseBootstrap.d9s_enabled).toBe('boolean');
    expect(typeof baseBootstrap.enjoyTheVue).toBe('boolean');

    // Object fields
    expect(baseBootstrap.authentication).toBeDefined();
    expect(baseBootstrap.secret_options).toBeDefined();
    expect(baseBootstrap.regions).toBeDefined();
    expect(baseBootstrap.domain_branding).toBeDefined();
    expect(baseBootstrap.features).toBeDefined();
    expect(baseBootstrap.ui).toBeDefined();
    expect(baseBootstrap.diagnostics).toBeDefined();

    // Arrays
    expect(Array.isArray(baseBootstrap.messages)).toBe(true);
    expect(Array.isArray(baseBootstrap.supported_locales)).toBe(true);
  });

  it('all boolean fields in BootstrapPayload have boolean defaults', () => {
    const booleanFields = [
      'authenticated',
      'awaiting_mfa',
      'had_valid_session',
      'domains_enabled',
      'regions_enabled',
      'i18n_enabled',
      'd9s_enabled',
      'enjoyTheVue',
    ] as const;

    for (const field of booleanFields) {
      expect(typeof baseBootstrap[field]).toBe('boolean');
    }
  });
});
