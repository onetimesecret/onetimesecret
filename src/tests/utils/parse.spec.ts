// src/tests/utils/parse.spec.ts

import { parseDateValue } from '@/utils/parse/date';
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
