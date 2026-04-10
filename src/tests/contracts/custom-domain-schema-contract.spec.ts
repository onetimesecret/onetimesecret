// src/tests/contracts/custom-domain-schema-contract.spec.ts
//
// Contract snapshot tests that verify the frontend Zod schema declares
// all fields the backend sends. Prevents silent field stripping (issue #2685).

import { customDomainSchema } from '@/schemas/shapes/v3/custom-domain';
import { describe, expect, it } from 'vitest';

import { CUSTOM_DOMAIN_SAFE_DUMP_FIELDS } from './custom-domain-safe-dump-fields';

// Fields intentionally excluded from customDomainSchema.
// Each entry MUST have a comment explaining why it is excluded.
const INTENTIONAL_EXCLUSIONS: Record<string, string> = {
  // identifier duplicates domainid (both are the internal UUID primary key).
  // The frontend uses domainid; identifier is included in safe_dump for
  // Ruby-side consumers that expect the Familia convention.
  identifier: 'Duplicates domainid; frontend uses domainid exclusively.',

  // Mail config status is consumed via the dedicated email-config API endpoints,
  // not from the domain record. The frontend uses domainsStore.getEmailConfig().
  mail_configured: 'Consumed via email-config API, not domain record fields.',
  mail_enabled: 'Consumed via email-config API, not domain record fields.',
};

describe('CustomDomain schema contract (safe_dump_fields)', () => {
  const schemaKeys = Object.keys(customDomainSchema.shape);

  describe('field completeness', () => {
    // For each backend field, verify the Zod schema declares it
    // (or it appears in the explicit exclusion list).
    const backendFields = CUSTOM_DOMAIN_SAFE_DUMP_FIELDS.filter(
      (f) => !(f in INTENTIONAL_EXCLUSIONS)
    );

    it.each(backendFields)(
      'customDomainSchema declares backend field "%s"',
      (field) => {
        expect(schemaKeys).toContain(field);
      }
    );

    it('all intentional exclusions reference real backend fields', () => {
      // Guard against stale exclusions: every key in INTENTIONAL_EXCLUSIONS
      // must actually exist in the backend field list.
      for (const excluded of Object.keys(INTENTIONAL_EXCLUSIONS)) {
        expect(
          CUSTOM_DOMAIN_SAFE_DUMP_FIELDS as readonly string[]
        ).toContain(excluded);
      }
    });

    it('no unaccounted backend fields are missing from the schema', () => {
      const missing = CUSTOM_DOMAIN_SAFE_DUMP_FIELDS.filter(
        (f) => !schemaKeys.includes(f) && !(f in INTENTIONAL_EXCLUSIONS)
      );
      expect(missing).toEqual([]);
    });
  });

  describe('strict parsing (no unknown fields)', () => {
    // Build a realistic custom domain payload containing ALL safe_dump fields.
    // Parsing through customDomainSchema.strict() should succeed, confirming
    // the schema does not reject any fields the backend sends.
    //
    // Fields in INTENTIONAL_EXCLUSIONS are included here because the backend
    // sends them; .strict() only rejects fields NOT in the schema, so we
    // use .passthrough() for this particular test to avoid false negatives
    // from the excluded fields.

    const realisticPayload: Record<string, unknown> = {
      extid: 'cd1a2b3c4d',
      domainid: '01234567-89ab-cdef-0123-456789abcdef',
      display_domain: 'secrets.example.com',
      custid: 'cust:user@example.com',
      base_domain: 'example.com',
      subdomain: 'secrets.example.com',
      trd: 'secrets',
      tld: 'com',
      sld: 'example',
      is_apex: false,
      txt_validation_host: '_onetime-challenge.secrets.example.com',
      txt_validation_value: 'abc123def456ghi789',
      brand: {
        primary_color: '#dc4a22',
        font_family: 'sans',
        corner_style: 'rounded',
        button_text_light: false,
        allow_public_homepage: true,
        allow_public_api: false,
        passphrase_required: false,
        notify_enabled: true,
      },
      status: 'active',
      vhost: {
        id: 12345,
        status: 'active',
        incoming_address: 'secrets.example.com',
        target_address: 'app.onetimesecret.com',
        has_ssl: true,
        is_resolving: true,
        apx_hit: true,
      },
      verified: true,
      created: 1609372800,
      updated: 1609459200,
      sso_configured: true,
      sso_enabled: false,
      homepage_config: {
        domain_id: '01234567-89ab-cdef-0123-456789abcdef',
        enabled: true,
        created_at: 1609372800,
        updated_at: 1609459200,
      },
    };

    it('parses a full backend payload without errors (passthrough mode)', () => {
      // passthrough keeps extra fields (the intentionally excluded ones)
      // so the parse focuses on whether declared fields are correct.
      const result = customDomainSchema.passthrough().safeParse(realisticPayload);
      expect(result.success).toBe(true);
    });

    it('strict parse succeeds for schema-declared fields only', () => {
      // Strip the intentionally excluded fields, then strict-parse.
      // This confirms the schema shape matches exactly what we expect.
      const declaredOnly = { ...realisticPayload };
      for (const key of Object.keys(INTENTIONAL_EXCLUSIONS)) {
        delete declaredOnly[key];
      }
      const result = customDomainSchema.strict().safeParse(declaredOnly);
      if (!result.success) {
        // Surface the Zod issues for easier debugging
        expect(result.error.issues).toEqual([]);
      }
      expect(result.success).toBe(true);
    });
  });
});
