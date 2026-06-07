// src/tests/schemas/shapes/config/public.spec.ts
//
// Tests for publicSecretOptionsShape covering the default values and value
// bounds that were stripped from the type-only contract in
// `contracts/config/public.ts`.

import { describe, it, expect } from 'vitest';
import { publicSecretOptionsShape } from '@/schemas/shapes/config/public';

describe('publicSecretOptionsShape (defaults)', () => {
  it('applies default TTL of 7 days (604800 seconds)', () => {
    const result = publicSecretOptionsShape.parse({});
    expect(result.default_ttl).toBe(604800);
  });

  it('applies the canonical ttl_options list', () => {
    const result = publicSecretOptionsShape.parse({});
    expect(result.ttl_options).toEqual([
      300, 1800, 3600, 14400, 43200, 86400, 259200, 604800, 1209600, 2592000,
    ]);
  });

  it('leaves nested passphrase / password_generation undefined when omitted', () => {
    const result = publicSecretOptionsShape.parse({});
    expect(result.passphrase).toBeUndefined();
    expect(result.password_generation).toBeUndefined();
  });

  it('applies passphrase defaults when a partial object is provided', () => {
    const result = publicSecretOptionsShape.parse({
      passphrase: { required: true },
    });

    expect(result.passphrase?.required).toBe(true);
    expect(result.passphrase?.minimum_length).toBe(4);
    expect(result.passphrase?.maximum_length).toBe(128);
    expect(result.passphrase?.enforce_complexity).toBe(false);
  });

  it('applies password_generation defaults when present but empty', () => {
    const result = publicSecretOptionsShape.parse({ password_generation: {} });

    expect(result.password_generation?.default_length).toBe(12);
    expect(result.password_generation?.length_options).toEqual([8, 12, 16, 20, 24, 32]);
  });
});

describe('publicSecretOptionsShape (TTL bounds)', () => {
  it('enforces minimum TTL of 60 seconds in options', () => {
    expect(() => publicSecretOptionsShape.parse({ ttl_options: [30] })).toThrow();
  });

  it('enforces maximum TTL of 30 days (2592000 seconds) in options', () => {
    expect(() => publicSecretOptionsShape.parse({ ttl_options: [3000000] })).toThrow();
  });

  it('accepts boundary TTL values', () => {
    const result = publicSecretOptionsShape.parse({ ttl_options: [60, 2592000] });
    expect(result.ttl_options).toEqual([60, 2592000]);
  });
});

describe('publicSecretOptionsShape (passphrase bounds)', () => {
  it('accepts zero for minimum_length (no enforcement)', () => {
    const result = publicSecretOptionsShape.parse({ passphrase: { minimum_length: 0 } });
    expect(result.passphrase?.minimum_length).toBe(0);
  });

  it('enforces maximum passphrase minimum_length of 256', () => {
    expect(() =>
      publicSecretOptionsShape.parse({ passphrase: { minimum_length: 300 } })
    ).toThrow();
  });

  it('enforces maximum passphrase maximum_length of 1024', () => {
    expect(() =>
      publicSecretOptionsShape.parse({ passphrase: { maximum_length: 2000 } })
    ).toThrow();
  });
});

describe('publicSecretOptionsShape (password generation bounds)', () => {
  it('enforces password length minimum of 4', () => {
    expect(() =>
      publicSecretOptionsShape.parse({ password_generation: { default_length: 2 } })
    ).toThrow();
  });

  it('enforces password length maximum of 128', () => {
    expect(() =>
      publicSecretOptionsShape.parse({ password_generation: { default_length: 256 } })
    ).toThrow();
  });
});
