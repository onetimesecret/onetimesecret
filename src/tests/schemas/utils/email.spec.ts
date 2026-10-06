// src/tests/schemas/utils/email.spec.ts

import { WIRE_EMAIL_PATTERN, wireEmailSchema } from '@/schemas/utils/email';
import { describe, expect, it } from 'vitest';

/**
 * wireEmailSchema sits on READ contracts (customer, member, invitation). It
 * must accept every address the server stores, otherwise hydration of that
 * account fails and the SPA never reaches the authenticated state. The
 * pattern mirrors Onetime::SignupValidation::VALID_EMAIL_PATTERN.
 */
describe('wireEmailSchema', () => {
  it('accepts the addresses Zod\'s default pattern rejects but the server stores', () => {
    const serverAccepted = [
      'first&last@company.com',
      "o'neil@example.com",
      'josé@example.com',
      'a!b#c$d%e*f=g?h^i`j{k|l}m~n@example.com',
      'user+tag@sub.example.co.uk',
      'UPPER.case@Example.COM',
    ];

    for (const email of serverAccepted) {
      expect(wireEmailSchema.safeParse(email).success, email).toBe(true);
    }
  });

  it('rejects what the server also rejects', () => {
    const rejected = [
      'not-an-email',
      'no-dot@localhost',
      'two@@example.com',
      'a,b@example.com',
      'a;b@example.com',
      'space here@example.com',
      'user@exam ple.com',
      'user@example.com\nX',
      '',
      '@example.com',
      'user@',
    ];

    for (const email of rejected) {
      expect(wireEmailSchema.safeParse(email).success, email).toBe(false);
    }
  });

  it('is anchored to the whole string', () => {
    // No multiline flag: a trailing line must not slip past `$`.
    expect(WIRE_EMAIL_PATTERN.test('user@example.com\n<script>')).toBe(false);
    expect(WIRE_EMAIL_PATTERN.flags).not.toContain('m');
  });
});
