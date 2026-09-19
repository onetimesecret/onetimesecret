// src/tests/schemas/api/internal/colonel-domains.spec.ts

import {
  colonelDomainVerifyDetailsSchema,
  colonelDomainVerifyResponseSchema,
} from '@/schemas/api/internal/responses/colonel-domains';
import { describe, expect, it } from 'vitest';

const record = {
  domain_id: 'cd1',
  extid: 'cd_abc123',
  display_domain: 'secrets.example.com',
  verification_state: 'verified',
  verified: true,
  resolving: true,
  ready: true,
  updated: 1700009999,
};

const details = (overrides: Record<string, unknown> = {}) => ({
  previous_state: 'verified',
  current_state: 'verified',
  changed: false,
  dns_validated: false,
  dns_indeterminate: true,
  dns_outcome: 'indeterminate',
  dns_message: 'DNS lookup timed out',
  ssl_ready: null,
  is_resolving: null,
  error: null,
  message: 'Domain verification completed',
  ...overrides,
});

describe('colonelDomainVerifyDetailsSchema', () => {
  // The status check is three-valued: the backend sends null when it could not
  // tell (failed status call, probe timeout, Approximated UNKNOWN).
  it('accepts null for ssl_ready and is_resolving and keeps it null', () => {
    const parsed = colonelDomainVerifyDetailsSchema.parse(details());

    expect(parsed.ssl_ready).toBeNull();
    expect(parsed.is_resolving).toBeNull();
  });

  it.each([
    [true, true],
    [false, false],
    [true, null],
    [null, false],
  ])('keeps is_resolving=%s ssl_ready=%s apart', (is_resolving, ssl_ready) => {
    const parsed = colonelDomainVerifyDetailsSchema.parse(details({ is_resolving, ssl_ready }));

    expect(parsed.is_resolving).toBe(is_resolving);
    expect(parsed.ssl_ready).toBe(ssl_ready);
  });

  it('still requires both keys: absent is a contract break, not "unknown"', () => {
    const { ssl_ready: _ssl, ...withoutSsl } = details();
    const { is_resolving: _res, ...withoutResolving } = details();

    expect(colonelDomainVerifyDetailsSchema.safeParse(withoutSsl).success).toBe(false);
    expect(colonelDomainVerifyDetailsSchema.safeParse(withoutResolving).success).toBe(false);
  });

  it('does not accept string booleans', () => {
    expect(colonelDomainVerifyDetailsSchema.safeParse(details({ ssl_ready: 'null' })).success).toBe(
      false
    );
    expect(
      colonelDomainVerifyDetailsSchema.safeParse(details({ is_resolving: 'false' })).success
    ).toBe(false);
  });

  it('accepts the confirmation_expired outcome', () => {
    const parsed = colonelDomainVerifyDetailsSchema.parse(
      details({ current_state: 'resolving', changed: true, dns_outcome: 'confirmation_expired' })
    );

    expect(parsed.dns_outcome).toBe('confirmation_expired');
  });
});

describe('colonelDomainVerifyResponseSchema', () => {
  it('parses an unknown-status verify response', () => {
    const result = colonelDomainVerifyResponseSchema.safeParse({
      shrimp: '',
      record,
      details: details(),
    });

    expect(result.success).toBe(true);
  });

  // record.resolving is the stored, last known answer. It stays boolean.
  it('keeps record.resolving a plain boolean', () => {
    const result = colonelDomainVerifyResponseSchema.safeParse({
      shrimp: '',
      record: { ...record, resolving: null },
      details: details(),
    });

    expect(result.success).toBe(false);
  });
});
