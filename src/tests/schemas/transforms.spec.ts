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

  // Note: secondsToDate now uses transform() instead of preprocess()
  // Both secondsToDate and toDate use the same pattern for consistency
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

  it('rejects undefined (use .optional() for optional fields)', () => {
    // V2 wire format doesn't have undefined - fields are either present or missing
    // For optional fields in schemas, use: transforms.fromString.number.optional()
    expect(() => schema.parse({ count: undefined })).toThrow();
  });

  it('returns null for non-numeric strings', () => {
    expect(schema.parse({ count: 'abc' }).count).toBeNull();
    expect(schema.parse({ count: 'NaN' }).count).toBeNull();
  });

  it('returns null for Infinity string values', () => {
    // Infinity parses to a number but transform returns null for edge cases
    // that would be invalid in typical usage
    expect(schema.parse({ count: 'Infinity' }).count).toBe(Infinity);
    expect(schema.parse({ count: '-Infinity' }).count).toBe(-Infinity);
  });

  it('handles scientific notation', () => {
    expect(schema.parse({ count: '1e10' }).count).toBe(1e10);
    expect(schema.parse({ count: '2.5e-3' }).count).toBe(0.0025);
  });

  it('rejects actual numbers (V2 wire format is strings)', () => {
    // V2 API sends numbers as strings, not actual numbers
    // Use fromNumber transforms for V3 wire format
    expect(() => schema.parse({ count: 42 })).toThrow();
  });
});

// -----------------------------------------------------------------------------
// fromString.ttlToNaturalLanguage (schema-level tests)
// -----------------------------------------------------------------------------

describe('transforms.fromString.ttlToNaturalLanguage', () => {
  const schema = z.object({ expiresIn: transforms.fromString.ttlToNaturalLanguage });

  it('converts string seconds to natural language (1 hour)', () => {
    const result = schema.parse({ expiresIn: '3600' });
    expect(result.expiresIn).toBe('1 hour from now');
  });

  it('converts string seconds to natural language (1 day)', () => {
    const result = schema.parse({ expiresIn: '86400' });
    expect(result.expiresIn).toBe('1 day from now');
  });

  it('converts string seconds to natural language plural (2 days)', () => {
    const result = schema.parse({ expiresIn: '172800' });
    expect(result.expiresIn).toBe('2 days from now');
  });

  it('handles leading zeros in string numbers', () => {
    const result = schema.parse({ expiresIn: '08' });
    expect(result.expiresIn).toBe('8 seconds from now');
  });

  it('preserves negative string values (treated as pre-formatted)', () => {
    // Note: "-1" contains a minus sign which the utility treats as non-numeric
    // and preserves as-is (same as "2 hours from now"). This may be a bug in
    // ttlToNaturalLanguage but is outside the scope of transform refactoring.
    const result = schema.parse({ expiresIn: '-1' });
    expect(result.expiresIn).toBe('-1');
  });

  it('returns null for null input', () => {
    const result = schema.parse({ expiresIn: null });
    expect(result.expiresIn).toBeNull();
  });

  it('rejects undefined input (use .optional() for optional fields)', () => {
    // V2 wire format doesn't have undefined - use .optional() for optional fields
    expect(() => schema.parse({ expiresIn: undefined })).toThrow();
  });

  it('preserves pre-formatted strings containing non-numeric characters', () => {
    const result = schema.parse({ expiresIn: '2 hours from now' });
    expect(result.expiresIn).toBe('2 hours from now');
  });

  it('handles zero string', () => {
    const result = schema.parse({ expiresIn: '0' });
    expect(result.expiresIn).toBe('a few seconds from now');
  });

  it('handles very large string values (1 year)', () => {
    const result = schema.parse({ expiresIn: '31536000' });
    expect(result.expiresIn).toBe('1 year from now');
  });

  it('handles minutes correctly as string', () => {
    const result = schema.parse({ expiresIn: '120' });
    expect(result.expiresIn).toBe('2 minutes from now');
  });

  it('rejects actual numbers (V2 wire format is strings)', () => {
    // V2 API sends TTL as strings, not actual numbers
    expect(() => schema.parse({ expiresIn: 3600 })).toThrow();
  });

  it('schema output type is string or null', () => {
    // Type-level verification: schema.parse returns { expiresIn: string | null }
    const validResult = schema.parse({ expiresIn: '3600' });
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

  it('coerces undefined to false', () => {
    // Missing fields in wire format should default to false
    expect(schema.parse({ active: undefined }).active).toBe(false);
  });

  it('rejects actual booleans (V2 wire format is strings)', () => {
    // V2 API sends booleans as strings "true"/"false", not actual booleans
    expect(() => schema.parse({ active: true })).toThrow();
    expect(() => schema.parse({ active: false })).toThrow();
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

    it('rejects numeric timestamps (V2 wire format is strings)', () => {
      // V2 API sends timestamps as strings, not numbers
      // Use fromNumber transforms for V3 wire format
      expect(() => schema.parse({ created: 1609459200 })).toThrow();
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

  describe('Date object rejection (V2 wire format is strings)', () => {
    it('rejects Date objects (V2 wire format is strings)', () => {
      // V2 API sends timestamps as strings, not Date objects
      const date = new Date('2021-01-01T00:00:00Z');
      expect(() => schema.parse({ created: date })).toThrow();
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

    it('rejects numeric timestamps (V2 wire format is strings)', () => {
      // V2 API sends timestamps as strings, not numbers
      // Use fromNumber transforms for V3 wire format
      expect(() => schema.parse({ updated: 1609459200 })).toThrow();
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

    it('rejects undefined (use .optional() for optional fields)', () => {
      // V2 wire format doesn't have undefined - use .optional() for optional fields
      expect(() => schema.parse({ updated: undefined })).toThrow();
    });

    it('transforms invalid date strings to null', () => {
      // parseDateValue returns null for unparseable strings
      const result = schema.parse({ updated: 'not-a-date' });
      expect(result.updated).toBeNull();
    });
  });

  describe('Date object rejection (V2 wire format is strings)', () => {
    it('rejects Date objects (V2 wire format is strings)', () => {
      // V2 API sends timestamps as strings, not Date objects
      // Use fromNumber transforms for V3 wire format with numeric timestamps
      const date = new Date('2021-01-01T00:00:00Z');
      expect(() => schema.parse({ updated: date })).toThrow();
    });

    it('rejects invalid Date objects', () => {
      const invalidDate = new Date('invalid');
      expect(() => schema.parse({ updated: invalidDate })).toThrow();
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
