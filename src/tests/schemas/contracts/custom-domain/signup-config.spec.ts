// src/tests/schemas/contracts/custom-domain/signup-config.spec.ts
//
// Contract validation for CustomDomain::SignupConfig schemas.
//
// Covers:
// - signupValidationStrategySchema: enum values, reject unknown
// - SIGNUP_STRATEGY_METADATA: drift guard against enum
// - customDomainSignupConfigCanonical: allow_base_domain defaults false when
//   absent (older API during a deploy), boolean when present
// - putSignupConfigPayloadStrictSchema: domain_allowlist needs a listed
//   domain OR allow_base_domain; other strategies need neither

import { describe, it, expect } from 'vitest';
import {
  signupValidationStrategySchema,
  SIGNUP_STRATEGY_METADATA,
  customDomainSignupConfigCanonical,
  putSignupConfigPayloadStrictSchema,
  type SignupValidationStrategy,
} from '@/schemas/contracts/custom-domain/signup-config';

// -----------------------------------------------------------------------------
// signupValidationStrategySchema
// -----------------------------------------------------------------------------

describe('signupValidationStrategySchema', () => {
  const validValues: SignupValidationStrategy[] = ['passthrough', 'domain_allowlist', 'mx', 'smtp'];

  it.each(validValues)('accepts valid value "%s"', (value) => {
    expect(signupValidationStrategySchema.parse(value)).toBe(value);
  });

  it('rejects unknown string', () => {
    expect(signupValidationStrategySchema.safeParse('own_domain').success).toBe(false);
  });

  it('metadata covers every strategy and nothing else (drift guard)', () => {
    expect(Object.keys(SIGNUP_STRATEGY_METADATA).sort()).toEqual(
      [...signupValidationStrategySchema.options].sort()
    );
  });

  it('only domain_allowlist requires the allowlist', () => {
    const requiring = Object.entries(SIGNUP_STRATEGY_METADATA)
      .filter(([, meta]) => meta.requiresAllowlist)
      .map(([key]) => key);
    expect(requiring).toEqual(['domain_allowlist']);
  });
});

// -----------------------------------------------------------------------------
// customDomainSignupConfigCanonical
// -----------------------------------------------------------------------------

describe('customDomainSignupConfigCanonical', () => {
  const base = {
    domain_id: 'dm-ext-123',
    validation_strategy: 'domain_allowlist',
    allowed_signup_domains: ['acme.com'],
    enabled: true,
    signup_enabled: true,
    autoverify: false,
    requires_allowlist: true,
    network_validation: false,
    created_at: 1700000000,
    updated_at: 1700000001,
  };

  it('defaults allow_base_domain to false when the API omits it', () => {
    const parsed = customDomainSignupConfigCanonical.parse(base);
    expect(parsed.allow_base_domain).toBe(false);
  });

  it('keeps allow_base_domain true when the API sends it', () => {
    const parsed = customDomainSignupConfigCanonical.parse({ ...base, allow_base_domain: true });
    expect(parsed.allow_base_domain).toBe(true);
  });

  it('rejects a non-boolean allow_base_domain', () => {
    const result = customDomainSignupConfigCanonical.safeParse({
      ...base,
      allow_base_domain: 'true',
    });
    expect(result.success).toBe(false);
  });
});

// -----------------------------------------------------------------------------
// putSignupConfigPayloadStrictSchema
// -----------------------------------------------------------------------------

describe('putSignupConfigPayloadStrictSchema', () => {
  it('rejects domain_allowlist with no listed domain and no allow_base_domain', () => {
    const result = putSignupConfigPayloadStrictSchema.safeParse({
      validation_strategy: 'domain_allowlist',
      allowed_signup_domains: [],
    });
    expect(result.success).toBe(false);
    if (!result.success) {
      expect(result.error.issues[0]?.path).toEqual(['allowed_signup_domains']);
    }
  });

  it('rejects domain_allowlist with allow_base_domain explicitly false and nothing listed', () => {
    const result = putSignupConfigPayloadStrictSchema.safeParse({
      validation_strategy: 'domain_allowlist',
      allowed_signup_domains: [],
      allow_base_domain: false,
    });
    expect(result.success).toBe(false);
  });

  it('accepts domain_allowlist with allow_base_domain and an empty list (the base domain is the list)', () => {
    const result = putSignupConfigPayloadStrictSchema.safeParse({
      validation_strategy: 'domain_allowlist',
      allowed_signup_domains: [],
      allow_base_domain: true,
    });
    expect(result.success).toBe(true);
  });

  it('accepts domain_allowlist with allow_base_domain and the list omitted entirely', () => {
    const result = putSignupConfigPayloadStrictSchema.safeParse({
      validation_strategy: 'domain_allowlist',
      allow_base_domain: true,
    });
    expect(result.success).toBe(true);
  });

  it('accepts domain_allowlist with a listed domain and no flag (unchanged behavior)', () => {
    const result = putSignupConfigPayloadStrictSchema.safeParse({
      validation_strategy: 'domain_allowlist',
      allowed_signup_domains: ['acme.com'],
    });
    expect(result.success).toBe(true);
  });

  it.each(['passthrough', 'mx', 'smtp'] as const)(
    'does not require a list or the flag for "%s"',
    (strategy) => {
      const result = putSignupConfigPayloadStrictSchema.safeParse({
        validation_strategy: strategy,
      });
      expect(result.success).toBe(true);
    }
  );
});
