// tests/unit/vue/utils/parse.spec.ts
import { parseDateValue } from '@/utils/parse/date';
import { describe, expect, it } from 'vitest';

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
});
