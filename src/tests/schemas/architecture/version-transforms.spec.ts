// src/tests/schemas/architecture/version-transforms.spec.ts
//
// Tests that verify version-specific transforms work correctly.
// V2: string -> typed (Redis/API string encoding)
// V3: number -> Date (native JSON types)

import { describe, expect, it } from 'vitest';
import { z } from 'zod';
import { transforms } from '@/schemas/transforms';

// -----------------------------------------------------------------------------
// V2 Transform Tests (fromString)
// -----------------------------------------------------------------------------

describe('V2 Transforms (fromString)', () => {
  describe('boolean transforms', () => {
    const schema = z.object({
      verified: transforms.fromString.boolean,
      active: transforms.fromString.boolean,
    });

    it('transforms "true" string to true', () => {
      const result = schema.parse({ verified: 'true', active: 'true' });
      expect(result.verified).toBe(true);
      expect(result.active).toBe(true);
    });

    it('transforms "1" string to true', () => {
      const result = schema.parse({ verified: '1', active: '1' });
      expect(result.verified).toBe(true);
      expect(result.active).toBe(true);
    });

    it('transforms "false" string to false', () => {
      const result = schema.parse({ verified: 'false', active: 'false' });
      expect(result.verified).toBe(false);
      expect(result.active).toBe(false);
    });

    it('transforms "0" string to false', () => {
      const result = schema.parse({ verified: '0', active: '0' });
      expect(result.verified).toBe(false);
      expect(result.active).toBe(false);
    });

    it('transforms empty string to false', () => {
      const result = schema.parse({ verified: '', active: '' });
      expect(result.verified).toBe(false);
      expect(result.active).toBe(false);
    });

    it('transforms null to false', () => {
      const result = schema.parse({ verified: null, active: null });
      expect(result.verified).toBe(false);
      expect(result.active).toBe(false);
    });

    it('passes through native booleans', () => {
      const result = schema.parse({ verified: true, active: false });
      expect(result.verified).toBe(true);
      expect(result.active).toBe(false);
    });
  });

  describe('number transforms', () => {
    const schema = z.object({
      count: transforms.fromString.number,
    });

    it('transforms numeric string to number', () => {
      const result = schema.parse({ count: '42' });
      expect(result.count).toBe(42);
    });

    it('transforms "0" to 0', () => {
      const result = schema.parse({ count: '0' });
      expect(result.count).toBe(0);
    });

    it('transforms empty string to null', () => {
      const result = schema.parse({ count: '' });
      expect(result.count).toBeNull();
    });

    it('transforms non-numeric string to null', () => {
      const result = schema.parse({ count: 'abc' });
      expect(result.count).toBeNull();
    });

    it('passes through native numbers', () => {
      const result = schema.parse({ count: 42 });
      expect(result.count).toBe(42);
    });
  });

  describe('date transforms', () => {
    const schema = z.object({
      created: transforms.fromString.date,
      updated: transforms.fromString.dateNullable,
    });

    it('transforms Unix timestamp string (seconds) to Date', () => {
      const result = schema.parse({
        created: '1609459200',
        updated: '1609459200',
      });
      expect(result.created).toBeInstanceOf(Date);
      expect(result.updated).toBeInstanceOf(Date);
      expect(result.created.toISOString()).toBe('2021-01-01T00:00:00.000Z');
    });

    it('transforms Unix timestamp string (milliseconds) to Date', () => {
      const result = schema.parse({
        created: '1609459200000',
        updated: '1609459200000',
      });
      expect(result.created.toISOString()).toBe('2021-01-01T00:00:00.000Z');
    });

    it('transforms ISO date string to Date', () => {
      const result = schema.parse({
        created: '2021-01-01T00:00:00Z',
        updated: '2021-01-01T00:00:00Z',
      });
      expect(result.created).toBeInstanceOf(Date);
    });

    it('nullable date accepts null', () => {
      const result = schema.parse({
        created: '1609459200',
        updated: null,
      });
      expect(result.updated).toBeNull();
    });

    it('nullable date transforms empty string to null', () => {
      const result = schema.parse({
        created: '1609459200',
        updated: '',
      });
      expect(result.updated).toBeNull();
    });

    it('required date rejects null', () => {
      expect(() =>
        schema.parse({
          created: null,
          updated: null,
        })
      ).toThrow();
    });
  });
});

// -----------------------------------------------------------------------------
// V3 Transform Tests (fromNumber)
// -----------------------------------------------------------------------------

describe('V3 Transforms (fromNumber)', () => {
  describe('toDate (required)', () => {
    const schema = z.object({
      created: transforms.fromNumber.toDate,
    });

    it('transforms Unix epoch (seconds) to Date', () => {
      const result = schema.parse({ created: 1609459200 });
      expect(result.created).toBeInstanceOf(Date);
      expect(result.created.toISOString()).toBe('2021-01-01T00:00:00.000Z');
    });

    it('handles zero timestamp (Unix epoch)', () => {
      const result = schema.parse({ created: 0 });
      expect(result.created.toISOString()).toBe('1970-01-01T00:00:00.000Z');
    });

    it('rejects null', () => {
      expect(() => schema.parse({ created: null })).toThrow();
    });

    it('rejects undefined', () => {
      expect(() => schema.parse({})).toThrow();
    });

    it('rejects string timestamps (V3 expects numbers)', () => {
      expect(() => schema.parse({ created: '1609459200' })).toThrow();
    });
  });

  describe('toDateNullable', () => {
    const schema = z.object({
      updated: transforms.fromNumber.toDateNullable,
    });

    it('transforms Unix epoch to Date', () => {
      const result = schema.parse({ updated: 1609459200 });
      expect(result.updated).toBeInstanceOf(Date);
      expect(result.updated!.toISOString()).toBe('2021-01-01T00:00:00.000Z');
    });

    it('preserves null', () => {
      const result = schema.parse({ updated: null });
      expect(result.updated).toBeNull();
    });

    it('rejects undefined', () => {
      expect(() => schema.parse({})).toThrow();
    });
  });

  describe('toDateOptional', () => {
    const schema = z.object({
      deleted: transforms.fromNumber.toDateOptional,
    });

    it('transforms Unix epoch to Date', () => {
      const result = schema.parse({ deleted: 1609459200 });
      expect(result.deleted).toBeInstanceOf(Date);
    });

    it('preserves undefined', () => {
      const result = schema.parse({ deleted: undefined });
      expect(result.deleted).toBeUndefined();
    });

    it('allows omitted field', () => {
      const result = schema.parse({});
      expect(result.deleted).toBeUndefined();
    });

    it('rejects null', () => {
      expect(() => schema.parse({ deleted: null })).toThrow();
    });
  });

  describe('toDateNullish', () => {
    const schema = z.object({
      viewed: transforms.fromNumber.toDateNullish,
    });

    it('transforms Unix epoch to Date', () => {
      const result = schema.parse({ viewed: 1609459200 });
      expect(result.viewed).toBeInstanceOf(Date);
    });

    it('transforms null to null', () => {
      const result = schema.parse({ viewed: null });
      expect(result.viewed).toBeNull();
    });

    it('transforms undefined to null (collapses nullish)', () => {
      const result = schema.parse({ viewed: undefined });
      expect(result.viewed).toBeNull();
    });

    it('transforms omitted field to null', () => {
      const result = schema.parse({});
      expect(result.viewed).toBeNull();
    });
  });
});

// -----------------------------------------------------------------------------
// V2 vs V3 Comparison Tests
// -----------------------------------------------------------------------------

describe('V2 vs V3 Transform Comparison', () => {
  it('V2 accepts string timestamps, V3 expects number timestamps', () => {
    const v2Schema = z.object({ ts: transforms.fromString.date });
    const v3Schema = z.object({ ts: transforms.fromNumber.toDate });

    // V2 works with strings
    const v2Result = v2Schema.parse({ ts: '1609459200' });
    expect(v2Result.ts).toBeInstanceOf(Date);

    // V3 works with numbers
    const v3Result = v3Schema.parse({ ts: 1609459200 });
    expect(v3Result.ts).toBeInstanceOf(Date);

    // Both produce same output
    expect(v2Result.ts.getTime()).toBe(v3Result.ts.getTime());
  });

  it('V2 accepts string booleans, V3 expects native booleans', () => {
    const v2Schema = z.object({ active: transforms.fromString.boolean });
    const v3Schema = z.object({ active: z.boolean() });

    // V2 transforms strings
    const v2Result = v2Schema.parse({ active: 'true' });
    expect(v2Result.active).toBe(true);

    // V3 expects native booleans
    const v3Result = v3Schema.parse({ active: true });
    expect(v3Result.active).toBe(true);

    // V3 rejects strings
    expect(() => v3Schema.parse({ active: 'true' })).toThrow();
  });

  it('V2 accepts string numbers, V3 expects native numbers', () => {
    const v2Schema = z.object({ count: transforms.fromString.number });
    const v3Schema = z.object({ count: z.number() });

    // V2 transforms strings
    const v2Result = v2Schema.parse({ count: '42' });
    expect(v2Result.count).toBe(42);

    // V3 expects native numbers
    const v3Result = v3Schema.parse({ count: 42 });
    expect(v3Result.count).toBe(42);

    // V3 rejects strings
    expect(() => v3Schema.parse({ count: '42' })).toThrow();
  });
});

// -----------------------------------------------------------------------------
// Realistic Wire Format Tests
// -----------------------------------------------------------------------------

describe('Realistic Wire Format Tests', () => {
  describe('V2 customer payload (Redis-encoded)', () => {
    const v2CustomerSchema = z.object({
      identifier: z.string(),
      email: z.email(),
      verified: transforms.fromString.boolean,
      active: transforms.fromString.boolean,
      secrets_created: transforms.fromString.number.default(0),
      created: transforms.fromString.date,
      updated: transforms.fromString.date,
      last_login: transforms.fromString.dateNullable,
    });

    it('parses Redis-encoded customer payload', () => {
      const wirePayload = {
        identifier: 'cust123',
        email: 'user@example.com',
        verified: 'true',
        active: '1',
        secrets_created: '5',
        created: '1609459200',
        updated: '1609459200',
        last_login: '',
      };

      const result = v2CustomerSchema.parse(wirePayload);

      expect(result.verified).toBe(true);
      expect(result.active).toBe(true);
      expect(result.secrets_created).toBe(5);
      expect(result.created).toBeInstanceOf(Date);
      expect(result.last_login).toBeNull();
    });
  });

  describe('V3 customer payload (native JSON)', () => {
    const v3CustomerSchema = z.object({
      identifier: z.string(),
      email: z.email(),
      verified: z.boolean(),
      active: z.boolean(),
      secrets_created: z.number().default(0),
      created: transforms.fromNumber.toDate,
      updated: transforms.fromNumber.toDate,
      last_login: transforms.fromNumber.toDateNullish,
    });

    it('parses native JSON customer payload', () => {
      const wirePayload = {
        identifier: 'cust123',
        email: 'user@example.com',
        verified: true,
        active: true,
        secrets_created: 5,
        created: 1609459200,
        updated: 1609459200,
        last_login: null,
      };

      const result = v3CustomerSchema.parse(wirePayload);

      expect(result.verified).toBe(true);
      expect(result.active).toBe(true);
      expect(result.secrets_created).toBe(5);
      expect(result.created).toBeInstanceOf(Date);
      expect(result.last_login).toBeNull();
    });
  });
});
