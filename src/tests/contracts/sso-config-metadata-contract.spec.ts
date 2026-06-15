// src/tests/contracts/sso-config-metadata-contract.spec.ts
//
// Contract tests for SSO_PROVIDER_METADATA constant and customDomainSsoConfigCanonical schema.
// Verifies frontend metadata matches backend PROVIDER_METADATA constant in:
// lib/onetime/models/custom_domain/sso_config.rb
//
// These tests ensure the frontend has accurate information about which
// providers require domain filtering vs having IdP-controlled access.
//
// Note: SSO config is per-domain. Model is CustomDomain::SsoConfig (#2786, #2801).

import { describe, expect, it } from 'vitest';
import {
  SSO_PROVIDER_METADATA,
  ssoProviderTypeSchema,
  customDomainSsoConfigCanonical,
  patchSsoConfigPayloadSchema,
  putSsoConfigPayloadSchema,
  type SsoProviderType,
} from '@/schemas/contracts/custom-domain/sso-config';

describe('SSO_PROVIDER_METADATA constant', () => {
  describe('structure', () => {
    it('defines metadata for all supported provider types', () => {
      const supportedProviders = ssoProviderTypeSchema.options;
      const metadataProviders = Object.keys(SSO_PROVIDER_METADATA);

      expect(metadataProviders.sort()).toEqual([...supportedProviders].sort());
    });

    it('each provider has requiresDomainFilter boolean', () => {
      for (const [_provider, metadata] of Object.entries(SSO_PROVIDER_METADATA)) {
        expect(typeof metadata.requiresDomainFilter).toBe('boolean');
      }
    });

    it('each provider has idpControlsAccess boolean', () => {
      for (const [_provider, metadata] of Object.entries(SSO_PROVIDER_METADATA)) {
        expect(typeof metadata.idpControlsAccess).toBe('boolean');
      }
    });

    it('each provider has description string', () => {
      for (const [_provider, metadata] of Object.entries(SSO_PROVIDER_METADATA)) {
        expect(typeof metadata.description).toBe('string');
        expect(metadata.description.length).toBeGreaterThan(0);
      }
    });
  });

  describe('provider-specific values (mirrors backend PROVIDER_METADATA)', () => {
    // Values must match lib/onetime/models/custom_domain/sso_config.rb PROVIDER_METADATA

    describe('oidc', () => {
      it('requires domain filter (generic OIDC has no app assignment)', () => {
        expect(SSO_PROVIDER_METADATA.oidc.requiresDomainFilter).toBe(true);
      });

      it('does NOT have IdP-controlled access', () => {
        expect(SSO_PROVIDER_METADATA.oidc.idpControlsAccess).toBe(false);
      });
    });

    describe('entra_id', () => {
      it('does not require domain filter (Azure app assignment controls access)', () => {
        expect(SSO_PROVIDER_METADATA.entra_id.requiresDomainFilter).toBe(false);
      });

      it('has IdP-controlled access', () => {
        expect(SSO_PROVIDER_METADATA.entra_id.idpControlsAccess).toBe(true);
      });
    });

    describe('google', () => {
      it('requires domain filter (Workspace needs explicit filtering for enterprise)', () => {
        expect(SSO_PROVIDER_METADATA.google.requiresDomainFilter).toBe(true);
      });

      it('does NOT have IdP-controlled access', () => {
        expect(SSO_PROVIDER_METADATA.google.idpControlsAccess).toBe(false);
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
      for (const [_provider, metadata] of Object.entries(SSO_PROVIDER_METADATA)) {
        expect(metadata.requiresDomainFilter).toBe(!metadata.idpControlsAccess);
      }
    });
  });
});

describe('customDomainSsoConfigCanonical schema', () => {
  describe('metadata fields', () => {
    it('declares requires_domain_filter field', () => {
      expect(customDomainSsoConfigCanonical.shape.requires_domain_filter).toBeDefined();
    });

    it('declares idp_controls_access field', () => {
      expect(customDomainSsoConfigCanonical.shape.idp_controls_access).toBeDefined();
    });

    it('requires_domain_filter is a boolean', () => {
      const result = customDomainSsoConfigCanonical.shape.requires_domain_filter.safeParse(true);
      expect(result.success).toBe(true);

      const invalidResult = customDomainSsoConfigCanonical.shape.requires_domain_filter.safeParse('true');
      expect(invalidResult.success).toBe(false);
    });

    it('idp_controls_access is a boolean', () => {
      const result = customDomainSsoConfigCanonical.shape.idp_controls_access.safeParse(false);
      expect(result.success).toBe(true);

      const invalidResult = customDomainSsoConfigCanonical.shape.idp_controls_access.safeParse('false');
      expect(invalidResult.success).toBe(false);
    });
  });

  describe('enforce_sso_only field', () => {
    it('declares enforce_sso_only field', () => {
      expect(customDomainSsoConfigCanonical.shape.enforce_sso_only).toBeDefined();
    });

    it('enforce_sso_only is a boolean', () => {
      const result = customDomainSsoConfigCanonical.shape.enforce_sso_only.safeParse(true);
      expect(result.success).toBe(true);

      const invalidResult = customDomainSsoConfigCanonical.shape.enforce_sso_only.safeParse('true');
      expect(invalidResult.success).toBe(false);
    });

    it('enforce_sso_only accepts false value', () => {
      const result = customDomainSsoConfigCanonical.shape.enforce_sso_only.safeParse(false);
      expect(result.success).toBe(true);
    });
  });

  describe('full payload parsing with metadata fields', () => {
    // Schema: customDomainSsoConfigCanonical (keyed by domain_id)
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
      enforce_sso_only: false,
      grant_org_scope: false,
      created_at: 1700000000,
      updated_at: 1700000000,
    };

    it('parses payload with GitHub metadata values', () => {
      const result = customDomainSsoConfigCanonical.safeParse(validPayload);
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
      const result = customDomainSsoConfigCanonical.safeParse(entraPayload);
      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data.requires_domain_filter).toBe(false);
        expect(result.data.idp_controls_access).toBe(true);
      }
    });

    it('parses payload with enforce_sso_only enabled', () => {
      const enforcePayload = {
        ...validPayload,
        enforce_sso_only: true,
      };
      const result = customDomainSsoConfigCanonical.safeParse(enforcePayload);
      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data.enforce_sso_only).toBe(true);
      }
    });

    it('parses payload with enforce_sso_only disabled (default)', () => {
      const result = customDomainSsoConfigCanonical.safeParse(validPayload);
      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data.enforce_sso_only).toBe(false);
      }
    });

    it('fails when requires_domain_filter is missing', () => {
      const { requires_domain_filter: _rdm, ...incomplete } = validPayload;
      const result = customDomainSsoConfigCanonical.safeParse(incomplete);
      expect(result.success).toBe(false);
    });

    it('fails when idp_controls_access is missing', () => {
      const { idp_controls_access: _ica, ...incomplete } = validPayload;
      const result = customDomainSsoConfigCanonical.safeParse(incomplete);
      expect(result.success).toBe(false);
    });

    it('fails when enforce_sso_only is missing', () => {
      const { enforce_sso_only: _eso, ...incomplete } = validPayload;
      const result = customDomainSsoConfigCanonical.safeParse(incomplete);
      expect(result.success).toBe(false);
    });
  });
});

describe('PUT/PATCH payload schemas with enforce_sso_only', () => {
  describe('patchSsoConfigPayloadSchema', () => {
    it('accepts enforce_sso_only as optional boolean', () => {
      const payload = { enforce_sso_only: true };
      const result = patchSsoConfigPayloadSchema.safeParse(payload);
      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data.enforce_sso_only).toBe(true);
      }
    });

    it('accepts payload without enforce_sso_only (partial update)', () => {
      const payload = { display_name: 'Updated SSO' };
      const result = patchSsoConfigPayloadSchema.safeParse(payload);
      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data.enforce_sso_only).toBeUndefined();
      }
    });

    it('rejects non-boolean enforce_sso_only', () => {
      const payload = { enforce_sso_only: 'true' };
      const result = patchSsoConfigPayloadSchema.safeParse(payload);
      expect(result.success).toBe(false);
    });

    it('accepts enforce_sso_only=false explicitly', () => {
      const payload = { enforce_sso_only: false };
      const result = patchSsoConfigPayloadSchema.safeParse(payload);
      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data.enforce_sso_only).toBe(false);
      }
    });
  });

  describe('putSsoConfigPayloadSchema', () => {
    const validPutPayload = {
      provider_type: 'entra_id' as SsoProviderType,
      display_name: 'Test SSO',
      client_id: 'client-123',
      client_secret: 'secret-456',
      tenant_id: 'tenant-789',
    };

    it('accepts enforce_sso_only in PUT payload', () => {
      const payload = { ...validPutPayload, enforce_sso_only: true };
      const result = putSsoConfigPayloadSchema.safeParse(payload);
      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data.enforce_sso_only).toBe(true);
      }
    });

    it('allows PUT payload without enforce_sso_only (defaults to false)', () => {
      const result = putSsoConfigPayloadSchema.safeParse(validPutPayload);
      expect(result.success).toBe(true);
      // Schema should allow omission; backend defaults to false
    });

    it('accepts enforce_sso_only=false in PUT payload', () => {
      const payload = { ...validPutPayload, enforce_sso_only: false };
      const result = putSsoConfigPayloadSchema.safeParse(payload);
      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data.enforce_sso_only).toBe(false);
      }
    });
  });
});
