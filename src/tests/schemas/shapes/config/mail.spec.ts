// src/tests/schemas/shapes/config/mail.spec.ts
//
// Coverage for the mail shape — emailer (SMTP) defaults and port bounds,
// truemail validation defaults, the static mailConnection block, and the
// static mailValidation block.

import { describe, it, expect } from 'vitest';
import {
  emailerSchema,
  truemailSchema,
  mailConnectionSchema,
  mailValidationSchema,
} from '@/schemas/contracts/config/section/mail';
import {
  emailerShape,
  mailShape,
  truemailShape,
  mailConnectionShape,
  mailValidationShape,
} from '@/schemas/shapes/config/section/mail';

describe('emailerShape — SMTP defaults and bounds', () => {
  it('fills every documented default on empty input', () => {
    const result = emailerShape.parse({});
    expect(result.mode).toBe('smtp');
    expect(result.from).toBe('CHANGEME@example.com');
    expect(result.from_name).toBe('Support');
    expect(result.host).toBe('smtp.provider.com');
    expect(result.port).toBe(587);
  });

  it.each([
    ['zero', 0],
    ['negative', -25],
    ['non-integer', 25.5],
  ])('rejects %s port on the shape', (_label, value) => {
    expect(() => emailerShape.parse({ port: value })).toThrow();
  });

  it('contract accepts the bad port values the shape rejects', () => {
    expect(() => emailerSchema.parse({ port: 0 })).not.toThrow();
    expect(() => emailerSchema.parse({ port: -25 })).not.toThrow();
  });
});

describe('truemailShape — defaults and bounds', () => {
  it('fills every documented default on empty input', () => {
    const result = truemailShape.parse({});
    expect(result.default_validation_type).toBe(':regex');
    expect(result.verifier_email).toBe('CHANGEME@example.com');
    expect(result.allowed_domains_only).toBe(false);
    expect(result.dns).toEqual(['1.1.1.1', '8.8.4.4', '208.67.220.220']);
    expect(result.smtp_port).toBeUndefined();
    expect(result.smtp_fail_fast).toBe(false);
    expect(result.smtp_safe_check).toBe(true);
    expect(result.not_rfc_mx_lookup_flow).toBe(false);
  });

  it('logger sub-tree defaults are applied', () => {
    const result = truemailShape.parse({ logger: {} });
    expect(result.logger?.tracking_event).toBe(':error');
    expect(result.logger?.stdout).toBe(true);
  });

  it('rejects non-positive smtp_port on the shape', () => {
    expect(() => truemailShape.parse({ smtp_port: 0 })).toThrow();
  });

  it('contract leaves smtp_safe_check undefined', () => {
    expect(truemailSchema.parse({}).smtp_safe_check).toBeUndefined();
  });
});

describe('mailShape — composed', () => {
  it('applies truemail sub-tree defaults when nested', () => {
    const result = mailShape.parse({ truemail: { logger: {} } });
    expect(result.truemail?.verifier_email).toBe('CHANGEME@example.com');
    expect(result.truemail?.logger?.stdout).toBe(true);
  });
});

describe('mailConnectionShape — defaults', () => {
  it('fills every documented default on empty input', () => {
    const result = mailConnectionShape.parse({});
    expect(result.mode).toBe('smtp');
    expect(result.auth).toBe('login');
    expect(result.from).toBe('noreply@example.com');
    expect(result.fromname).toBe('OneTimeSecret');
  });

  it('contract leaves auth undefined', () => {
    expect(mailConnectionSchema.parse({}).auth).toBeUndefined();
  });
});

describe('mailValidationShape — defaults', () => {
  it('fills every documented default on empty input', () => {
    const result = mailValidationShape.parse({});
    expect(result.default_validation_type).toBe('mx');
    expect(result.verifier_email).toBe('example@onetimesecret.dev');
    expect(result.verifier_domain).toBe('onetimesecret.dev');
  });

  it('logger sub-tree defaults are applied', () => {
    const result = mailValidationShape.parse({ logger: {} });
    expect(result.logger?.tracking_event).toBe('all');
    expect(result.logger?.stdout).toBe(true);
  });

  it('contract leaves verifier_email undefined', () => {
    expect(mailValidationSchema.parse({}).verifier_email).toBeUndefined();
  });
});
