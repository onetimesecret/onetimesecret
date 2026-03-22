// src/tests/schemas/transforms.spec.ts
//
// Direct unit tests for schema transforms defined in transforms.ts
// These test the transform behaviors in isolation from specific domain schemas.

import { describe, expect, it } from 'vitest';
import { z } from 'zod';
import { transforms } from '@/schemas/transforms';

// -----------------------------------------------------------------------------
// fromString.optionalEmail
// -----------------------------------------------------------------------------

describe('transforms.fromString.optionalEmail', () => {
  const schema = z.object({ email: transforms.fromString.optionalEmail });

  it('preserves valid email addresses', () => {
    const result = schema.parse({ email: 'user@example.com' });
    expect(result.email).toBe('user@example.com');
  });

  it('transforms empty string to undefined', () => {
    const result = schema.parse({ email: '' });
    expect(result.email).toBeUndefined();
  });

  it('allows undefined input', () => {
    const result = schema.parse({});
    expect(result.email).toBeUndefined();
  });

  it('rejects invalid email formats', () => {
    expect(() => schema.parse({ email: 'not-an-email' })).toThrow();
    expect(() => schema.parse({ email: 'missing@' })).toThrow();
    expect(() => schema.parse({ email: '@no-local-part.com' })).toThrow();
  });

  it('handles emails with plus addressing', () => {
    const result = schema.parse({ email: 'user+tag@example.com' });
    expect(result.email).toBe('user+tag@example.com');
  });

  it('handles emails with subdomains', () => {
    const result = schema.parse({ email: 'user@mail.example.com' });
    expect(result.email).toBe('user@mail.example.com');
  });
});

// -----------------------------------------------------------------------------
// fromObject.nested
// -----------------------------------------------------------------------------

describe('transforms.fromObject.nested', () => {
  const innerSchema = z.object({
    theme: z.string().default('light'),
    notifications: z.boolean().default(true),
  });

  const schema = z.object({
    settings: transforms.fromObject.nested(innerSchema),
  });

  it('passes through valid nested objects', () => {
    const result = schema.parse({ settings: { theme: 'dark', notifications: false } });
    expect(result.settings).toEqual({ theme: 'dark', notifications: false });
  });

  it('transforms null to empty object (defaults apply)', () => {
    const result = schema.parse({ settings: null });
    expect(result.settings).toEqual({ theme: 'light', notifications: true });
  });

  it('transforms undefined to empty object (defaults apply)', () => {
    const result = schema.parse({ settings: undefined });
    expect(result.settings).toEqual({ theme: 'light', notifications: true });
  });

  it('transforms empty object to empty object (defaults apply)', () => {
    // Empty object {} has Object.keys().length === 0, so it becomes {}
    // Then inner schema applies defaults
    const result = schema.parse({ settings: {} });
    expect(result.settings).toEqual({ theme: 'light', notifications: true });
  });

  it('preserves partial nested objects with defaults for missing fields', () => {
    const result = schema.parse({ settings: { theme: 'dark' } });
    expect(result.settings).toEqual({ theme: 'dark', notifications: true });
  });

  it('handles nested objects with all required fields', () => {
    const strictInner = z.object({ id: z.string() });
    const strictSchema = z.object({
      data: transforms.fromObject.nested(strictInner),
    });

    // null → {} → missing required 'id' throws
    expect(() => strictSchema.parse({ data: null })).toThrow();

    // Valid nested object works
    const result = strictSchema.parse({ data: { id: 'abc' } });
    expect(result.data.id).toBe('abc');
  });
});

// -----------------------------------------------------------------------------
// fromNumber date transforms
// -----------------------------------------------------------------------------

describe('transforms.fromNumber.toDate', () => {
  const schema = z.object({ created: transforms.fromNumber.toDate });

  it('converts Unix timestamp (seconds) to Date', () => {
    const result = schema.parse({ created: 1609459200 }); // 2021-01-01T00:00:00Z
    expect(result.created).toBeInstanceOf(Date);
    expect(result.created.toISOString()).toBe('2021-01-01T00:00:00.000Z');
  });

  it('rejects null input', () => {
    expect(() => schema.parse({ created: null })).toThrow();
  });

  it('rejects undefined input', () => {
    expect(() => schema.parse({})).toThrow();
  });

  it('handles zero timestamp (Unix epoch)', () => {
    const result = schema.parse({ created: 0 });
    expect(result.created.toISOString()).toBe('1970-01-01T00:00:00.000Z');
  });
});

describe('transforms.fromNumber.toDateNullable', () => {
  const schema = z.object({ updated: transforms.fromNumber.toDateNullable });

  it('converts Unix timestamp to Date', () => {
    const result = schema.parse({ updated: 1609459200 });
    expect(result.updated).toBeInstanceOf(Date);
    expect(result.updated!.toISOString()).toBe('2021-01-01T00:00:00.000Z');
  });

  it('preserves null input', () => {
    const result = schema.parse({ updated: null });
    expect(result.updated).toBeNull();
  });

  it('rejects undefined input (not in type union)', () => {
    expect(() => schema.parse({})).toThrow();
  });
});

describe('transforms.fromNumber.toDateOptional', () => {
  const schema = z.object({ deleted: transforms.fromNumber.toDateOptional });

  it('converts Unix timestamp to Date', () => {
    const result = schema.parse({ deleted: 1609459200 });
    expect(result.deleted).toBeInstanceOf(Date);
    expect(result.deleted!.toISOString()).toBe('2021-01-01T00:00:00.000Z');
  });

  it('preserves undefined input', () => {
    const result = schema.parse({ deleted: undefined });
    expect(result.deleted).toBeUndefined();
  });

  it('allows omitted field', () => {
    const result = schema.parse({});
    expect(result.deleted).toBeUndefined();
  });

  it('rejects null input (not in type union)', () => {
    expect(() => schema.parse({ deleted: null })).toThrow();
  });
});

describe('transforms.fromNumber.toDateNullish', () => {
  const schema = z.object({ viewed: transforms.fromNumber.toDateNullish });

  it('converts Unix timestamp to Date', () => {
    const result = schema.parse({ viewed: 1609459200 });
    expect(result.viewed).toBeInstanceOf(Date);
    expect(result.viewed!.toISOString()).toBe('2021-01-01T00:00:00.000Z');
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

// -----------------------------------------------------------------------------
// fromNumber.secondsToDate (deprecated)
// -----------------------------------------------------------------------------

describe('transforms.fromNumber.secondsToDate (deprecated)', () => {
  const schema = z.object({ ts: transforms.fromNumber.secondsToDate });

  it('converts Unix timestamp (seconds) to Date', () => {
    const result = schema.parse({ ts: 1609459200 });
    expect(result.ts).toBeInstanceOf(Date);
    expect(result.ts.toISOString()).toBe('2021-01-01T00:00:00.000Z');
  });

  it('handles zero timestamp', () => {
    const result = schema.parse({ ts: 0 });
    expect(result.ts.toISOString()).toBe('1970-01-01T00:00:00.000Z');
  });

  // Note: secondsToDate uses preprocess which accepts any input type
  // This is why it's deprecated in favor of toDate which uses transform()
});

// -----------------------------------------------------------------------------
// fromString transforms (already have integration coverage, add edge cases)
// -----------------------------------------------------------------------------

describe('transforms.fromString.number', () => {
  const schema = z.object({ count: transforms.fromString.number });

  it('parses integer strings', () => {
    expect(schema.parse({ count: '42' }).count).toBe(42);
  });

  it('parses decimal strings', () => {
    expect(schema.parse({ count: '3.14' }).count).toBe(3.14);
  });

  it('handles negative numbers', () => {
    expect(schema.parse({ count: '-42' }).count).toBe(-42);
  });

  it('returns null for empty string', () => {
    expect(schema.parse({ count: '' }).count).toBeNull();
  });

  it('returns null for null', () => {
    expect(schema.parse({ count: null }).count).toBeNull();
  });

  it('returns null for undefined', () => {
    expect(schema.parse({ count: undefined }).count).toBeNull();
  });

  it('returns null for non-numeric strings', () => {
    expect(schema.parse({ count: 'abc' }).count).toBeNull();
    expect(schema.parse({ count: 'NaN' }).count).toBeNull();
  });

  it('rejects Infinity values (Zod 4 finite number validation)', () => {
    // Zod 4 rejects Infinity as an invalid number type
    expect(() => schema.parse({ count: 'Infinity' })).toThrow();
    expect(() => schema.parse({ count: '-Infinity' })).toThrow();
  });

  it('handles scientific notation', () => {
    expect(schema.parse({ count: '1e10' }).count).toBe(1e10);
    expect(schema.parse({ count: '2.5e-3' }).count).toBe(0.0025);
  });

  it('passes through actual numbers', () => {
    expect(schema.parse({ count: 42 }).count).toBe(42);
    expect(schema.parse({ count: 0 }).count).toBe(0);
  });
});

// -----------------------------------------------------------------------------
// fromString.ttlToNaturalLanguage (schema-level tests)
// -----------------------------------------------------------------------------

describe('transforms.fromString.ttlToNaturalLanguage', () => {
  const schema = z.object({ expiresIn: transforms.fromString.ttlToNaturalLanguage });

  it('converts seconds to natural language (1 hour)', () => {
    const result = schema.parse({ expiresIn: 3600 });
    expect(result.expiresIn).toBe('1 hour from now');
  });

  it('converts seconds to natural language (1 day)', () => {
    const result = schema.parse({ expiresIn: 86400 });
    expect(result.expiresIn).toBe('1 day from now');
  });

  it('converts seconds to natural language plural (2 days)', () => {
    const result = schema.parse({ expiresIn: 172800 });
    expect(result.expiresIn).toBe('2 days from now');
  });

  it('converts string seconds to natural language', () => {
    const result = schema.parse({ expiresIn: '3600' });
    expect(result.expiresIn).toBe('1 hour from now');
  });

  it('handles leading zeros in string numbers', () => {
    const result = schema.parse({ expiresIn: '08' });
    expect(result.expiresIn).toBe('8 seconds from now');
  });

  it('returns null for negative values', () => {
    const result = schema.parse({ expiresIn: -1 });
    expect(result.expiresIn).toBeNull();
  });

  it('returns null for null input', () => {
    const result = schema.parse({ expiresIn: null });
    expect(result.expiresIn).toBeNull();
  });

  it('returns null for undefined input', () => {
    const result = schema.parse({ expiresIn: undefined });
    expect(result.expiresIn).toBeNull();
  });

  it('preserves pre-formatted strings containing non-numeric characters', () => {
    const result = schema.parse({ expiresIn: '2 hours from now' });
    expect(result.expiresIn).toBe('2 hours from now');
  });

  it('handles zero seconds', () => {
    const result = schema.parse({ expiresIn: 0 });
    expect(result.expiresIn).toBe('a few seconds from now');
  });

  it('handles very large values (1 year)', () => {
    const result = schema.parse({ expiresIn: 31536000 });
    expect(result.expiresIn).toBe('1 year from now');
  });

  it('handles minutes correctly', () => {
    const result = schema.parse({ expiresIn: 120 });
    expect(result.expiresIn).toBe('2 minutes from now');
  });

  it('schema output type is string or null', () => {
    // Type-level verification: schema.parse returns { expiresIn: string | null }
    const validResult = schema.parse({ expiresIn: 3600 });
    expect(typeof validResult.expiresIn).toBe('string');

    const nullResult = schema.parse({ expiresIn: null });
    expect(nullResult.expiresIn).toBeNull();
  });
});

describe('transforms.fromString.boolean', () => {
  const schema = z.object({ active: transforms.fromString.boolean });

  it('parses "true" as true', () => {
    expect(schema.parse({ active: 'true' }).active).toBe(true);
  });

  it('parses "1" as true', () => {
    expect(schema.parse({ active: '1' }).active).toBe(true);
  });

  it('parses "false" as false', () => {
    expect(schema.parse({ active: 'false' }).active).toBe(false);
  });

  it('parses "0" as false', () => {
    expect(schema.parse({ active: '0' }).active).toBe(false);
  });

  it('parses empty string as false', () => {
    expect(schema.parse({ active: '' }).active).toBe(false);
  });

  it('parses null as false', () => {
    expect(schema.parse({ active: null }).active).toBe(false);
  });

  it('parses undefined as false', () => {
    expect(schema.parse({ active: undefined }).active).toBe(false);
  });

  it('passes through actual booleans', () => {
    expect(schema.parse({ active: true }).active).toBe(true);
    expect(schema.parse({ active: false }).active).toBe(false);
  });

  it('treats other string values as false', () => {
    // Only "true" and "1" are truthy
    expect(schema.parse({ active: 'yes' }).active).toBe(false);
    expect(schema.parse({ active: 'TRUE' }).active).toBe(false);
    expect(schema.parse({ active: 'True' }).active).toBe(false);
  });
});

// -----------------------------------------------------------------------------
// fromString.date (required date transform)
// -----------------------------------------------------------------------------

describe('transforms.fromString.date', () => {
  const schema = z.object({ created: transforms.fromString.date });

  describe('valid timestamp parsing', () => {
    it('parses Unix timestamp string (seconds) to Date', () => {
      const result = schema.parse({ created: '1609459200' }); // 2021-01-01T00:00:00Z
      expect(result.created).toBeInstanceOf(Date);
      expect(result.created.toISOString()).toBe('2021-01-01T00:00:00.000Z');
    });

    it('parses Unix timestamp string (milliseconds) to Date', () => {
      // Timestamps with more than 10 digits are treated as milliseconds
      const result = schema.parse({ created: '1609459200000' });
      expect(result.created).toBeInstanceOf(Date);
      expect(result.created.toISOString()).toBe('2021-01-01T00:00:00.000Z');
    });

    it('passes through numeric timestamps', () => {
      const result = schema.parse({ created: 1609459200 });
      expect(result.created).toBeInstanceOf(Date);
      expect(result.created.toISOString()).toBe('2021-01-01T00:00:00.000Z');
    });

    it('handles zero timestamp (Unix epoch)', () => {
      const result = schema.parse({ created: '0' });
      expect(result.created.toISOString()).toBe('1970-01-01T00:00:00.000Z');
    });
  });

  describe('ISO date string parsing', () => {
    it('parses full ISO 8601 datetime string', () => {
      const result = schema.parse({ created: '2021-01-01T00:00:00Z' });
      expect(result.created).toBeInstanceOf(Date);
      expect(result.created.toISOString()).toBe('2021-01-01T00:00:00.000Z');
    });

    it('parses ISO date string with timezone offset', () => {
      const result = schema.parse({ created: '2021-01-01T12:00:00+00:00' });
      expect(result.created).toBeInstanceOf(Date);
      expect(result.created.toISOString()).toBe('2021-01-01T12:00:00.000Z');
    });

    it('parses simple ISO date string (YYYY-MM-DD)', () => {
      const result = schema.parse({ created: '2021-01-01' });
      expect(result.created).toBeInstanceOf(Date);
      // Note: Date parsing of YYYY-MM-DD treats it as UTC midnight
      expect(result.created.getUTCFullYear()).toBe(2021);
      expect(result.created.getUTCMonth()).toBe(0); // January
      expect(result.created.getUTCDate()).toBe(1);
    });
  });

  describe('required date rejection of null/empty', () => {
    it('rejects null input', () => {
      expect(() => schema.parse({ created: null })).toThrow();
    });

    it('rejects empty string input', () => {
      expect(() => schema.parse({ created: '' })).toThrow();
    });

    it('rejects undefined input', () => {
      expect(() => schema.parse({ created: undefined })).toThrow();
    });

    it('rejects omitted field', () => {
      expect(() => schema.parse({})).toThrow();
    });

    it('rejects invalid date strings', () => {
      expect(() => schema.parse({ created: 'not-a-date' })).toThrow();
      expect(() => schema.parse({ created: 'abc' })).toThrow();
    });
  });

  describe('Date object passthrough', () => {
    it('passes through valid Date objects', () => {
      const date = new Date('2021-01-01T00:00:00Z');
      const result = schema.parse({ created: date });
      expect(result.created).toBeInstanceOf(Date);
      expect(result.created.toISOString()).toBe('2021-01-01T00:00:00.000Z');
    });

    it('rejects invalid Date objects', () => {
      const invalidDate = new Date('invalid');
      expect(() => schema.parse({ created: invalidDate })).toThrow();
    });
  });
});

// -----------------------------------------------------------------------------
// fromString.dateNullable (nullable date transform)
// -----------------------------------------------------------------------------

describe('transforms.fromString.dateNullable', () => {
  const schema = z.object({ updated: transforms.fromString.dateNullable });

  describe('valid timestamp parsing', () => {
    it('parses Unix timestamp string (seconds) to Date', () => {
      const result = schema.parse({ updated: '1609459200' }); // 2021-01-01T00:00:00Z
      expect(result.updated).toBeInstanceOf(Date);
      expect(result.updated!.toISOString()).toBe('2021-01-01T00:00:00.000Z');
    });

    it('parses Unix timestamp string (milliseconds) to Date', () => {
      const result = schema.parse({ updated: '1609459200000' });
      expect(result.updated).toBeInstanceOf(Date);
      expect(result.updated!.toISOString()).toBe('2021-01-01T00:00:00.000Z');
    });

    it('passes through numeric timestamps', () => {
      const result = schema.parse({ updated: 1609459200 });
      expect(result.updated).toBeInstanceOf(Date);
      expect(result.updated!.toISOString()).toBe('2021-01-01T00:00:00.000Z');
    });

    it('handles zero timestamp (Unix epoch)', () => {
      const result = schema.parse({ updated: '0' });
      expect(result.updated!.toISOString()).toBe('1970-01-01T00:00:00.000Z');
    });
  });

  describe('ISO date string parsing', () => {
    it('parses full ISO 8601 datetime string', () => {
      const result = schema.parse({ updated: '2021-01-01T00:00:00Z' });
      expect(result.updated).toBeInstanceOf(Date);
      expect(result.updated!.toISOString()).toBe('2021-01-01T00:00:00.000Z');
    });

    it('parses ISO date string with timezone offset', () => {
      const result = schema.parse({ updated: '2021-01-01T12:00:00+00:00' });
      expect(result.updated).toBeInstanceOf(Date);
      expect(result.updated!.toISOString()).toBe('2021-01-01T12:00:00.000Z');
    });

    it('parses simple ISO date string (YYYY-MM-DD)', () => {
      const result = schema.parse({ updated: '2021-01-01' });
      expect(result.updated).toBeInstanceOf(Date);
      expect(result.updated!.getUTCFullYear()).toBe(2021);
      expect(result.updated!.getUTCMonth()).toBe(0);
      expect(result.updated!.getUTCDate()).toBe(1);
    });
  });

  describe('nullable date allows null/empty', () => {
    it('transforms null to null', () => {
      const result = schema.parse({ updated: null });
      expect(result.updated).toBeNull();
    });

    it('transforms empty string to null', () => {
      const result = schema.parse({ updated: '' });
      expect(result.updated).toBeNull();
    });

    it('transforms undefined to null', () => {
      const result = schema.parse({ updated: undefined });
      expect(result.updated).toBeNull();
    });

    it('transforms invalid date strings to null', () => {
      // parseDateValue returns null for unparseable strings
      const result = schema.parse({ updated: 'not-a-date' });
      expect(result.updated).toBeNull();
    });
  });

  describe('Date object passthrough', () => {
    it('passes through valid Date objects', () => {
      const date = new Date('2021-01-01T00:00:00Z');
      const result = schema.parse({ updated: date });
      expect(result.updated).toBeInstanceOf(Date);
      expect(result.updated!.toISOString()).toBe('2021-01-01T00:00:00.000Z');
    });

    it('handles invalid Date objects gracefully', () => {
      // parseDateValue checks isNaN on the date and returns null if invalid
      const invalidDate = new Date('invalid');
      const result = schema.parse({ updated: invalidDate });
      expect(result.updated).toBeNull();
    });
  });

  describe('type inference verification', () => {
    it('output type is Date | null', () => {
      const validResult = schema.parse({ updated: '1609459200' });
      expect(validResult.updated).toBeInstanceOf(Date);

      const nullResult = schema.parse({ updated: null });
      expect(nullResult.updated).toBeNull();
    });
  });
});
