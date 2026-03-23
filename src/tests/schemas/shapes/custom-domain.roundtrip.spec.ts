// src/tests/schemas/shapes/custom-domain.roundtrip.spec.ts
//
// Round-trip tests for custom domain schemas (V2 and V3).
// Verifies: canonical -> wire -> parse -> canonical preserves data.
//
// Purpose:
//   - Verify serializer functions match schema expectations
//   - Catch type mismatches between canonical and wire formats
//   - Test domain parsing fields (tld, sld, subdomain, trd)
//   - Test nested object handling (vhost, brand)
//   - Test verification status (verified, is_apex)
//
// Pattern:
//   1. Create canonical custom domain
//   2. Convert to wire format (V2 or V3)
//   3. Parse wire format with schema
//   4. Compare parsed result to original canonical

import { describe, it, expect } from 'vitest';
import { customDomainSchema as v2CustomDomainSchema } from '@/schemas/shapes/v2/custom-domain';
import {
  createCanonicalCustomDomain,
  createVerifiedDomain,
  createPendingDomain,
  createSubdomainDomain,
  createApexDomain,
  createBrandedDomain,
  createComplexTldDomain,
  createMinimalDomain,
  createOldDomain,
  createV2WireCustomDomain,
  createV3WireCustomDomain,
  compareCanonicalCustomDomain,
  type CustomDomainCanonical,
} from './fixtures/custom-domain.fixtures';

// V3 schema import - inline definition for now since V3 shapes may not exist yet
// When V3 custom domain shapes are added, replace with:
// import { customDomainRecord as v3CustomDomainSchema } from '@/schemas/shapes/v3/custom-domain';
import { transforms } from '@/schemas/transforms';
import { z } from 'zod';

// Inline V3 schema for testing (mirrors V3 response schema structure)
const v3BrandSettingsSchema = z
  .object({
    primary_color: z.string().default('#dc4a22'),
    colour: z.string().optional(),
    instructions_pre_reveal: z.string().nullish(),
    instructions_reveal: z.string().nullish(),
    instructions_post_reveal: z.string().nullish(),
    description: z.string().optional(),
    button_text_light: z.boolean().default(false),
    allow_public_homepage: z.boolean().default(false),
    allow_public_api: z.boolean().default(false),
    font_family: z.enum(['sans', 'serif', 'mono']).default('sans'),
    corner_style: z.enum(['rounded', 'pill', 'square']).default('rounded'),
    locale: z.string().default('en'),
    default_ttl: z.number().nullish(),
    passphrase_required: z.boolean().default(false),
    notify_enabled: z.boolean().default(false),
  })
  .partial();

const v3VhostSchema = z
  .object({
    target_address: z.string().optional(),
    target_ports: z.string().optional(),
    target_cname: z.string().optional(),
    apx_hit: z.boolean().optional(),
    has_ssl: z.boolean().optional(),
    is_resolving: z.boolean().optional(),
    status_message: z.string().optional(),
    created_at: transforms.fromNumber.toDate.optional(),
    last_monitored_unix: transforms.fromNumber.toDate.optional(),
    ssl_active_from: transforms.fromNumber.toDateNullish,
    ssl_active_until: transforms.fromNumber.toDateNullish,
  })
  .partial();

const v3CustomDomainSchema = z.object({
  created: transforms.fromNumber.toDate,
  updated: transforms.fromNumber.toDate,
  domainid: z.string(),
  extid: z.string(),
  custid: z.string().nullable(),
  display_domain: z.string(),
  base_domain: z.string(),
  subdomain: z.string().nullable(),
  trd: z.string().nullable(),
  tld: z.string(),
  sld: z.string(),
  is_apex: z.boolean(),
  verified: z.boolean(),
  txt_validation_host: z.string(),
  txt_validation_value: z.string(),
  vhost: v3VhostSchema.nullable(),
  brand: v3BrandSettingsSchema.nullable(),
});

// -----------------------------------------------------------------------------
// V2 Custom Domain Round-Trip Tests
// -----------------------------------------------------------------------------

describe('V2 CustomDomain Round-Trip', () => {
  describe('customDomainSchema', () => {
    it('round-trips a standard custom domain', () => {
      const canonical = createCanonicalCustomDomain();
      const v2Wire = createV2WireCustomDomain(canonical);
      const parsed = v2CustomDomainSchema.parse(v2Wire);

      // Verify identity fields
      expect(parsed.domainid).toBe(canonical.domainid);
      expect(parsed.extid).toBe(canonical.extid);
      expect(parsed.custid).toBe(canonical.custid);

      // Verify domain structure
      expect(parsed.display_domain).toBe(canonical.display_domain);
      expect(parsed.base_domain).toBe(canonical.base_domain);
      expect(parsed.subdomain).toBe(canonical.subdomain);
      expect(parsed.trd).toBe(canonical.trd);
      expect(parsed.tld).toBe(canonical.tld);
      expect(parsed.sld).toBe(canonical.sld);

      // Verify boolean fields
      expect(parsed.is_apex).toBe(canonical.is_apex);
      expect(parsed.verified).toBe(canonical.verified);

      // Verify DNS validation
      expect(parsed.txt_validation_host).toBe(canonical.txt_validation_host);
      expect(parsed.txt_validation_value).toBe(canonical.txt_validation_value);

      // Timestamps (compare as milliseconds)
      expect(parsed.created.getTime()).toBe(canonical.created.getTime());
      expect(parsed.updated.getTime()).toBe(canonical.updated.getTime());
    });

    it('round-trips a verified domain', () => {
      const canonical = createVerifiedDomain();
      const v2Wire = createV2WireCustomDomain(canonical);
      const parsed = v2CustomDomainSchema.parse(v2Wire);

      expect(parsed.verified).toBe(true);
      expect(parsed.vhost).not.toBeNull();
    });

    it('round-trips a pending domain (unverified)', () => {
      const canonical = createPendingDomain();
      const v2Wire = createV2WireCustomDomain(canonical);
      const parsed = v2CustomDomainSchema.parse(v2Wire);

      expect(parsed.verified).toBe(false);
      expect(parsed.vhost).toBeNull();
      expect(parsed.brand).toBeNull();
    });

    it('round-trips a subdomain', () => {
      const canonical = createSubdomainDomain();
      const v2Wire = createV2WireCustomDomain(canonical);
      const parsed = v2CustomDomainSchema.parse(v2Wire);

      expect(parsed.display_domain).toBe('secrets.example.com');
      expect(parsed.base_domain).toBe('example.com');
      expect(parsed.subdomain).toBe('secrets.example.com');
      expect(parsed.trd).toBe('secrets');
      expect(parsed.is_apex).toBe(false);
    });

    it('round-trips an apex domain', () => {
      const canonical = createApexDomain();
      const v2Wire = createV2WireCustomDomain(canonical);
      const parsed = v2CustomDomainSchema.parse(v2Wire);

      expect(parsed.display_domain).toBe('example.com');
      expect(parsed.base_domain).toBe('example.com');
      expect(parsed.subdomain).toBeNull();
      expect(parsed.trd).toBeNull();
      expect(parsed.is_apex).toBe(true);
    });

    it('round-trips a domain with complex TLD (.co.uk)', () => {
      const canonical = createComplexTldDomain();
      const v2Wire = createV2WireCustomDomain(canonical);
      const parsed = v2CustomDomainSchema.parse(v2Wire);

      expect(parsed.tld).toBe('co.uk');
      expect(parsed.sld).toBe('example');
      expect(parsed.base_domain).toBe('example.co.uk');
    });

    it('round-trips a minimal domain (null fields)', () => {
      const canonical = createMinimalDomain();
      const v2Wire = createV2WireCustomDomain(canonical);
      const parsed = v2CustomDomainSchema.parse(v2Wire);

      expect(parsed.custid).toBeNull();
      expect(parsed.subdomain).toBeNull();
      expect(parsed.trd).toBeNull();
      expect(parsed.vhost).toBeNull();
      expect(parsed.brand).toBeNull();
    });

    it('handles different created/updated timestamps', () => {
      const canonical = createOldDomain();
      const v2Wire = createV2WireCustomDomain(canonical);
      const parsed = v2CustomDomainSchema.parse(v2Wire);

      // created should be earlier than updated
      expect(parsed.created.getTime()).toBeLessThan(parsed.updated.getTime());
    });
  });

  describe('nested object handling', () => {
    it('preserves vhost fields', () => {
      const canonical = createVerifiedDomain();
      const v2Wire = createV2WireCustomDomain(canonical);
      const parsed = v2CustomDomainSchema.parse(v2Wire);

      expect(parsed.vhost).not.toBeNull();
      if (parsed.vhost) {
        expect(parsed.vhost.has_ssl).toBe(true);
        expect(parsed.vhost.is_resolving).toBe(true);
      }
    });

    it('preserves brand settings', () => {
      const canonical = createBrandedDomain();
      const v2Wire = createV2WireCustomDomain(canonical);
      const parsed = v2CustomDomainSchema.parse(v2Wire);

      expect(parsed.brand).not.toBeNull();
      if (parsed.brand) {
        expect(parsed.brand.primary_color).toBe('#336699');
        expect(parsed.brand.button_text_light).toBe(true);
        expect(parsed.brand.allow_public_homepage).toBe(true);
        expect(parsed.brand.font_family).toBe('serif');
        expect(parsed.brand.corner_style).toBe('pill');
      }
    });
  });

  describe('edge cases', () => {
    it('handles null custid', () => {
      const canonical = createCanonicalCustomDomain({ custid: null });
      const v2Wire = createV2WireCustomDomain(canonical);
      const parsed = v2CustomDomainSchema.parse(v2Wire);

      expect(parsed.custid).toBeNull();
    });

    it('handles special characters in display_domain', () => {
      // Note: domain names are already validated, but test ASCII representation
      const canonical = createCanonicalCustomDomain({
        display_domain: 'xn--nxasmq5b.example.com', // Punycode
      });
      const v2Wire = createV2WireCustomDomain(canonical);
      const parsed = v2CustomDomainSchema.parse(v2Wire);

      expect(parsed.display_domain).toBe('xn--nxasmq5b.example.com');
    });

    it('handles empty string subdomain as null after parse', () => {
      const canonical = createApexDomain();
      const v2Wire = createV2WireCustomDomain(canonical);
      const parsed = v2CustomDomainSchema.parse(v2Wire);

      // Apex domain has no subdomain
      expect(parsed.subdomain).toBeNull();
      expect(parsed.trd).toBeNull();
    });
  });
});

// -----------------------------------------------------------------------------
// V3 Custom Domain Round-Trip Tests
// -----------------------------------------------------------------------------

describe('V3 CustomDomain Round-Trip', () => {
  describe('v3CustomDomainSchema', () => {
    it('round-trips a standard custom domain', () => {
      const canonical = createCanonicalCustomDomain();
      const v3Wire = createV3WireCustomDomain(canonical);
      const parsed = v3CustomDomainSchema.parse(v3Wire);

      // Verify identity fields
      expect(parsed.domainid).toBe(canonical.domainid);
      expect(parsed.extid).toBe(canonical.extid);

      // Verify domain structure
      expect(parsed.display_domain).toBe(canonical.display_domain);
      expect(parsed.base_domain).toBe(canonical.base_domain);
      expect(parsed.tld).toBe(canonical.tld);
      expect(parsed.sld).toBe(canonical.sld);

      // Verify boolean fields (native in V3)
      expect(parsed.is_apex).toBe(canonical.is_apex);
      expect(parsed.verified).toBe(canonical.verified);

      // Timestamps (compare as milliseconds)
      expect(parsed.created.getTime()).toBe(canonical.created.getTime());
      expect(parsed.updated.getTime()).toBe(canonical.updated.getTime());
    });

    it('round-trips a verified domain', () => {
      const canonical = createVerifiedDomain();
      const v3Wire = createV3WireCustomDomain(canonical);
      const parsed = v3CustomDomainSchema.parse(v3Wire);

      expect(parsed.verified).toBe(true);
    });

    it('round-trips a pending domain', () => {
      const canonical = createPendingDomain();
      const v3Wire = createV3WireCustomDomain(canonical);
      const parsed = v3CustomDomainSchema.parse(v3Wire);

      expect(parsed.verified).toBe(false);
      expect(parsed.vhost).toBeNull();
    });

    it('round-trips a subdomain', () => {
      const canonical = createSubdomainDomain();
      const v3Wire = createV3WireCustomDomain(canonical);
      const parsed = v3CustomDomainSchema.parse(v3Wire);

      expect(parsed.is_apex).toBe(false);
      expect(parsed.trd).toBe('secrets');
    });

    it('round-trips an apex domain', () => {
      const canonical = createApexDomain();
      const v3Wire = createV3WireCustomDomain(canonical);
      const parsed = v3CustomDomainSchema.parse(v3Wire);

      expect(parsed.is_apex).toBe(true);
      expect(parsed.subdomain).toBeNull();
    });
  });

  describe('V3 wire format types', () => {
    it('sends timestamps as numbers', () => {
      const canonical = createCanonicalCustomDomain();
      const v3Wire = createV3WireCustomDomain(canonical);

      expect(typeof v3Wire.created).toBe('number');
      expect(typeof v3Wire.updated).toBe('number');
    });

    it('sends booleans as native booleans', () => {
      const canonical = createVerifiedDomain();
      const v3Wire = createV3WireCustomDomain(canonical);

      expect(typeof v3Wire.verified).toBe('boolean');
      expect(typeof v3Wire.is_apex).toBe('boolean');
      expect(v3Wire.verified).toBe(true);
    });

    it('sends nested object booleans as native', () => {
      const canonical = createBrandedDomain();
      const v3Wire = createV3WireCustomDomain(canonical);

      expect(v3Wire.brand).not.toBeNull();
      if (v3Wire.brand) {
        expect(typeof v3Wire.brand.button_text_light).toBe('boolean');
        expect(typeof v3Wire.brand.allow_public_homepage).toBe('boolean');
      }
    });
  });
});

// -----------------------------------------------------------------------------
// Domain Parsing Field Tests
// -----------------------------------------------------------------------------

describe('Domain Parsing Fields', () => {
  describe('TLD variations', () => {
    it.each([
      ['com', 'example.com', 'example'],
      ['co.uk', 'example.co.uk', 'example'],
      ['org', 'nonprofit.org', 'nonprofit'],
      ['io', 'startup.io', 'startup'],
    ])('handles TLD %s correctly', (tld, baseDomain, sld) => {
      const canonical = createCanonicalCustomDomain({
        tld,
        sld,
        base_domain: baseDomain,
        display_domain: baseDomain,
      });
      const v2Wire = createV2WireCustomDomain(canonical);
      const parsed = v2CustomDomainSchema.parse(v2Wire);

      expect(parsed.tld).toBe(tld);
      expect(parsed.sld).toBe(sld);
      expect(parsed.base_domain).toBe(baseDomain);
    });
  });

  describe('subdomain depth', () => {
    it('handles single-level subdomain', () => {
      const canonical = createCanonicalCustomDomain({
        display_domain: 'www.example.com',
        subdomain: 'www.example.com',
        trd: 'www',
      });
      const v2Wire = createV2WireCustomDomain(canonical);
      const parsed = v2CustomDomainSchema.parse(v2Wire);

      expect(parsed.trd).toBe('www');
    });

    it('handles multi-level subdomain', () => {
      const canonical = createCanonicalCustomDomain({
        display_domain: 'secrets.api.example.com',
        subdomain: 'secrets.api.example.com',
        trd: 'secrets.api',
      });
      const v2Wire = createV2WireCustomDomain(canonical);
      const parsed = v2CustomDomainSchema.parse(v2Wire);

      expect(parsed.trd).toBe('secrets.api');
    });
  });
});

// -----------------------------------------------------------------------------
// Verification Status Tests
// -----------------------------------------------------------------------------

describe('Verification Status', () => {
  it('preserves verified=true', () => {
    const canonical = createVerifiedDomain();
    const v2Wire = createV2WireCustomDomain(canonical);
    const parsed = v2CustomDomainSchema.parse(v2Wire);

    expect(parsed.verified).toBe(true);
  });

  it('preserves verified=false', () => {
    const canonical = createPendingDomain();
    const v2Wire = createV2WireCustomDomain(canonical);
    const parsed = v2CustomDomainSchema.parse(v2Wire);

    expect(parsed.verified).toBe(false);
  });

  it('preserves is_apex=true for apex domains', () => {
    const canonical = createApexDomain();
    const v2Wire = createV2WireCustomDomain(canonical);
    const parsed = v2CustomDomainSchema.parse(v2Wire);

    expect(parsed.is_apex).toBe(true);
  });

  it('preserves is_apex=false for subdomains', () => {
    const canonical = createSubdomainDomain();
    const v2Wire = createV2WireCustomDomain(canonical);
    const parsed = v2CustomDomainSchema.parse(v2Wire);

    expect(parsed.is_apex).toBe(false);
  });
});

// -----------------------------------------------------------------------------
// V2 Transform Behavior
// -----------------------------------------------------------------------------

describe('V2 CustomDomain Transform Behavior', () => {
  describe('boolean transforms', () => {
    // V2 only accepts string-encoded booleans
    it.each([
      ['true', true],
      ['false', false],
      ['1', true],
      ['0', false],
    ])('transforms %p to %p for verified', (input, expected) => {
      const wire = createV2WireCustomDomain(createCanonicalCustomDomain());
      (wire as Record<string, unknown>).verified = input;

      const parsed = v2CustomDomainSchema.parse(wire);

      expect(parsed.verified).toBe(expected);
    });

    it.each([
      ['true', true],
      ['false', false],
    ])('transforms %p to %p for is_apex', (input, expected) => {
      const wire = createV2WireCustomDomain(createCanonicalCustomDomain());
      (wire as Record<string, unknown>).is_apex = input;

      const parsed = v2CustomDomainSchema.parse(wire);

      expect(parsed.is_apex).toBe(expected);
    });
  });

  describe('date transforms', () => {
    it('transforms Unix timestamp string to Date for created', () => {
      const timestamp = Math.floor(Date.now() / 1000);
      const wire = createV2WireCustomDomain(createCanonicalCustomDomain());
      (wire as Record<string, unknown>).created = String(timestamp);

      const parsed = v2CustomDomainSchema.parse(wire);

      expect(parsed.created).toBeInstanceOf(Date);
      expect(parsed.created.getTime()).toBe(timestamp * 1000);
    });
  });
});

// -----------------------------------------------------------------------------
// Comparison Function Tests
// -----------------------------------------------------------------------------

describe('compareCanonicalCustomDomain', () => {
  it('returns equal for identical domains', () => {
    const canonical = createCanonicalCustomDomain();
    const comparison = compareCanonicalCustomDomain(canonical, canonical);

    expect(comparison.equal).toBe(true);
    expect(comparison.differences).toEqual([]);
  });

  it('detects differences in verified status', () => {
    const a = createVerifiedDomain();
    const b = createPendingDomain();
    const comparison = compareCanonicalCustomDomain(a, b);

    expect(comparison.equal).toBe(false);
    expect(comparison.differences.some((d) => d.includes('verified'))).toBe(true);
  });

  it('detects differences in domain structure', () => {
    const a = createApexDomain();
    const b = createSubdomainDomain();
    const comparison = compareCanonicalCustomDomain(a, b);

    expect(comparison.equal).toBe(false);
    expect(comparison.differences.some((d) => d.includes('is_apex'))).toBe(true);
  });
});
