// src/tests/schemas/contracts/config/public.spec.ts
//
// Contract-level tests for publicSecretOptionsSchema and
// publicAuthenticationSchema. The contract is type-only: it accepts any
// well-typed input and does not enforce TTL/passphrase/password-generation
// bounds and does not supply defaults. Defaults and bounds are exercised
// against the shape in `src/tests/schemas/shapes/config/public.spec.ts`.

import { describe, it, expect } from 'vitest';
import {
  publicSecretOptionsSchema,
  publicAuthenticationSchema,
  type SecretOptions,
} from '@/schemas/contracts/config/public';

describe('publicSecretOptionsSchema (contract)', () => {
  describe('empty / partial input', () => {
    it('parses empty object — every field is optional in the contract', () => {
      const result = publicSecretOptionsSchema.parse({});

      expect(result.default_ttl).toBeUndefined();
      expect(result.ttl_options).toBeUndefined();
      expect(result.passphrase).toBeUndefined();
      expect(result.password_generation).toBeUndefined();
    });

    it('parses partial passphrase input without rejecting missing fields', () => {
      const result = publicSecretOptionsSchema.parse({
        passphrase: { required: true },
      });

      expect(result.passphrase?.required).toBe(true);
      expect(result.passphrase?.minimum_length).toBeUndefined();
      expect(result.passphrase?.maximum_length).toBeUndefined();
      expect(result.passphrase?.enforce_complexity).toBeUndefined();
    });
  });

  describe('TTL configuration', () => {
    it('accepts custom default_ttl', () => {
      const result = publicSecretOptionsSchema.parse({ default_ttl: 86400 });
      expect(result.default_ttl).toBe(86400);
    });

    it('accepts custom ttl_options array', () => {
      const customOptions = [300, 3600, 86400];
      const result = publicSecretOptionsSchema.parse({ ttl_options: customOptions });
      expect(result.ttl_options).toEqual(customOptions);
    });

    it('accepts TTL values below the historic min — bounds are a shape concern', () => {
      const result = publicSecretOptionsSchema.parse({ ttl_options: [30] });
      expect(result.ttl_options).toEqual([30]);
    });

    it('accepts TTL values above the historic max — bounds are a shape concern', () => {
      const result = publicSecretOptionsSchema.parse({ ttl_options: [3000000] });
      expect(result.ttl_options).toEqual([3000000]);
    });
  });

  describe('passphrase configuration', () => {
    it('accepts the full passphrase block', () => {
      const result = publicSecretOptionsSchema.parse({
        passphrase: {
          required: true,
          minimum_length: 12,
          maximum_length: 64,
          enforce_complexity: true,
        },
      });

      expect(result.passphrase?.required).toBe(true);
      expect(result.passphrase?.minimum_length).toBe(12);
      expect(result.passphrase?.maximum_length).toBe(64);
      expect(result.passphrase?.enforce_complexity).toBe(true);
    });

    it('accepts zero for minimum_length', () => {
      const result = publicSecretOptionsSchema.parse({ passphrase: { minimum_length: 0 } });
      expect(result.passphrase?.minimum_length).toBe(0);
    });

    it('accepts values beyond the historic length bounds (shape enforces those)', () => {
      const result = publicSecretOptionsSchema.parse({
        passphrase: { minimum_length: 300, maximum_length: 2000 },
      });
      expect(result.passphrase?.minimum_length).toBe(300);
      expect(result.passphrase?.maximum_length).toBe(2000);
    });
  });

  describe('password generation configuration', () => {
    it('accepts the full password_generation block', () => {
      const result = publicSecretOptionsSchema.parse({
        password_generation: {
          default_length: 16,
          length_options: [8, 16, 24, 32],
          character_sets: {
            uppercase: true,
            lowercase: true,
            numbers: true,
            symbols: true,
            exclude_ambiguous: false,
          },
        },
      });

      expect(result.password_generation?.default_length).toBe(16);
      expect(result.password_generation?.length_options).toEqual([8, 16, 24, 32]);
      expect(result.password_generation?.character_sets?.symbols).toBe(true);
      expect(result.password_generation?.character_sets?.exclude_ambiguous).toBe(false);
    });

    it('parses empty password_generation without applying defaults', () => {
      const result = publicSecretOptionsSchema.parse({ password_generation: {} });
      expect(result.password_generation?.default_length).toBeUndefined();
      expect(result.password_generation?.length_options).toBeUndefined();
    });

    it('accepts length values beyond the historic 4–128 range', () => {
      const result = publicSecretOptionsSchema.parse({
        password_generation: { default_length: 2 },
      });
      expect(result.password_generation?.default_length).toBe(2);

      const result2 = publicSecretOptionsSchema.parse({
        password_generation: { default_length: 256 },
      });
      expect(result2.password_generation?.default_length).toBe(256);
    });
  });

  describe('full configuration scenarios', () => {
    it('parses a fully populated production-like configuration', () => {
      const productionConfig = {
        default_ttl: 604800,
        ttl_options: [3600, 86400, 604800, 1209600],
        passphrase: {
          required: false,
          minimum_length: 8,
          maximum_length: 128,
          enforce_complexity: false,
        },
        password_generation: {
          default_length: 16,
          length_options: [12, 16, 20, 24],
          character_sets: {
            uppercase: true,
            lowercase: true,
            numbers: true,
            symbols: false,
            exclude_ambiguous: true,
          },
        },
      };

      const result = publicSecretOptionsSchema.parse(productionConfig);
      expect(result).toMatchObject(productionConfig);
    });

    it('parses a minimal self-hosted configuration', () => {
      const minimalConfig = { default_ttl: 86400, ttl_options: [86400] };
      const result = publicSecretOptionsSchema.parse(minimalConfig);
      expect(result.default_ttl).toBe(86400);
      expect(result.ttl_options).toEqual([86400]);
    });
  });

  describe('type inference', () => {
    it('infers fields as optional numbers / arrays', () => {
      const config: SecretOptions = publicSecretOptionsSchema.parse({
        default_ttl: 100,
        ttl_options: [100],
      });

      const _ttl: number | undefined = config.default_ttl;
      const _options: number[] | undefined = config.ttl_options;

      expect(_ttl).toBe(100);
      expect(_options).toEqual([100]);
    });
  });
});

describe('publicAuthenticationSchema', () => {
  it('parses authentication settings', () => {
    const result = publicAuthenticationSchema.parse({
      enabled: true,
      signup: true,
      signin: true,
      autoverify: false,
      required: false,
    });

    expect(result.enabled).toBe(true);
    expect(result.signup).toBe(true);
    expect(result.signin).toBe(true);
    expect(result.autoverify).toBe(false);
    expect(result.required).toBe(false);
  });

  it('accepts native boolean values from serialized config', () => {
    const result = publicAuthenticationSchema.parse({
      enabled: true,
      signup: false,
      signin: true,
      autoverify: false,
      required: true,
    });

    expect(result.enabled).toBe(true);
    expect(result.signup).toBe(false);
    expect(result.signin).toBe(true);
    expect(result.autoverify).toBe(false);
    expect(result.required).toBe(true);
  });

  it('accepts optional mode field', () => {
    const result = publicAuthenticationSchema.parse({
      enabled: true,
      signup: true,
      signin: true,
      autoverify: false,
      required: false,
      mode: 'full',
    });

    expect(result.mode).toBe('full');
  });

  it('validates mode enum values', () => {
    expect(() =>
      publicAuthenticationSchema.parse({
        enabled: true,
        signup: true,
        signin: true,
        autoverify: false,
        required: false,
        mode: 'invalid' as any,
      })
    ).toThrow();
  });

  it('accepts simple mode', () => {
    const result = publicAuthenticationSchema.parse({
      enabled: true,
      signup: false,
      signin: true,
      autoverify: true,
      required: false,
      mode: 'simple',
    });

    expect(result.mode).toBe('simple');
  });
});
