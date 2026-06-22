// src/tests/schemas/shapes/config/site.spec.ts
//
// Coverage for the site shape — the top-level fields plus the eight
// nested sub-trees (authentication, session, middleware, security/csp,
// passphrase, password_generation, siteSecretOptions). The `passphrase`
// minimum_length bounds (0..256) and the password generation length
// defaults are the load-bearing pieces consumers rely on; the rest is
// boolean default coverage.

import { describe, it, expect } from 'vitest';
import {
  siteSchema,
  siteAuthenticationSchema,
  sessionConfigSchema,
} from '@/schemas/contracts/config/section/site';
import {
  siteShape,
  siteAuthenticationShape,
  siteSecretOptionsShape,
  passphraseShape,
  passwordGenerationShape,
  sessionConfigShape,
  middlewareShape,
  securityShape,
  cspShape,
} from '@/schemas/shapes/config/section/site';

describe('siteShape — top-level defaults', () => {
  it('fills host and ssl on empty input', () => {
    const result = siteShape.parse({});
    expect(result.host).toBe('localhost:3000');
    expect(result.ssl).toBe(false);
  });

  it('contract leaves host/ssl undefined', () => {
    const c = siteSchema.parse({});
    expect(c.host).toBeUndefined();
    expect(c.ssl).toBeUndefined();
  });
});

describe('siteAuthenticationShape — defaults', () => {
  it('applies signup/signin/required/etc. defaults', () => {
    const result = siteAuthenticationShape.parse({});
    expect(result.enabled).toBe(true);
    expect(result.signup).toBe(true);
    expect(result.signin).toBe(true);
    expect(result.autoverify).toBe(false);
    expect(result.required).toBe(false);
    expect(result.colonels).toEqual([]);
    expect(result.allowed_signup_domains).toEqual([]);
  });

  it('contract leaves these fields undefined', () => {
    const c = siteAuthenticationSchema.parse({});
    expect(c.enabled).toBeUndefined();
    expect(c.colonels).toBeUndefined();
  });
});

describe('sessionConfigShape — defaults and bounds', () => {
  it('fills expire_after, key, secure, same_site, httponly', () => {
    const result = sessionConfigShape.parse({});
    expect(result.expire_after).toBe(86400);
    expect(result.key).toBe('onetime.session');
    expect(result.secure).toBe(true);
    expect(result.same_site).toBe('lax');
    expect(result.httponly).toBe(true);
  });

  it('rejects non-positive expire_after on the shape', () => {
    expect(() => sessionConfigShape.parse({ expire_after: 0 })).toThrow();
    expect(() => sessionConfigShape.parse({ expire_after: -10 })).toThrow();
  });

  it('rejects non-integer expire_after on the shape', () => {
    expect(() => sessionConfigShape.parse({ expire_after: 86400.5 })).toThrow();
  });

  it('contract accepts the same bad expire_after values', () => {
    expect(() => sessionConfigSchema.parse({ expire_after: -1 })).not.toThrow();
  });

  it('rejects same_site values outside the enum', () => {
    expect(() => sessionConfigShape.parse({ same_site: 'wide' })).toThrow();
  });
});

describe('cspShape / securityShape', () => {
  it('csp.enabled defaults to true (staged report-only)', () => {
    expect(cspShape.parse({}).enabled).toBe(true);
    expect(cspShape.parse({}).report_only).toBe(true);
    expect(cspShape.parse({}).report_uri).toBe(null);
  });

  it('security composes csp', () => {
    expect(securityShape.parse({ csp: {} }).csp?.enabled).toBe(true);
  });
});

describe('middlewareShape — defaults', () => {
  it('fills every middleware toggle', () => {
    const result = middlewareShape.parse({});
    expect(result.static_files).toBe(true);
    expect(result.utf8_sanitizer).toBe(true);
    expect(result.authenticity_token).toBe(true);
    expect(result.http_origin).toBe(true);
    expect(result.xss_header).toBe(true);
    expect(result.frame_options).toBe(true);
    expect(result.path_traversal).toBe(false);
    expect(result.cookie_tossing).toBe(false);
    expect(result.ip_spoofing).toBe(false);
    // Effective value tracks SSL server-side; false is the client fallback.
    expect(result.strict_transport).toBe(false);
  });
});

describe('passphraseShape — defaults and bounds', () => {
  it('fills required, minimum_length, maximum_length, enforce_complexity', () => {
    const result = passphraseShape.parse({});
    expect(result.required).toBe(false);
    expect(result.minimum_length).toBe(4);
    expect(result.maximum_length).toBe(128);
    expect(result.enforce_complexity).toBe(false);
  });

  it('accepts minimum_length = 0 (no enforcement)', () => {
    expect(passphraseShape.parse({ minimum_length: 0 }).minimum_length).toBe(0);
  });

  it('accepts minimum_length = 256 (upper bound)', () => {
    expect(passphraseShape.parse({ minimum_length: 256 }).minimum_length).toBe(256);
  });

  it('rejects minimum_length > 256', () => {
    expect(() => passphraseShape.parse({ minimum_length: 257 })).toThrow();
  });

  it('rejects negative minimum_length', () => {
    expect(() => passphraseShape.parse({ minimum_length: -1 })).toThrow();
  });

  it('rejects non-positive maximum_length', () => {
    expect(() => passphraseShape.parse({ maximum_length: 0 })).toThrow();
  });
});

describe('passwordGenerationShape — defaults', () => {
  it('fills default_length and character_sets defaults', () => {
    const result = passwordGenerationShape.parse({ character_sets: {} });
    expect(result.default_length).toBe(12);
    expect(result.character_sets.uppercase).toBe(true);
    expect(result.character_sets.lowercase).toBe(true);
    expect(result.character_sets.numbers).toBe(true);
    expect(result.character_sets.symbols).toBe(true);
    expect(result.character_sets.exclude_ambiguous).toBe(true);
  });

  it('rejects non-positive default_length', () => {
    expect(() =>
      passwordGenerationShape.parse({ default_length: 0, character_sets: {} })
    ).toThrow();
  });
});

describe('siteSecretOptionsShape — bounds (no defaults at this level)', () => {
  // siteSecretOptionsSchema requires `passphrase` and `password_generation`
  // (they are NOT `.optional()` on the contract); every parse below supplies
  // both as `character_sets: {}` to satisfy the nested character-set object.
  const passphrase = {};
  const password_generation = { character_sets: {} };

  it('rejects negative generated_value_display_ttl', () => {
    expect(() =>
      siteSecretOptionsShape.parse({
        generated_value_display_ttl: -1,
        passphrase,
        password_generation,
      })
    ).toThrow();
  });

  it('accepts zero generated_value_display_ttl (nonnegative)', () => {
    const result = siteSecretOptionsShape.parse({
      generated_value_display_ttl: 0,
      passphrase,
      password_generation,
    });
    expect(result.generated_value_display_ttl).toBe(0);
  });

  it('preserves nullable default_ttl', () => {
    const result = siteSecretOptionsShape.parse({
      default_ttl: null,
      passphrase,
      password_generation,
    });
    expect(result.default_ttl).toBeNull();
  });

  it('applies nested passphrase defaults when caller supplies empty object', () => {
    const result = siteSecretOptionsShape.parse({ passphrase, password_generation });
    expect(result.passphrase?.minimum_length).toBe(4);
    expect(result.passphrase?.maximum_length).toBe(128);
  });
});

describe('siteShape — composed sub-trees', () => {
  it('applies authentication / session / middleware defaults end-to-end', () => {
    const result = siteShape.parse({
      authentication: {},
      session: {},
      middleware: {},
      security: { csp: {} },
    });
    expect(result.authentication?.signup).toBe(true);
    expect(result.session?.expire_after).toBe(86400);
    expect(result.middleware?.static_files).toBe(true);
    expect(result.security?.csp?.enabled).toBe(true);
  });
});
