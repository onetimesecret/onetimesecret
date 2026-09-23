// src/tests/contracts/bootstrap-wire-contract.spec.ts
//
// The bootstrap contract against RECORDED server bodies (#4458, #4463).
//
// Every other bootstrap test builds its payload in TypeScript, so a schema
// that disagrees with the server still passes them all. That is how the
// branch reached its first browser run with a contract no real payload
// satisfied: 9 paths failed for an anonymous visitor and 11 for a signed-in
// one, every page load fell back to GET /bootstrap/me, that failed the same
// way, and every user ended in `unavailable`.
//
// The fixtures in src/tests/fixtures/wire/ are bodies captured from a running
// server (full auth mode, the e2e-full-auth lane env) with only the CSRF
// token, nonce, Sentry DSN and email address replaced. Re-record them when a
// serializer changes shape; do not hand-edit them into agreement.
//
//   anonymous      hydration of GET / with no session
//   authenticated  GET /bootstrap/me with a verified, signed-in account
//   mfa-pending    GET /bootstrap/me between password and TOTP

import { describe, expect, it } from 'vitest';

import {
  bootstrapSchema,
  effectiveAuthStatus,
  withoutWireNulls,
} from '@/schemas/contracts/bootstrap';
import { parseCompleteSnapshot } from '@/utils/snapshotOrdering';

import anonymous from '../fixtures/wire/bootstrap-anonymous.json';
import authenticated from '../fixtures/wire/bootstrap-authenticated.json';
import mfaPending from '../fixtures/wire/bootstrap-mfa-pending.json';

const recordings = { anonymous, authenticated, 'mfa-pending': mfaPending } as const;

function accepted(wire: unknown) {
  const parsed = parseCompleteSnapshot(wire);
  // Paths only: a failure here must say WHICH key disagrees with the server.
  expect(parsed.ok ? [] : parsed.invalidPaths).toEqual([]);
  if (!parsed.ok) throw new Error('unreachable');
  return parsed;
}

describe('recorded server payloads satisfy the bootstrap contract', () => {
  it.each(Object.entries(recordings))('%s is accepted whole', (_name, wire) => {
    const parsed = accepted(wire);
    expect(parsed.pairMalformed).toBe(false);
  });

  it('reads each recording as the status the server stated', () => {
    expect(effectiveAuthStatus(accepted(anonymous).payload)).toBe('anonymous');
    expect(effectiveAuthStatus(accepted(authenticated).payload)).toBe('authenticated');
    expect(effectiveAuthStatus(accepted(mfaPending).payload)).toBe('mfa_pending');
  });

  it('orders exactly the payloads that report a session', () => {
    expect(accepted(anonymous).payload.snapshot_version).toBeUndefined();
    expect(accepted(authenticated).payload.snapshot_version).toMatch(/^[1-9][0-9]*$/);
    expect(accepted(mfaPending).payload.snapshot_version).toMatch(/^[1-9][0-9]*$/);
  });

  it('carries no account data before the second factor', () => {
    const { payload } = accepted(mfaPending);
    expect(payload.cust).toBeNull();
    expect(payload.custid).toBe('');
    expect(payload.email).toBe('');
  });
});

describe('the customer wire encoding (cust.safe_dump)', () => {
  const wire = authenticated.cust;
  const { payload } = accepted(authenticated);

  it('timestamps arrive as fractional epoch seconds and leave as Dates', () => {
    expect(typeof wire.created).toBe('number');
    expect(Number.isInteger(wire.created)).toBe(false);
    expect(payload.cust?.created).toEqual(new Date(wire.created * 1000));
    expect(payload.cust?.updated).toBeInstanceOf(Date);
    expect(payload.cust?.last_login).toBeInstanceOf(Date);
  });

  it('counters arrive as decimal strings and leave as numbers', () => {
    expect(typeof wire.secrets_created).toBe('string');
    expect(payload.cust?.secrets_created).toBe(Number(wire.secrets_created));
    expect(payload.cust?.emails_sent).toBe(Number(wire.emails_sent));
  });

  it('feature_flags is not a safe_dump field and defaults to none', () => {
    expect(wire).not.toHaveProperty('feature_flags');
    expect(payload.cust?.feature_flags).toEqual({});
  });

  it('a counter that is not a whole number is a contract failure', () => {
    const tampered = { ...authenticated, cust: { ...wire, secrets_created: '1e3' } };
    const parsed = parseCompleteSnapshot(tampered);
    expect(parsed.ok ? [] : parsed.invalidPaths).toEqual(['cust.secrets_created']);
  });

  it('parsing an accepted snapshot again changes nothing', () => {
    expect(bootstrapSchema.parse(payload)).toEqual(payload);
  });
});

describe('wire nulls (serializer output_template seeds nil for every key)', () => {
  it('the recordings really contain nulls the schema has no null for', () => {
    // Guards the premise: if the server stops sending these, this file is
    // no longer evidence for the rule below and should be re-recorded.
    expect(anonymous.custid).toBeNull();
    expect(anonymous.support_email).toBeNull();
    expect(bootstrapSchema.safeParse(anonymous).success).toBe(false);
  });

  it('such a null reads as the schema default', () => {
    const { payload } = accepted(anonymous);
    expect(payload.custid).toBe('');
    expect(payload.support_email).toBe('');
    expect(payload.custom_domains).toEqual([]);
    expect(payload.domains).toBeUndefined();
  });

  it('a null the schema accepts stays a null', () => {
    const normalized = withoutWireNulls(anonymous) as Record<string, unknown>;
    expect(normalized).toHaveProperty('cust', null);
    expect(normalized).toHaveProperty('organization', null);
    expect(normalized).not.toHaveProperty('custid');
  });

  it('never adds a key or changes a value', () => {
    const normalized = withoutWireNulls(authenticated) as Record<string, unknown>;
    for (const [key, value] of Object.entries(normalized)) {
      expect(value).toBe((authenticated as Record<string, unknown>)[key]);
    }
  });

  it('cannot turn an unstated status into a session', () => {
    const silent = { ...anonymous, auth_status: null, authenticated: null, awaiting_mfa: null };
    expect(effectiveAuthStatus(accepted(silent).payload)).toBe('anonymous');
  });

  it.each([null, undefined, 'text', 3, []])('passes %j through untouched', (input) => {
    expect(withoutWireNulls(input)).toBe(input);
  });
});

describe('fields whose declared type disagreed with the server', () => {
  it('fallback_locale is the config map of fallback chains', () => {
    const { payload } = accepted(anonymous);
    expect(payload.fallback_locale).toEqual(anonymous.fallback_locale);
    expect(bootstrapSchema.parse({}).fallback_locale).toBe('en');
  });

  it('regions carries no top-level identifier', () => {
    expect(anonymous.regions).not.toHaveProperty('identifier');
    expect(accepted(anonymous).payload.regions?.jurisdictions.length).toBeGreaterThan(0);
  });
});
