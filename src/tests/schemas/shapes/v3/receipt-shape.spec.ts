// src/tests/schemas/shapes/v3/receipt-shape.spec.ts
//
// V3-only receipt wire-shape guarantees (2026-07-29 API audit, items 5 and 7).
//
// V2 is frozen on the shared safe_dump shape (comma-joined `recipients` string,
// deprecated `custid`). V3 is pre-release, so it normalizes both:
//
//   recipients  always string[] or null — never a string, never undefined
//   custid      absent from the parsed record entirely
//
// The server-side half lives in apps/api/v3/logic/receipt_shape.rb; this file
// pins the frontend contract that consumes it.

import {
  receiptBaseSchema,
  receiptListSchema,
  receiptSchema,
} from '@/schemas/shapes/v3/receipt';
import { describe, expect, it } from 'vitest';

/** Minimal payload satisfying receiptBaseSchema's required fields. */
const baseWire = (overrides: Record<string, unknown> = {}) => ({
  identifier: 'abc123def456',
  key: 'abc123def456',
  shortid: 'abc12345',
  state: 'new',
  owner_id: 'ur_abc123',
  created: 1_735_142_814,
  updated: 1_735_204_014,
  shared: null,
  previewed: null,
  revealed: null,
  burned: null,
  secret_ttl: 3600,
  receipt_ttl: 7200,
  lifespan: 7200,
  is_previewed: false,
  is_revealed: false,
  is_burned: false,
  is_destroyed: false,
  is_expired: false,
  is_orphaned: false,
  ...overrides,
});

const listWire = (overrides: Record<string, unknown> = {}) =>
  baseWire({ show_recipients: false, ...overrides });

const fullWire = (overrides: Record<string, unknown> = {}) =>
  baseWire({
    natural_expiration: '2 hours',
    expiration: 1_735_211_214,
    expiration_in_seconds: 7200,
    share_path: '/secret/abc',
    burn_path: '/receipt/abc/burn',
    receipt_path: '/receipt/abc',
    share_url: 'https://example.com/secret/abc',
    receipt_url: 'https://example.com/receipt/abc',
    burn_url: 'https://example.com/receipt/abc/burn',
    ...overrides,
  });

describe('V3 receipt shape: recipients is null-or-array', () => {
  it('parses the normalized array form', () => {
    const parsed = receiptBaseSchema.parse(
      baseWire({ recipients: ['a***@e***.com', 'b***@f***.com'] })
    );

    expect(parsed.recipients).toEqual(['a***@e***.com', 'b***@f***.com']);
  });

  it('parses null as null', () => {
    expect(receiptBaseSchema.parse(baseWire({ recipients: null })).recipients).toBeNull();
  });

  // Every real V3 receipt carries the key (safe_dump always emits it); an
  // absent key means a partial/synthetic record and is left absent rather than
  // materialized as null.
  it('leaves an absent field absent', () => {
    expect(Object.keys(receiptBaseSchema.parse(baseWire()))).not.toContain('recipients');
  });

  it('emits null for an empty array', () => {
    expect(receiptBaseSchema.parse(baseWire({ recipients: [] })).recipients).toBeNull();
  });

  // Read tolerance only: the V2 wire form. The backend normalizer strips this
  // before it reaches a V3 client, but recipients is display-only, so rejecting
  // it here would null the whole receipt (#3424).
  it('coerces the legacy comma-joined string into an array', () => {
    const parsed = receiptBaseSchema.parse(
      baseWire({ recipients: 'a***@e***.com, b***@f***.com' })
    );

    expect(parsed.recipients).toEqual(['a***@e***.com', 'b***@f***.com']);
  });

  it('coerces an empty legacy string to null', () => {
    expect(receiptBaseSchema.parse(baseWire({ recipients: '' })).recipients).toBeNull();
  });

  it('applies to the list and full receipt shapes too', () => {
    expect(receiptListSchema.parse(listWire({ recipients: 'solo@example.com' })).recipients).toEqual(
      ['solo@example.com']
    );
    expect(receiptSchema.parse(fullWire({ recipients: '' })).recipients).toBeNull();
  });
});

describe('V3 receipt shape: custid is dropped', () => {
  it('strips custid from the base record even when the server sends it', () => {
    const parsed = receiptBaseSchema.parse(baseWire({ custid: 'cust:user@example.com' }));

    expect(Object.keys(parsed)).not.toContain('custid');
  });

  it('strips custid from the list and full receipt shapes', () => {
    expect(
      Object.keys(receiptListSchema.parse(listWire({ custid: 'cust:user@example.com' })))
    ).not.toContain('custid');
    expect(
      Object.keys(receiptSchema.parse(fullWire({ custid: 'cust:user@example.com' })))
    ).not.toContain('custid');
  });

  it('keeps owner_id, the canonical creator identifier', () => {
    expect(receiptBaseSchema.parse(baseWire()).owner_id).toBe('ur_abc123');
  });
});
