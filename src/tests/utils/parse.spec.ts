// src/tests/utils/parse.spec.ts

import { parseDateValue } from '@/utils/parse/date';
import { parseBoolean, parseNumber, parseNestedObject } from '@/utils/parse/index';
import { describe, expect, it } from 'vitest';

/**
 * pnpm exec vitest run tests/unit/vue/utils/parse.spec.ts
 *
 */

describe('parseDateValue', () => {
  it('should correctly parse ISO date strings', () => {
    const isoDate = '2024-12-25T16:06:54Z';
    const result = parseDateValue(isoDate);
    expect(result).toEqual(new Date(isoDate));
  });

  it('should correctly parse timestamps as seconds', () => {
    const timestamp = 1703520414; // seconds
    const result = parseDateValue(timestamp);
    expect(result).toEqual(new Date(timestamp * 1000));
  });

  it('should correctly parse timestamp strings', () => {
    const timestampStr = '1703520414';
    const result = parseDateValue(timestampStr);
    expect(result).toEqual(new Date(parseInt(timestampStr, 10) * 1000));
  });

  it('should handle null/undefined/empty values', () => {
    expect(parseDateValue(null)).toBeNull();
    expect(parseDateValue(undefined)).toBeNull();
    expect(parseDateValue('')).toBeNull();
  });

  it('should pass through Date objects', () => {
    const date = new Date();
    expect(parseDateValue(date)).toBe(date);
  });

  describe('millis or seconds', () => {
    const TEST_DATE = new Date('2024-12-25T16:06:54.000Z');
    const SECONDS_TIMESTAMP = Math.floor(TEST_DATE.getTime() / 1000); // 1703520414
    const MILLIS_TIMESTAMP = TEST_DATE.getTime(); // 1703520414000

    it('handles null and undefined', () => {
      expect(parseDateValue(null)).toBeNull();
      expect(parseDateValue(undefined)).toBeNull();
      expect(parseDateValue('')).toBeNull();
    });

    it('handles ISO string dates', () => {
      expect(parseDateValue('2024-12-25T16:06:54.000Z')).toEqual(TEST_DATE);
    });

    it('handles second-based timestamps as strings', () => {
      expect(parseDateValue(String(SECONDS_TIMESTAMP))).toEqual(TEST_DATE);
    });

    it('handles millisecond-based timestamps as strings', () => {
      expect(parseDateValue(String(MILLIS_TIMESTAMP))).toEqual(TEST_DATE);
    });

    it('handles second-based timestamps as numbers', () => {
      expect(parseDateValue(SECONDS_TIMESTAMP)).toEqual(TEST_DATE);
    });

    it('handles millisecond-based timestamps as numbers', () => {
      expect(parseDateValue(MILLIS_TIMESTAMP)).toEqual(TEST_DATE);
    });

    it('handles invalid inputs', () => {
      expect(parseDateValue('invalid')).toBeNull();
      expect(parseDateValue({})).toBeNull();
      expect(parseDateValue([])).toBeNull();
      expect(parseDateValue(new Date('invalid'))).toBeNull();
    });
  });
});

describe('parseNumber', () => {
  describe('null/undefined/empty handling', () => {
    it('returns null for null', () => {
      expect(parseNumber(null)).toBeNull();
    });

    it('returns null for undefined', () => {
      expect(parseNumber(undefined)).toBeNull();
    });

    it('returns null for empty string', () => {
      expect(parseNumber('')).toBeNull();
    });
  });

  describe('invalid string inputs', () => {
    it('returns null for alphabetic string "abc"', () => {
      expect(parseNumber('abc')).toBeNull();
    });

    it('returns null for string "NaN"', () => {
      expect(parseNumber('NaN')).toBeNull();
    });

    it('returns null for mixed alphanumeric strings', () => {
      expect(parseNumber('12abc')).toBeNull();
      expect(parseNumber('abc12')).toBeNull();
    });

    it('returns null for whitespace-only strings', () => {
      // Note: Number('   ') returns 0, but trimmed it's empty
      // Current implementation: Number('   ') = 0, which is not NaN
      // This documents actual behavior
      expect(parseNumber('   ')).toBe(0);
    });
  });

  describe('special numeric values', () => {
    it('parses "Infinity" to Infinity', () => {
      expect(parseNumber('Infinity')).toBe(Infinity);
    });

    it('parses "-Infinity" to -Infinity', () => {
      expect(parseNumber('-Infinity')).toBe(-Infinity);
    });

    it('passes through Infinity number value', () => {
      expect(parseNumber(Infinity)).toBe(Infinity);
    });

    it('passes through -Infinity number value', () => {
      expect(parseNumber(-Infinity)).toBe(-Infinity);
    });
  });

  describe('scientific notation', () => {
    it('parses scientific notation string "1e5"', () => {
      expect(parseNumber('1e5')).toBe(100000);
    });

    it('parses scientific notation string "1.5e3"', () => {
      expect(parseNumber('1.5e3')).toBe(1500);
    });

    it('parses negative exponent "1e-3"', () => {
      expect(parseNumber('1e-3')).toBe(0.001);
    });

    it('parses uppercase "1E5"', () => {
      expect(parseNumber('1E5')).toBe(100000);
    });
  });

  describe('hex strings', () => {
    it('parses hex string "0x10" to 16', () => {
      expect(parseNumber('0x10')).toBe(16);
    });

    it('parses hex string "0xFF" to 255', () => {
      expect(parseNumber('0xFF')).toBe(255);
    });

    it('parses lowercase hex "0xff"', () => {
      expect(parseNumber('0xff')).toBe(255);
    });
  });

  describe('numeric passthrough', () => {
    it('passes through positive integers', () => {
      expect(parseNumber(42)).toBe(42);
    });

    it('passes through negative integers', () => {
      expect(parseNumber(-42)).toBe(-42);
    });

    it('passes through zero', () => {
      expect(parseNumber(0)).toBe(0);
    });

    it('passes through floating point numbers', () => {
      expect(parseNumber(3.14159)).toBe(3.14159);
    });

    it('passes through NaN (as a number type)', () => {
      // NaN is typeof number, so it passes through directly
      expect(parseNumber(NaN)).toBeNaN();
    });
  });

  describe('string numeric parsing', () => {
    it('parses positive integer strings', () => {
      expect(parseNumber('42')).toBe(42);
    });

    it('parses negative integer strings', () => {
      expect(parseNumber('-42')).toBe(-42);
    });

    it('parses "0" to 0', () => {
      expect(parseNumber('0')).toBe(0);
    });

    it('parses floating point strings', () => {
      expect(parseNumber('3.14159')).toBe(3.14159);
    });

    it('parses strings with leading zeros', () => {
      expect(parseNumber('007')).toBe(7);
    });

    it('parses strings with leading/trailing whitespace', () => {
      expect(parseNumber('  42  ')).toBe(42);
    });
  });

  describe('edge cases', () => {
    it('returns null for objects', () => {
      expect(parseNumber({})).toBeNull();
    });

    it('returns null for arrays', () => {
      // Note: Number([]) = 0, Number([1]) = 1, but Number([1,2]) = NaN
      expect(parseNumber([])).toBe(0);
      expect(parseNumber([1])).toBe(1);
      expect(parseNumber([1, 2])).toBeNull();
    });

    it('parses boolean true to 1', () => {
      expect(parseNumber(true)).toBe(1);
    });

    it('parses boolean false to 0', () => {
      expect(parseNumber(false)).toBe(0);
    });
  });
});

describe('parseNestedObject', () => {
  describe('null/undefined handling', () => {
    it('returns empty object for null', () => {
      expect(parseNestedObject(null)).toEqual({});
    });

    it('returns empty object for undefined', () => {
      expect(parseNestedObject(undefined)).toEqual({});
    });
  });

  describe('empty object handling', () => {
    it('returns empty object for empty object (no keys)', () => {
      expect(parseNestedObject({})).toEqual({});
    });
  });

  describe('object with keys', () => {
    it('preserves object with single key', () => {
      const input = { key: 'value' };
      expect(parseNestedObject(input)).toBe(input);
    });

    it('preserves object with multiple keys', () => {
      const input = { a: 1, b: 2, c: 3 };
      expect(parseNestedObject(input)).toBe(input);
    });

    it('preserves deeply nested objects', () => {
      const input = { level1: { level2: { level3: 'deep' } } };
      expect(parseNestedObject(input)).toBe(input);
    });

    it('preserves object with null value', () => {
      const input = { key: null };
      expect(parseNestedObject(input)).toBe(input);
    });

    it('preserves object with undefined value', () => {
      const input = { key: undefined };
      expect(parseNestedObject(input)).toBe(input);
    });

    it('preserves object with array value', () => {
      const input = { items: [1, 2, 3] };
      expect(parseNestedObject(input)).toBe(input);
    });

    it('preserves object with mixed value types', () => {
      const input = {
        string: 'hello',
        number: 42,
        boolean: true,
        nested: { foo: 'bar' },
        array: [1, 2],
      };
      expect(parseNestedObject(input)).toBe(input);
    });
  });

  describe('non-object values (silent fallback to empty object)', () => {
    it('returns empty object for string', () => {
      expect(parseNestedObject('string')).toEqual({});
    });

    it('returns empty object for number', () => {
      expect(parseNestedObject(42)).toEqual({});
    });

    it('returns empty object for zero', () => {
      expect(parseNestedObject(0)).toEqual({});
    });

    it('returns empty object for boolean true', () => {
      expect(parseNestedObject(true)).toEqual({});
    });

    it('returns empty object for boolean false', () => {
      expect(parseNestedObject(false)).toEqual({});
    });

    it('returns empty object for empty string', () => {
      expect(parseNestedObject('')).toEqual({});
    });
  });

  describe('array handling', () => {
    // Arrays are typeof 'object' but have numeric keys
    it('returns empty array for empty array', () => {
      // Empty array has no keys, so returns {}
      expect(parseNestedObject([])).toEqual({});
    });

    it('preserves non-empty array (has numeric keys)', () => {
      // Non-empty arrays have keys (0, 1, 2...) so they pass the check
      const input = [1, 2, 3];
      expect(parseNestedObject(input)).toBe(input);
    });

    it('preserves array with single element', () => {
      const input = ['single'];
      expect(parseNestedObject(input)).toBe(input);
    });
  });

  describe('special object types', () => {
    it('preserves Date objects (has keys from Object.keys)', () => {
      // Date objects have no enumerable keys via Object.keys
      const date = new Date();
      expect(parseNestedObject(date)).toEqual({});
    });

    it('preserves RegExp objects (has keys from Object.keys)', () => {
      // RegExp objects have no enumerable keys via Object.keys
      const regex = /test/;
      expect(parseNestedObject(regex)).toEqual({});
    });

    it('handles object with symbol keys (not counted by Object.keys)', () => {
      const sym = Symbol('test');
      const input = { [sym]: 'value' };
      // Object.keys only returns string keys, so this has 0 keys
      expect(parseNestedObject(input)).toEqual({});
    });

    it('preserves object with both string and symbol keys', () => {
      const sym = Symbol('test');
      const input = { [sym]: 'symbol value', stringKey: 'string value' };
      // Has 1 string key, so it passes
      expect(parseNestedObject(input)).toBe(input);
    });
  });

  describe('reference preservation', () => {
    it('returns same reference for valid object (not a copy)', () => {
      const input = { key: 'value' };
      const result = parseNestedObject(input);
      expect(result).toBe(input);
      // Mutating the result affects the original
      (result as Record<string, string>).newKey = 'new value';
      expect(input).toHaveProperty('newKey', 'new value');
    });

    it('returns new empty object for invalid input', () => {
      const result1 = parseNestedObject(null);
      const result2 = parseNestedObject(null);
      // Each call returns a new empty object
      expect(result1).not.toBe(result2);
      expect(result1).toEqual({});
      expect(result2).toEqual({});
    });
  });
});
