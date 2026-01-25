// src/tests/schemas/models/public.spec.ts

//
// Tests for publicSecretOptionsSchema covering various configurations
// that may be encountered from different deployment environments.

import { describe, it, expect } from 'vitest';
import {
  publicSecretOptionsSchema,
  publicAuthenticationSchema,
  type SecretOptions,
} from '@/schemas/models/public';

describe('publicSecretOptionsSchema', () => {
  describe('default values', () => {
    it('parses empty object with all defaults', () => {
      const result = publicSecretOptionsSchema.parse({});

      expect(result.default_ttl).toBe(604800); // 7 days
      expect(result.ttl_options).toEqual([
        300, 1800, 3600, 14400, 43200, 86400, 259200, 604800, 1209600, 2592000,
      ]);
      expect(result.passphrase).toBeUndefined();
      expect(result.password_generation).toBeUndefined();
    });

    it('applies default TTL of 7 days (604800 seconds)', () => {
      const result = publicSecretOptionsSchema.parse({});
      expect(result.default_ttl).toBe(604800);
    });
  });

  describe('TTL configuration', () => {
    it('accepts custom default_ttl', () => {
      const result = publicSecretOptionsSchema.parse({
        default_ttl: 86400, // 1 day
      });
      expect(result.default_ttl).toBe(86400);
    });

    it('accepts custom ttl_options array', () => {
      const customOptions = [300, 3600, 86400];
      const result = publicSecretOptionsSchema.parse({
        ttl_options: customOptions,
      });
      expect(result.ttl_options).toEqual(customOptions);
    });

    it('enforces minimum TTL of 60 seconds in options', () => {
      expect(() =>
        publicSecretOptionsSchema.parse({
          ttl_options: [30], // Below minimum
        })
      ).toThrow();
    });

    it('enforces maximum TTL of 30 days (2592000 seconds) in options', () => {
      expect(() =>
        publicSecretOptionsSchema.parse({
          ttl_options: [3000000], // Above maximum
        })
      ).toThrow();
    });

    it('accepts boundary TTL values', () => {
      const result = publicSecretOptionsSchema.parse({
        ttl_options: [60, 2592000], // Min and max allowed
      });
      expect(result.ttl_options).toEqual([60, 2592000]);
    });
  });

  describe('passphrase configuration', () => {
    it('accepts passphrase settings object', () => {
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

    it('applies passphrase defaults when partial object provided', () => {
      const result = publicSecretOptionsSchema.parse({
        passphrase: {
          required: true,
        },
      });

      expect(result.passphrase?.required).toBe(true);
      expect(result.passphrase?.minimum_length).toBe(8); // default
      expect(result.passphrase?.maximum_length).toBe(128); // default
      expect(result.passphrase?.enforce_complexity).toBe(false); // default
    });

    it('handles string boolean for required field (fromString transform)', () => {
      const result = publicSecretOptionsSchema.parse({
        passphrase: {
          required: 'true' as unknown as boolean,
        },
      });

      expect(result.passphrase?.required).toBe(true);
    });

    it('enforces minimum passphrase length constraints', () => {
      expect(() =>
        publicSecretOptionsSchema.parse({
          passphrase: {
            minimum_length: 0, // Below minimum of 1
          },
        })
      ).toThrow();
    });

    it('enforces maximum passphrase length constraints', () => {
      expect(() =>
        publicSecretOptionsSchema.parse({
          passphrase: {
            maximum_length: 2000, // Above maximum of 1024
          },
        })
      ).toThrow();
    });
  });

  describe('password generation configuration', () => {
    it('accepts password generation settings', () => {
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

    it('applies password generation defaults', () => {
      const result = publicSecretOptionsSchema.parse({
        password_generation: {},
      });

      expect(result.password_generation?.default_length).toBe(12);
      expect(result.password_generation?.length_options).toEqual([8, 12, 16, 20, 24, 32]);
    });

    it('enforces password length minimum of 4', () => {
      expect(() =>
        publicSecretOptionsSchema.parse({
          password_generation: {
            default_length: 2,
          },
        })
      ).toThrow();
    });

    it('enforces password length maximum of 128', () => {
      expect(() =>
        publicSecretOptionsSchema.parse({
          password_generation: {
            default_length: 256,
          },
        })
      ).toThrow();
    });
  });

  describe('full configuration scenarios', () => {
    it('parses production-like configuration', () => {
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

    it('parses high-security configuration', () => {
      const securityConfig = {
        default_ttl: 3600, // 1 hour max
        ttl_options: [300, 1800, 3600],
        passphrase: {
          required: true,
          minimum_length: 16,
          maximum_length: 256,
          enforce_complexity: true,
        },
      };

      const result = publicSecretOptionsSchema.parse(securityConfig);
      expect(result.passphrase?.required).toBe(true);
      expect(result.passphrase?.minimum_length).toBe(16);
    });

    it('parses minimal self-hosted configuration', () => {
      const minimalConfig = {
        default_ttl: 86400,
        ttl_options: [86400],
      };

      const result = publicSecretOptionsSchema.parse(minimalConfig);
      expect(result.default_ttl).toBe(86400);
      expect(result.ttl_options).toEqual([86400]);
    });
  });

  describe('type inference', () => {
    it('infers correct TypeScript type', () => {
      const config: SecretOptions = publicSecretOptionsSchema.parse({});

      // Type assertions - these would fail compilation if types are wrong
      const _ttl: number = config.default_ttl;
      const _options: number[] = config.ttl_options;

      expect(_ttl).toBeDefined();
      expect(_options).toBeDefined();
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

  it('handles string booleans from environment variables', () => {
    const result = publicAuthenticationSchema.parse({
      enabled: 'true' as unknown as boolean,
      signup: 'false' as unknown as boolean,
      signin: 'true' as unknown as boolean,
      autoverify: 'false' as unknown as boolean,
      required: 'true' as unknown as boolean,
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
