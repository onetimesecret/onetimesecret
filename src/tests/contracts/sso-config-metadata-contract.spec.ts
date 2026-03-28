// src/tests/contracts/sso-config-metadata-contract.spec.ts
//
// Contract tests for SSO_PROVIDER_METADATA constant and domainSsoConfigCanonical schema.
// Verifies frontend metadata matches backend PROVIDER_METADATA constant in:
// lib/onetime/models/domain_sso_config.rb
//
// These tests ensure the frontend has accurate information about which
// providers require domain filtering vs having IdP-controlled access.
//
// Note: SSO config moved from per-org to per-domain in #2786. The schema was
// renamed to domainSsoConfigCanonical; orgSsoConfigCanonical is a deprecated alias.

import { describe, expect, it } from 'vitest';
import {
  SSO_PROVIDER_METADATA,
  ssoProviderTypeSchema,
  orgSsoConfigCanonical,
  type SsoProviderType,
} from '@/schemas/contracts/sso-config';

describe('SSO_PROVIDER_METADATA constant', () => {
  describe('structure', () => {
    it('defines metadata for all supported provider types', () => {
      const supportedProviders = ssoProviderTypeSchema.options;
      const metadataProviders = Object.keys(SSO_PROVIDER_METADATA);

      expect(metadataProviders.sort()).toEqual([...supportedProviders].sort());
    });

    it('each provider has requiresDomainFilter boolean', () => {
      for (const [provider, metadata] of Object.entries(SSO_PROVIDER_METADATA)) {
        expect(typeof metadata.requiresDomainFilter).toBe('boolean');
      }
    });

    it('each provider has idpControlsAccess boolean', () => {
      for (const [provider, metadata] of Object.entries(SSO_PROVIDER_METADATA)) {
        expect(typeof metadata.idpControlsAccess).toBe('boolean');
      }
    });

    it('each provider has description string', () => {
      for (const [provider, metadata] of Object.entries(SSO_PROVIDER_METADATA)) {
        expect(typeof metadata.description).toBe('string');
        expect(metadata.description.length).toBeGreaterThan(0);
      }
    });
  });

  describe('provider-specific values (mirrors backend PROVIDER_METADATA)', () => {
    describe('oidc', () => {
      it('does not require domain filter', () => {
        expect(SSO_PROVIDER_METADATA.oidc.requiresDomainFilter).toBe(false);
      });

      it('has IdP-controlled access', () => {
        expect(SSO_PROVIDER_METADATA.oidc.idpControlsAccess).toBe(true);
      });
    });

    describe('entra_id', () => {
      it('does not require domain filter', () => {
        expect(SSO_PROVIDER_METADATA.entra_id.requiresDomainFilter).toBe(false);
      });

      it('has IdP-controlled access', () => {
        expect(SSO_PROVIDER_METADATA.entra_id.idpControlsAccess).toBe(true);
      });
    });

    describe('google', () => {
      it('does not require domain filter', () => {
        expect(SSO_PROVIDER_METADATA.google.requiresDomainFilter).toBe(false);
      });

      it('has IdP-controlled access', () => {
        expect(SSO_PROVIDER_METADATA.google.idpControlsAccess).toBe(true);
      });
    });

    describe('github', () => {
      it('requires domain filter', () => {
        expect(SSO_PROVIDER_METADATA.github.requiresDomainFilter).toBe(true);
      });

      it('does NOT have IdP-controlled access', () => {
        expect(SSO_PROVIDER_METADATA.github.idpControlsAccess).toBe(false);
      });

      it('description mentions domain filter recommendation', () => {
        expect(SSO_PROVIDER_METADATA.github.description).toContain('domain filter');
      });
    });
  });

  describe('consistency rules', () => {
    it('requiresDomainFilter and idpControlsAccess are mutually exclusive', () => {
      // If IdP controls access, app-side domain filter is not required
      // If IdP does not control access, domain filter IS required
      for (const [provider, metadata] of Object.entries(SSO_PROVIDER_METADATA)) {
        expect(metadata.requiresDomainFilter).toBe(!metadata.idpControlsAccess);
      }
    });
  });
});

describe('orgSsoConfigCanonical schema', () => {
  describe('metadata fields', () => {
    it('declares requires_domain_filter field', () => {
      expect(orgSsoConfigCanonical.shape.requires_domain_filter).toBeDefined();
    });

    it('declares idp_controls_access field', () => {
      expect(orgSsoConfigCanonical.shape.idp_controls_access).toBeDefined();
    });

    it('requires_domain_filter is a boolean', () => {
      const result = orgSsoConfigCanonical.shape.requires_domain_filter.safeParse(true);
      expect(result.success).toBe(true);

      const invalidResult = orgSsoConfigCanonical.shape.requires_domain_filter.safeParse('true');
      expect(invalidResult.success).toBe(false);
    });

    it('idp_controls_access is a boolean', () => {
      const result = orgSsoConfigCanonical.shape.idp_controls_access.safeParse(false);
      expect(result.success).toBe(true);

      const invalidResult = orgSsoConfigCanonical.shape.idp_controls_access.safeParse('false');
      expect(invalidResult.success).toBe(false);
    });
  });

  describe('full payload parsing with metadata fields', () => {
    // Note: Schema was renamed from orgSsoConfigCanonical to domainSsoConfigCanonical
    // and uses domain_id instead of org_id (per #2786 domain SSO migration)
    const validPayload = {
      domain_id: 'dm_123',
      provider_type: 'github' as SsoProviderType,
      enabled: true,
      display_name: 'GitHub SSO',
      client_id: 'client-abc',
      client_secret_masked: '****5678',
      tenant_id: null,
      issuer: null,
      allowed_domains: [],
      requires_domain_filter: true,
      idp_controls_access: false,
      created_at: 1700000000,
      updated_at: 1700000000,
    };

    it('parses payload with GitHub metadata values', () => {
      const result = orgSsoConfigCanonical.safeParse(validPayload);
      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data.requires_domain_filter).toBe(true);
        expect(result.data.idp_controls_access).toBe(false);
      }
    });

    it('parses payload with Entra ID metadata values', () => {
      const entraPayload = {
        ...validPayload,
        provider_type: 'entra_id' as SsoProviderType,
        tenant_id: 'tenant-123',
        requires_domain_filter: false,
        idp_controls_access: true,
      };
      const result = orgSsoConfigCanonical.safeParse(entraPayload);
      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data.requires_domain_filter).toBe(false);
        expect(result.data.idp_controls_access).toBe(true);
      }
    });

    it('fails when requires_domain_filter is missing', () => {
      const { requires_domain_filter, ...incomplete } = validPayload;
      const result = orgSsoConfigCanonical.safeParse(incomplete);
      expect(result.success).toBe(false);
    });

    it('fails when idp_controls_access is missing', () => {
      const { idp_controls_access, ...incomplete } = validPayload;
      const result = orgSsoConfigCanonical.safeParse(incomplete);
      expect(result.success).toBe(false);
    });
  });
});
