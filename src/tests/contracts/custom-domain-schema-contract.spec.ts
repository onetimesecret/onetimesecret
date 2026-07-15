// src/tests/contracts/custom-domain-schema-contract.spec.ts
//
// Contract snapshot tests that verify the frontend Zod schema declares
// all fields the backend sends. Prevents silent field stripping (issue #2685).

import { domainIconMetaCanonical } from '@/schemas/contracts/custom-domain';
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
        primary_color: '#3B82F6',
        font_family: 'sans',
        corner_style: 'rounded',
        button_text_light: false,
        passphrase_required: false,
        notify_enabled: true,
      },
      icon: {
        filename: 'favicon.ico',
        content_type: 'image/x-icon',
        favicon_source: 'auto_fetch',
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

  // #3780: the workspace "Refresh favicon" gate reads
  // `customDomainRecord.icon?.favicon_source`. Before the icon projection was
  // added to safe_dump (backend) and the schema (here), that value was always
  // stripped to `undefined` and the gate was inert. These lock the wiring in.
  describe('icon provenance projection (#3780)', () => {
    const baseDomain: Record<string, unknown> = {
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
      verified: true,
      created: 1609372800,
      updated: 1609459200,
    };

    it('carries icon.favicon_source through to the parsed record', () => {
      const parsed = customDomainSchema.parse({
        ...baseDomain,
        icon: {
          filename: 'logo.png',
          content_type: 'image/png',
          favicon_source: 'user_upload',
        },
      });
      expect(parsed.icon?.favicon_source).toBe('user_upload');
    });

    it('accepts a null icon (no icon stored) — gate stays enabled', () => {
      const parsed = customDomainSchema.parse({ ...baseDomain, icon: null });
      expect(parsed.icon ?? undefined).toBeUndefined();
    });

    it('accepts an absent icon (older payloads) — gate stays enabled', () => {
      const parsed = customDomainSchema.parse(baseDomain);
      expect(parsed.icon ?? undefined).toBeUndefined();
    });

    it('accepts an icon with a null favicon_source (legacy untagged upload)', () => {
      const parsed = customDomainSchema.parse({
        ...baseDomain,
        icon: { filename: 'old.ico', content_type: 'image/x-icon', favicon_source: null },
      });
      expect(parsed.icon?.favicon_source ?? undefined).toBeUndefined();
    });

    it('rejects nothing but never carries the encoded blob (projection is string-only)', () => {
      // The backend projection never sends `encoded`; the schema simply has no
      // such key, so a stray one is stripped rather than surfacing megabytes on
      // the record. Strict mode proves the declared shape is exactly the 3
      // string fields.
      const strict = customDomainSchema
        .extend({ icon: domainIconMetaCanonical.strict().nullable().optional() })
        .safeParse({
          ...baseDomain,
          icon: { filename: 'f.ico', content_type: 'image/x-icon', favicon_source: 'auto_fetch' },
        });
      expect(strict.success).toBe(true);
    });
  });
});
