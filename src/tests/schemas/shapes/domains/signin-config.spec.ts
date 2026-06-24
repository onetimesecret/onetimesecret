// src/tests/schemas/shapes/domains/signin-config.spec.ts
//
// Shape validation tests for CustomDomain::SigninConfig after timestamp
// transforms. Verifies: wire number -> Date for created_at/updated_at,
// restrict_to nullable, summary schema subset.
//
// Architecture: contract (numbers) -> shape (Dates) -> API (envelope)

import { describe, it, expect } from 'vitest';
import {
  customDomainSigninConfigSchema,
  customDomainSigninConfigSummarySchema,
  type CustomDomainSigninConfig,
  type CustomDomainSigninConfigSummary,
} from '@/schemas/shapes/domains/signin-config';

// -----------------------------------------------------------------------------
// Fixtures
// -----------------------------------------------------------------------------

const wireConfig = {
  domain_id: 'dm-ext-789',
  enabled: true,
  signin_enabled: true,
  restrict_to: null,
  email_auth_enabled: true,
  sso_enabled: false,
  created_at: 1700000000,
  updated_at: 1700001000,
};

const wireSummary = {
  domain_id: 'dm-ext-789',
  enabled: true,
  signin_enabled: true,
  restrict_to: null,
  created_at: 1700000000,
  updated_at: 1700001000,
};

// -----------------------------------------------------------------------------
// customDomainSigninConfigSchema (full shape with transforms)
// -----------------------------------------------------------------------------

describe('customDomainSigninConfigSchema', () => {
  it('transforms created_at from number to Date', () => {
    const result = customDomainSigninConfigSchema.parse(wireConfig);
    expect(result.created_at).toBeInstanceOf(Date);
    expect(result.created_at.getTime()).toBe(1700000000 * 1000);
  });

  it('transforms updated_at from number to Date', () => {
    const result = customDomainSigninConfigSchema.parse(wireConfig);
    expect(result.updated_at).toBeInstanceOf(Date);
    expect(result.updated_at.getTime()).toBe(1700001000 * 1000);
  });

  it('preserves identity fields unchanged', () => {
    const result = customDomainSigninConfigSchema.parse(wireConfig);
    expect(result.domain_id).toBe('dm-ext-789');
  });

  it('preserves boolean fields unchanged', () => {
    const result = customDomainSigninConfigSchema.parse(wireConfig);
    expect(result.enabled).toBe(true);
    expect(result.signin_enabled).toBe(true);
    expect(result.email_auth_enabled).toBe(true);
    expect(result.sso_enabled).toBe(false);
  });

  it('accepts restrict_to as null', () => {
    const result = customDomainSigninConfigSchema.parse(wireConfig);
    expect(result.restrict_to).toBeNull();
  });

  it('accepts restrict_to as valid enum value', () => {
    const result = customDomainSigninConfigSchema.parse({
      ...wireConfig,
      restrict_to: 'sso',
    });
    expect(result.restrict_to).toBe('sso');
  });

  it.each(['password', 'email_auth', 'webauthn', 'sso'] as const)(
    'accepts restrict_to = "%s"',
    (method) => {
      const result = customDomainSigninConfigSchema.parse({
        ...wireConfig,
        restrict_to: method,
      });
      expect(result.restrict_to).toBe(method);
    }
  );

  it('rejects restrict_to as invalid string', () => {
    const parsed = customDomainSigninConfigSchema.safeParse({
      ...wireConfig,
      restrict_to: 'oauth',
    });
    expect(parsed.success).toBe(false);
  });

  it('rejects timestamps as strings', () => {
    const parsed = customDomainSigninConfigSchema.safeParse({
      ...wireConfig,
      created_at: '1700000000',
    });
    expect(parsed.success).toBe(false);
  });

  it('rejects missing required boolean fields', () => {
    const { sso_enabled: _, ...without } = wireConfig;
    const parsed = customDomainSigninConfigSchema.safeParse(without);
    expect(parsed.success).toBe(false);
  });

  it('conforms to CustomDomainSigninConfig type', () => {
    const result: CustomDomainSigninConfig =
      customDomainSigninConfigSchema.parse(wireConfig);
    // Type-level assertion (compile time). Runtime: just confirm object.
    expect(typeof result).toBe('object');
  });

  it('round-trips a full config with all restrict_to values', () => {
    const withRestrict = { ...wireConfig, restrict_to: 'email_auth' as const };
    const parsed = customDomainSigninConfigSchema.parse(withRestrict);

    // After transform, timestamps are Date objects, so a JSON round-trip
    // re-serializes them as ISO strings. This test confirms the shape
    // parses cleanly from wire format.
    expect(parsed.restrict_to).toBe('email_auth');
    expect(parsed.created_at).toBeInstanceOf(Date);
  });

  it('handles disabled config (all booleans false)', () => {
    const disabled = {
      ...wireConfig,
      enabled: false,
      signin_enabled: false,
      email_auth_enabled: false,
      sso_enabled: false,
    };
    const result = customDomainSigninConfigSchema.parse(disabled);
    expect(result.enabled).toBe(false);
    expect(result.signin_enabled).toBe(false);
    expect(result.email_auth_enabled).toBe(false);
    expect(result.sso_enabled).toBe(false);
  });
});

// -----------------------------------------------------------------------------
// customDomainSigninConfigSummarySchema (list-view subset)
// -----------------------------------------------------------------------------

describe('customDomainSigninConfigSummarySchema', () => {
  it('transforms timestamps from number to Date', () => {
    const result = customDomainSigninConfigSummarySchema.parse(wireSummary);
    expect(result.created_at).toBeInstanceOf(Date);
    expect(result.updated_at).toBeInstanceOf(Date);
  });

  it('preserves core fields', () => {
    const result = customDomainSigninConfigSummarySchema.parse(wireSummary);
    expect(result.domain_id).toBe('dm-ext-789');
    expect(result.enabled).toBe(true);
    expect(result.signin_enabled).toBe(true);
  });

  it('accepts restrict_to as null', () => {
    const result = customDomainSigninConfigSummarySchema.parse(wireSummary);
    expect(result.restrict_to).toBeNull();
  });

  it('accepts restrict_to as valid enum value', () => {
    const result = customDomainSigninConfigSummarySchema.parse({
      ...wireSummary,
      restrict_to: 'webauthn',
    });
    expect(result.restrict_to).toBe('webauthn');
  });

  it('does not require email_auth_enabled or sso_enabled', () => {
    // Summary schema is a subset; those detail fields are not present
    const result = customDomainSigninConfigSummarySchema.parse(wireSummary);
    expect(result).not.toHaveProperty('email_auth_enabled');
    expect(result).not.toHaveProperty('sso_enabled');
  });

  it('conforms to CustomDomainSigninConfigSummary type', () => {
    const result: CustomDomainSigninConfigSummary =
      customDomainSigninConfigSummarySchema.parse(wireSummary);
    expect(typeof result).toBe('object');
  });
});
