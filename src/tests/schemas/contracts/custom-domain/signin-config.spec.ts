// src/tests/schemas/contracts/custom-domain/signin-config.spec.ts
//
// Contract validation for CustomDomain::SigninConfig schemas.
//
// Covers:
// - signinRestrictToSchema: enum values, reject unknown
// - SIGNIN_RESTRICT_TO_METADATA: drift guard against enum
// - customDomainSigninConfigCanonical: required fields, nullable restrict_to
// - putSigninConfigPayloadSchema: all-optional, nullable restrict_to

import { describe, it, expect } from 'vitest';
import {
  signinRestrictToSchema,
  SIGNIN_RESTRICT_TO_METADATA,
  customDomainSigninConfigCanonical,
  putSigninConfigPayloadSchema,
  type SigninRestrictTo,
} from '@/schemas/contracts/custom-domain/signin-config';

// -----------------------------------------------------------------------------
// signinRestrictToSchema
// -----------------------------------------------------------------------------

describe('signinRestrictToSchema', () => {
  const validValues: SigninRestrictTo[] = ['password', 'email_auth', 'webauthn', 'sso'];

  it.each(validValues)('accepts valid value "%s"', (value) => {
    const result = signinRestrictToSchema.parse(value);
    expect(result).toBe(value);
  });

  it('rejects unknown string', () => {
    const parsed = signinRestrictToSchema.safeParse('magic_link');
    expect(parsed.success).toBe(false);
  });

  it('rejects empty string', () => {
    const parsed = signinRestrictToSchema.safeParse('');
    expect(parsed.success).toBe(false);
  });

  it('rejects number', () => {
    const parsed = signinRestrictToSchema.safeParse(42);
    expect(parsed.success).toBe(false);
  });

  it('exposes exactly 4 enum values', () => {
    const enumValues = signinRestrictToSchema.options;
    expect(enumValues).toHaveLength(4);
    expect([...enumValues].sort()).toEqual(['email_auth', 'password', 'sso', 'webauthn']);
  });
});

// -----------------------------------------------------------------------------
// SIGNIN_RESTRICT_TO_METADATA drift guard
// -----------------------------------------------------------------------------

describe('SIGNIN_RESTRICT_TO_METADATA', () => {
  it('has an entry for every enum value', () => {
    const enumValues = signinRestrictToSchema.options;
    const metadataKeys = Object.keys(SIGNIN_RESTRICT_TO_METADATA);

    expect(metadataKeys.sort()).toEqual([...enumValues].sort());
  });

  it('each entry has description and requiresFeature strings', () => {
    for (const key of Object.keys(SIGNIN_RESTRICT_TO_METADATA) as SigninRestrictTo[]) {
      const entry = SIGNIN_RESTRICT_TO_METADATA[key];
      expect(typeof entry.description).toBe('string');
      expect(entry.description.length).toBeGreaterThan(0);
      expect(typeof entry.requiresFeature).toBe('string');
      expect(entry.requiresFeature.length).toBeGreaterThan(0);
    }
  });
});

// -----------------------------------------------------------------------------
// customDomainSigninConfigCanonical
// -----------------------------------------------------------------------------

describe('customDomainSigninConfigCanonical', () => {
  const validConfig = {
    domain_id: 'dm-ext-123',
    enabled: true,
    signin_enabled: true,
    restrict_to: null,
    email_auth_enabled: true,
    sso_enabled: false,
    created_at: 1700000000,
    updated_at: 1700001000,
  };

  it('parses a complete valid config', () => {
    const result = customDomainSigninConfigCanonical.parse(validConfig);
    expect(result.domain_id).toBe('dm-ext-123');
    expect(result.enabled).toBe(true);
    expect(result.restrict_to).toBeNull();
    expect(result.created_at).toBe(1700000000);
  });

  it('accepts restrict_to as null', () => {
    const result = customDomainSigninConfigCanonical.parse(validConfig);
    expect(result.restrict_to).toBeNull();
  });

  it('accepts restrict_to as valid enum value', () => {
    const result = customDomainSigninConfigCanonical.parse({
      ...validConfig,
      restrict_to: 'sso',
    });
    expect(result.restrict_to).toBe('sso');
  });

  it('rejects restrict_to as invalid string', () => {
    const parsed = customDomainSigninConfigCanonical.safeParse({
      ...validConfig,
      restrict_to: 'oauth',
    });
    expect(parsed.success).toBe(false);
  });

  it('rejects missing domain_id', () => {
    const { domain_id: _, ...without } = validConfig;
    const parsed = customDomainSigninConfigCanonical.safeParse(without);
    expect(parsed.success).toBe(false);
  });

  it('rejects missing enabled', () => {
    const { enabled: _, ...without } = validConfig;
    const parsed = customDomainSigninConfigCanonical.safeParse(without);
    expect(parsed.success).toBe(false);
  });

  it('rejects missing signin_enabled', () => {
    const { signin_enabled: _, ...without } = validConfig;
    const parsed = customDomainSigninConfigCanonical.safeParse(without);
    expect(parsed.success).toBe(false);
  });

  it('rejects missing email_auth_enabled', () => {
    const { email_auth_enabled: _, ...without } = validConfig;
    const parsed = customDomainSigninConfigCanonical.safeParse(without);
    expect(parsed.success).toBe(false);
  });

  it('rejects missing sso_enabled', () => {
    const { sso_enabled: _, ...without } = validConfig;
    const parsed = customDomainSigninConfigCanonical.safeParse(without);
    expect(parsed.success).toBe(false);
  });

  it('rejects missing timestamps', () => {
    const { created_at: _, updated_at: __, ...without } = validConfig;
    const parsed = customDomainSigninConfigCanonical.safeParse(without);
    expect(parsed.success).toBe(false);
  });

  it('rejects enabled as string', () => {
    const parsed = customDomainSigninConfigCanonical.safeParse({
      ...validConfig,
      enabled: 'true',
    });
    expect(parsed.success).toBe(false);
  });

  it('timestamps are numbers (no transform at canonical level)', () => {
    const result = customDomainSigninConfigCanonical.parse(validConfig);
    expect(typeof result.created_at).toBe('number');
    expect(typeof result.updated_at).toBe('number');
  });

  it('round-trips through JSON', () => {
    const result = customDomainSigninConfigCanonical.parse(validConfig);
    const serialized = JSON.stringify(result);
    const reparsed = customDomainSigninConfigCanonical.parse(JSON.parse(serialized));
    expect(reparsed).toEqual(result);
  });
});

// -----------------------------------------------------------------------------
// putSigninConfigPayloadSchema
// -----------------------------------------------------------------------------

describe('putSigninConfigPayloadSchema', () => {
  it('accepts empty object (all fields optional)', () => {
    const result = putSigninConfigPayloadSchema.parse({});
    expect(result).toBeDefined();
  });

  it('accepts a full payload', () => {
    const result = putSigninConfigPayloadSchema.parse({
      enabled: true,
      signin_enabled: true,
      restrict_to: 'email_auth',
      email_auth_enabled: true,
      sso_enabled: false,
    });
    expect(result.enabled).toBe(true);
    expect(result.restrict_to).toBe('email_auth');
  });

  it('accepts restrict_to as null', () => {
    const result = putSigninConfigPayloadSchema.parse({ restrict_to: null });
    expect(result.restrict_to).toBeNull();
  });

  it('accepts restrict_to as valid enum value', () => {
    const result = putSigninConfigPayloadSchema.parse({ restrict_to: 'webauthn' });
    expect(result.restrict_to).toBe('webauthn');
  });

  it('rejects restrict_to as invalid string', () => {
    const parsed = putSigninConfigPayloadSchema.safeParse({ restrict_to: 'oauth' });
    expect(parsed.success).toBe(false);
  });

  it('rejects boolean fields as strings', () => {
    const parsed = putSigninConfigPayloadSchema.safeParse({ enabled: 'true' });
    expect(parsed.success).toBe(false);
  });

  it('accepts partial payload (just enabled)', () => {
    const result = putSigninConfigPayloadSchema.parse({ enabled: false });
    expect(result.enabled).toBe(false);
    expect(result.signin_enabled).toBeUndefined();
  });
});
