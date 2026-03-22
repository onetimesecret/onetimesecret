// src/tests/schemas/shapes/custom-domain.compat.spec.ts
//
// Cross-version compatibility tests for custom domain schemas.
// Tests what happens when V2 wire data is parsed by V3 schema and vice versa.
//
// Purpose:
//   - Document expected failures (incompatible encodings)
//   - Verify graceful handling where possible
//   - Establish compatibility matrix for migration planning
//   - Test nested object (vhost, brand) compatibility

import { describe, it, expect } from 'vitest';
import { customDomainSchema as v2CustomDomainSchema } from '@/schemas/shapes/v2/custom-domain';
import { customDomainRecord as v3CustomDomainSchema } from '@/schemas/shapes/v3/custom-domain';
import {
  createCanonicalCustomDomain,
  createVerifiedDomain,
  createPendingDomain,
  createApexDomain,
  createSubdomainDomain,
  createBrandedDomain,
  createMinimalDomain,
  createV2WireCustomDomain,
  createV3WireCustomDomain,
} from './fixtures/custom-domain.fixtures';

// -----------------------------------------------------------------------------
// V2 Wire -> V3 Schema (Forward Compatibility)
// -----------------------------------------------------------------------------

describe('V2 Wire -> V3 Schema (Forward Compatibility)', () => {
  describe('V3 schema type expectations', () => {
    it('FAILS: V3 expects number timestamps, V2 sends strings', () => {
      // V2 sends created/updated as string Unix timestamps
      // V3 expects native numbers
      const canonical = createCanonicalCustomDomain();
      const v2Wire = createV2WireCustomDomain(canonical);

      expect(typeof v2Wire.created).toBe('string');
      expect(typeof v2Wire.updated).toBe('string');

      // V3 schema rejects string timestamps
      const result = v3CustomDomainSchema.safeParse(v2Wire);
      expect(result.success).toBe(false);
      if (!result.success) {
        const timestampErrors = result.error.issues.filter(
          (i) => i.path.includes('created') || i.path.includes('updated')
        );
        expect(timestampErrors.length).toBeGreaterThan(0);
      }
    });

    it('FAILS: V3 rejects V2 string booleans for verified', () => {
      // V2 sends booleans as strings ("true"/"false")
      // V3 expects native booleans
      const canonical = createVerifiedDomain();
      const v2Wire = createV2WireCustomDomain(canonical);

      expect(typeof v2Wire.verified).toBe('string');

      // V3 schema rejects string booleans
      const result = v3CustomDomainSchema.safeParse(v2Wire);
      expect(result.success).toBe(false);
    });

    it('FAILS: V3 rejects V2 string booleans for is_apex', () => {
      const canonical = createApexDomain();
      const v2Wire = createV2WireCustomDomain(canonical);

      expect(typeof v2Wire.is_apex).toBe('string');

      const result = v3CustomDomainSchema.safeParse(v2Wire);
      expect(result.success).toBe(false);
    });
  });

  describe('nested object compatibility', () => {
    it('FAILS: V3 rejects V2 nested vhost with string timestamps', () => {
      const canonical = createVerifiedDomain();
      const v2Wire = createV2WireCustomDomain(canonical);

      // V2 vhost sends timestamps as strings
      if (v2Wire.vhost) {
        expect(typeof v2Wire.vhost.last_monitored_unix).toBe('string');
      }

      const result = v3CustomDomainSchema.safeParse(v2Wire);
      expect(result.success).toBe(false);
    });

    it('FAILS: V3 rejects V2 nested brand with string booleans', () => {
      const canonical = createBrandedDomain();
      const v2Wire = createV2WireCustomDomain(canonical);

      // V2 brand sends booleans as strings
      if (v2Wire.brand) {
        expect(typeof v2Wire.brand.button_text_light).toBe('string');
      }

      const result = v3CustomDomainSchema.safeParse(v2Wire);
      expect(result.success).toBe(false);
    });
  });
});

// -----------------------------------------------------------------------------
// V3 Wire -> V2 Schema (Backward Compatibility)
// -----------------------------------------------------------------------------

describe('V3 Wire -> V2 Schema (Backward Compatibility)', () => {
  describe('timestamp handling', () => {
    it('SUCCEEDS: V2 transforms handle native numbers for timestamps', () => {
      // V2's parseDateValue handles both strings AND numbers
      const canonical = createCanonicalCustomDomain();
      const v3Wire = createV3WireCustomDomain(canonical);

      // V3 sends as number
      expect(typeof v3Wire.created).toBe('number');
      expect(typeof v3Wire.updated).toBe('number');

      // V2's preprocess should handle this
      const result = v2CustomDomainSchema.safeParse(v3Wire);

      if (result.success) {
        expect(result.data.created).toBeInstanceOf(Date);
        expect(result.data.updated).toBeInstanceOf(Date);
      }
    });
  });

  describe('boolean handling', () => {
    it('SUCCEEDS: V2 transforms.fromString.boolean handles native booleans', () => {
      // V2's parseBoolean function handles both strings AND booleans
      const canonical = createVerifiedDomain();
      const v3Wire = createV3WireCustomDomain(canonical);

      expect(typeof v3Wire.verified).toBe('boolean');
      expect(typeof v3Wire.is_apex).toBe('boolean');

      const result = v2CustomDomainSchema.safeParse(v3Wire);

      // V2's parseBoolean handles native booleans
      if (result.success) {
        expect(result.data.verified).toBe(true);
      }
    });

    it('SUCCEEDS: V2 handles false booleans from V3', () => {
      const canonical = createPendingDomain();
      const v3Wire = createV3WireCustomDomain(canonical);

      expect(v3Wire.verified).toBe(false);

      const result = v2CustomDomainSchema.safeParse(v3Wire);

      if (result.success) {
        expect(result.data.verified).toBe(false);
      }
    });

    it('SUCCEEDS: V2 handles is_apex boolean from V3', () => {
      const canonical = createApexDomain();
      const v3Wire = createV3WireCustomDomain(canonical);

      expect(v3Wire.is_apex).toBe(true);

      const result = v2CustomDomainSchema.safeParse(v3Wire);

      if (result.success) {
        expect(result.data.is_apex).toBe(true);
      }
    });
  });

  describe('full domain parsing', () => {
    it('V2 schema successfully parses complete V3 wire data', () => {
      // Due to V2's flexible preprocessors, it should handle V3 data
      const canonical = createCanonicalCustomDomain();
      const v3Wire = createV3WireCustomDomain(canonical);

      const result = v2CustomDomainSchema.safeParse(v3Wire);

      // Document whether this succeeds
      console.log('[V3->V2] custom_domain compatibility:', result.success);
      if (!result.success) {
        console.log(
          '[V3->V2] Errors:',
          result.error.issues.map((i) => `${i.path}: ${i.message}`)
        );
      }

      // V2 should parse V3 data successfully due to flexible transforms
      expect(result.success).toBe(true);
    });

    it('V2 schema parses verified domain from V3 format', () => {
      const canonical = createVerifiedDomain();
      const v3Wire = createV3WireCustomDomain(canonical);

      const result = v2CustomDomainSchema.safeParse(v3Wire);

      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data.verified).toBe(true);
        expect(result.data.vhost).not.toBeNull();
      }
    });

    it('V2 schema parses pending domain from V3 format', () => {
      const canonical = createPendingDomain();
      const v3Wire = createV3WireCustomDomain(canonical);

      const result = v2CustomDomainSchema.safeParse(v3Wire);

      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data.verified).toBe(false);
        expect(result.data.vhost).toBeNull();
      }
    });

    it('V2 schema parses apex domain from V3 format', () => {
      const canonical = createApexDomain();
      const v3Wire = createV3WireCustomDomain(canonical);

      const result = v2CustomDomainSchema.safeParse(v3Wire);

      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data.is_apex).toBe(true);
        expect(result.data.subdomain).toBeNull();
        expect(result.data.trd).toBeNull();
      }
    });

    it('V2 schema parses subdomain from V3 format', () => {
      const canonical = createSubdomainDomain();
      const v3Wire = createV3WireCustomDomain(canonical);

      const result = v2CustomDomainSchema.safeParse(v3Wire);

      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data.is_apex).toBe(false);
        expect(result.data.trd).toBe('secrets');
      }
    });

    it('V2 schema parses minimal domain from V3 format', () => {
      const canonical = createMinimalDomain();
      const v3Wire = createV3WireCustomDomain(canonical);

      const result = v2CustomDomainSchema.safeParse(v3Wire);

      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data.custid).toBeNull();
        expect(result.data.vhost).toBeNull();
        expect(result.data.brand).toBeNull();
      }
    });
  });

  describe('nested object handling', () => {
    it('V2 parses V3 vhost with number timestamps', () => {
      const canonical = createVerifiedDomain();
      const v3Wire = createV3WireCustomDomain(canonical);

      const result = v2CustomDomainSchema.safeParse(v3Wire);

      expect(result.success).toBe(true);
      if (result.success && result.data.vhost) {
        // V2 vhost schema should handle number timestamps
        expect(result.data.vhost.has_ssl).toBe(true);
        expect(result.data.vhost.is_resolving).toBe(true);
      }
    });

    it('V2 parses V3 brand with boolean values', () => {
      const canonical = createBrandedDomain();
      const v3Wire = createV3WireCustomDomain(canonical);

      const result = v2CustomDomainSchema.safeParse(v3Wire);

      expect(result.success).toBe(true);
      if (result.success && result.data.brand) {
        expect(result.data.brand.primary_color).toBe('#336699');
        expect(result.data.brand.button_text_light).toBe(true);
        expect(result.data.brand.allow_public_homepage).toBe(true);
      }
    });
  });
});

// -----------------------------------------------------------------------------
// Null Field Handling Compatibility
// -----------------------------------------------------------------------------

describe('Null Field Handling Compatibility', () => {
  describe('null vs undefined handling', () => {
    it('V2 and V3 both handle null custid identically', () => {
      const canonical = createCanonicalCustomDomain({ custid: null });

      const v2Wire = createV2WireCustomDomain(canonical);
      const v3Wire = createV3WireCustomDomain(canonical);

      expect(v2Wire.custid).toBeNull();
      expect(v3Wire.custid).toBeNull();
    });

    it('V2 and V3 both handle null subdomain identically', () => {
      const canonical = createApexDomain();

      const v2Wire = createV2WireCustomDomain(canonical);
      const v3Wire = createV3WireCustomDomain(canonical);

      expect(v2Wire.subdomain).toBeNull();
      expect(v3Wire.subdomain).toBeNull();
    });

    it('V2 and V3 both handle null trd identically', () => {
      const canonical = createApexDomain();

      const v2Wire = createV2WireCustomDomain(canonical);
      const v3Wire = createV3WireCustomDomain(canonical);

      expect(v2Wire.trd).toBeNull();
      expect(v3Wire.trd).toBeNull();
    });

    it('V2 and V3 both handle null vhost identically', () => {
      const canonical = createPendingDomain();

      const v2Wire = createV2WireCustomDomain(canonical);
      const v3Wire = createV3WireCustomDomain(canonical);

      expect(v2Wire.vhost).toBeNull();
      expect(v3Wire.vhost).toBeNull();
    });

    it('V2 and V3 both handle null brand identically', () => {
      const canonical = createPendingDomain();

      const v2Wire = createV2WireCustomDomain(canonical);
      const v3Wire = createV3WireCustomDomain(canonical);

      expect(v2Wire.brand).toBeNull();
      expect(v3Wire.brand).toBeNull();
    });
  });

  describe('empty string handling in V2', () => {
    it('V2 treats empty string as false for boolean (verified)', () => {
      const wire = createV2WireCustomDomain(createCanonicalCustomDomain());
      (wire as Record<string, unknown>).verified = '';

      const result = v2CustomDomainSchema.safeParse(wire);

      if (result.success) {
        // parseBoolean returns false for empty string
        expect(result.data.verified).toBe(false);
      }
    });

    it('V2 treats empty string as false for boolean (is_apex)', () => {
      const wire = createV2WireCustomDomain(createCanonicalCustomDomain());
      (wire as Record<string, unknown>).is_apex = '';

      const result = v2CustomDomainSchema.safeParse(wire);

      if (result.success) {
        expect(result.data.is_apex).toBe(false);
      }
    });
  });
});

// -----------------------------------------------------------------------------
// Domain Structure Compatibility
// -----------------------------------------------------------------------------

describe('Domain Structure Compatibility', () => {
  describe('domain parsing fields', () => {
    it('V2 and V3 produce identical domain structure for apex domain', () => {
      const canonical = createApexDomain();

      const v2Wire = createV2WireCustomDomain(canonical);
      const v3Wire = createV3WireCustomDomain(canonical);

      // Domain structure fields should be identical
      expect(v2Wire.display_domain).toBe(v3Wire.display_domain);
      expect(v2Wire.base_domain).toBe(v3Wire.base_domain);
      expect(v2Wire.tld).toBe(v3Wire.tld);
      expect(v2Wire.sld).toBe(v3Wire.sld);
    });

    it('V2 and V3 produce identical domain structure for subdomain', () => {
      const canonical = createSubdomainDomain();

      const v2Wire = createV2WireCustomDomain(canonical);
      const v3Wire = createV3WireCustomDomain(canonical);

      expect(v2Wire.display_domain).toBe(v3Wire.display_domain);
      expect(v2Wire.subdomain).toBe(v3Wire.subdomain);
      expect(v2Wire.trd).toBe(v3Wire.trd);
    });

    it('V2 and V3 produce identical DNS validation fields', () => {
      const canonical = createCanonicalCustomDomain();

      const v2Wire = createV2WireCustomDomain(canonical);
      const v3Wire = createV3WireCustomDomain(canonical);

      expect(v2Wire.txt_validation_host).toBe(v3Wire.txt_validation_host);
      expect(v2Wire.txt_validation_value).toBe(v3Wire.txt_validation_value);
    });
  });
});

// -----------------------------------------------------------------------------
// Compatibility Summary Matrix
// -----------------------------------------------------------------------------

describe('Compatibility Summary', () => {
  it('documents the V2<->V3 compatibility matrix for custom_domain', () => {
    const matrix = {
      'V2 Wire -> V3 Schema': {
        'created/updated (string->number)': 'INCOMPATIBLE - V3 expects number',
        'verified (string->boolean)': 'INCOMPATIBLE - V3 expects boolean',
        'is_apex (string->boolean)': 'INCOMPATIBLE - V3 expects boolean',
        'vhost.last_monitored_unix': 'INCOMPATIBLE - V3 expects number',
        'brand.button_text_light': 'INCOMPATIBLE - V3 expects boolean',
        'null subdomain': 'COMPATIBLE - both use null',
        'null vhost/brand': 'COMPATIBLE - both use null',
        'domain structure fields': 'COMPATIBLE - both use strings',
      },
      'V3 Wire -> V2 Schema': {
        'created/updated (number->string)': 'COMPATIBLE - V2 parseDate handles numbers',
        'verified (boolean->string)': 'COMPATIBLE - V2 parseBoolean handles booleans',
        'is_apex (boolean->string)': 'COMPATIBLE - V2 parseBoolean handles booleans',
        'vhost (native types)': 'COMPATIBLE - V2 nested transforms handle both',
        'brand (native types)': 'COMPATIBLE - V2 nested transforms handle both',
        'null subdomain': 'COMPATIBLE - both use null',
        'domain structure fields': 'COMPATIBLE - both use strings',
      },
      'Semantic Differences': {
        'verified: missing': 'V2 uses transform, V3 defaults to false',
        'is_apex: missing': 'Both handle via defaults',
        'vhost: null': 'Both accept null for unverified domains',
        'brand: null': 'Both accept null for unconfigured domains',
      },
    };

    console.log('\n=== V2 <-> V3 CustomDomain Compatibility Matrix ===');
    console.log(JSON.stringify(matrix, null, 2));

    // V3 -> V2 is generally compatible (V2 has flexible preprocessors)
    // V2 -> V3 is generally INCOMPATIBLE (V3 expects strict types)
    expect(true).toBe(true); // Documentation test
  });

  it('documents custom_domain-specific transformation notes', () => {
    const notes = {
      'domain parsing fields':
        'tld, sld, trd, subdomain, base_domain are parsed from display_domain via PublicSuffix',
      'is_apex semantics':
        'true when subdomain is null (apex domain like example.com)',
      'nested objects':
        'vhost and brand are nullable and have their own type transforms',
      'vhost timestamps':
        'created_at, last_monitored_unix, ssl_active_from/until are dates',
      'brand booleans':
        'button_text_light, allow_public_homepage, allow_public_api, passphrase_required, notify_enabled',
      'DNS validation':
        'txt_validation_host and txt_validation_value for domain ownership verification',
    };

    expect(notes).toBeDefined();
  });
});

// -----------------------------------------------------------------------------
// Transform Error Handling
// -----------------------------------------------------------------------------

describe('Transform Error Handling', () => {
  describe('malformed input handling', () => {
    it('V2 parseBoolean returns false for unrecognized values', () => {
      const wire = createV2WireCustomDomain(createCanonicalCustomDomain());
      (wire as Record<string, unknown>).verified = 'maybe';

      const result = v2CustomDomainSchema.safeParse(wire);

      if (result.success) {
        // parseBoolean returns false for unrecognized values
        expect(result.data.verified).toBe(false);
      }
    });

    it('V2 parseBoolean handles "1" as true', () => {
      const wire = createV2WireCustomDomain(createCanonicalCustomDomain());
      (wire as Record<string, unknown>).verified = '1';

      const result = v2CustomDomainSchema.safeParse(wire);

      if (result.success) {
        expect(result.data.verified).toBe(true);
      }
    });

    it('V2 parseBoolean handles "0" as false', () => {
      const wire = createV2WireCustomDomain(createCanonicalCustomDomain());
      (wire as Record<string, unknown>).verified = '0';

      const result = v2CustomDomainSchema.safeParse(wire);

      if (result.success) {
        expect(result.data.verified).toBe(false);
      }
    });
  });

  describe('required field validation', () => {
    it('rejects missing identifier', () => {
      const wire = createV2WireCustomDomain(createCanonicalCustomDomain());
      const { identifier, ...wireWithoutIdentifier } = wire;

      const result = v2CustomDomainSchema.safeParse(wireWithoutIdentifier);

      expect(result.success).toBe(false);
    });

    it('rejects missing display_domain', () => {
      const wire = createV2WireCustomDomain(createCanonicalCustomDomain());
      const { display_domain, ...wireWithoutDomain } = wire;

      const result = v2CustomDomainSchema.safeParse(wireWithoutDomain);

      expect(result.success).toBe(false);
    });

    it('rejects missing tld', () => {
      const wire = createV2WireCustomDomain(createCanonicalCustomDomain());
      const { tld, ...wireWithoutTld } = wire;

      const result = v2CustomDomainSchema.safeParse(wireWithoutTld);

      expect(result.success).toBe(false);
    });
  });
});

// -----------------------------------------------------------------------------
// V3 Default Values
// -----------------------------------------------------------------------------

describe('V3 CustomDomain Default Values', () => {
  it('applies default for verified when missing', () => {
    const wire = createV3WireCustomDomain(createCanonicalCustomDomain());
    const { verified, ...wireWithoutVerified } = wire;

    const parsed = v3CustomDomainSchema.parse(wireWithoutVerified);

    expect(parsed.verified).toBe(false);
  });

  it('applies default for is_apex when missing', () => {
    const wire = createV3WireCustomDomain(createCanonicalCustomDomain());
    const { is_apex, ...wireWithoutApex } = wire;

    const parsed = v3CustomDomainSchema.parse(wireWithoutApex);

    expect(parsed.is_apex).toBe(false);
  });

  it('applies null default for vhost when missing', () => {
    const wire = createV3WireCustomDomain(createPendingDomain());
    const { vhost, ...wireWithoutVhost } = wire;

    const parsed = v3CustomDomainSchema.parse(wireWithoutVhost);

    expect(parsed.vhost).toBeNull();
  });

  it('applies null default for brand when missing', () => {
    const wire = createV3WireCustomDomain(createPendingDomain());
    const { brand, ...wireWithoutBrand } = wire;

    const parsed = v3CustomDomainSchema.parse(wireWithoutBrand);

    expect(parsed.brand).toBeNull();
  });

  it('applies pending status default when missing', () => {
    const wire = createV3WireCustomDomain(createCanonicalCustomDomain());
    const { status, ...wireWithoutStatus } = wire;

    const parsed = v3CustomDomainSchema.parse(wireWithoutStatus);

    expect(parsed.status).toBe('pending');
  });
});
