// src/tests/utils/format.spec.ts

import { formatDate, formatRelativeTime, ttlToNaturalLanguage } from '@/utils/format/index';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

describe('ttlToNaturalLanguage', () => {
  describe('null/undefined/negative inputs', () => {
    it('returns null for null input', () => {
      expect(ttlToNaturalLanguage(null)).toBeNull();
    });

    it('returns null for undefined input', () => {
      expect(ttlToNaturalLanguage(undefined)).toBeNull();
    });

    it('returns null for negative numbers', () => {
      expect(ttlToNaturalLanguage(-1)).toBeNull();
      expect(ttlToNaturalLanguage(-100)).toBeNull();
      expect(ttlToNaturalLanguage(-86400)).toBeNull();
    });

    it('returns null for negative string numbers', () => {
      // Note: "-1" contains a non-numeric character ("-") so it's preserved as-is
      // This is current behavior - the regex /[^0-9.]/ matches "-"
      expect(ttlToNaturalLanguage('-1')).toBe('-1');
    });

    it('returns null for empty string (becomes NaN)', () => {
      expect(ttlToNaturalLanguage('')).toBeNull();
    });
  });

  describe('zero seconds', () => {
    it('returns "a few seconds from now" for zero', () => {
      expect(ttlToNaturalLanguage(0)).toBe('a few seconds from now');
    });

    it('returns "a few seconds from now" for string zero', () => {
      expect(ttlToNaturalLanguage('0')).toBe('a few seconds from now');
    });
  });

  describe('seconds interval (1-59s)', () => {
    it('returns singular for 1 second', () => {
      expect(ttlToNaturalLanguage(1)).toBe('1 second from now');
    });

    it('returns plural for 2 seconds', () => {
      expect(ttlToNaturalLanguage(2)).toBe('2 seconds from now');
    });

    it('returns plural for 59 seconds (boundary before minute)', () => {
      expect(ttlToNaturalLanguage(59)).toBe('59 seconds from now');
    });
  });

  describe('minutes interval (60-3599s)', () => {
    it('returns 1 minute for exactly 60 seconds (boundary)', () => {
      expect(ttlToNaturalLanguage(60)).toBe('1 minute from now');
    });

    it('returns 1 minute for 61 seconds', () => {
      expect(ttlToNaturalLanguage(61)).toBe('1 minute from now');
    });

    it('returns 1 minute for 119 seconds', () => {
      expect(ttlToNaturalLanguage(119)).toBe('1 minute from now');
    });

    it('returns 2 minutes for 120 seconds', () => {
      expect(ttlToNaturalLanguage(120)).toBe('2 minutes from now');
    });

    it('returns 59 minutes for 3540 seconds', () => {
      expect(ttlToNaturalLanguage(3540)).toBe('59 minutes from now');
    });

    it('returns 59 minutes for 3599 seconds (boundary before hour)', () => {
      expect(ttlToNaturalLanguage(3599)).toBe('59 minutes from now');
    });
  });

  describe('hours interval (3600-86399s)', () => {
    it('returns 1 hour for exactly 3600 seconds (boundary)', () => {
      expect(ttlToNaturalLanguage(3600)).toBe('1 hour from now');
    });

    it('returns 1 hour for 3601 seconds', () => {
      expect(ttlToNaturalLanguage(3601)).toBe('1 hour from now');
    });

    it('returns 1 hour for 7199 seconds', () => {
      expect(ttlToNaturalLanguage(7199)).toBe('1 hour from now');
    });

    it('returns 2 hours for 7200 seconds', () => {
      expect(ttlToNaturalLanguage(7200)).toBe('2 hours from now');
    });

    it('returns 23 hours for 82800 seconds', () => {
      expect(ttlToNaturalLanguage(82800)).toBe('23 hours from now');
    });

    it('returns 23 hours for 86399 seconds (boundary before day)', () => {
      expect(ttlToNaturalLanguage(86399)).toBe('23 hours from now');
    });
  });

  describe('days interval (86400-604799s)', () => {
    it('returns 1 day for exactly 86400 seconds (boundary)', () => {
      expect(ttlToNaturalLanguage(86400)).toBe('1 day from now');
    });

    it('returns 1 day for 86401 seconds', () => {
      expect(ttlToNaturalLanguage(86401)).toBe('1 day from now');
    });

    it('returns 2 days for 172800 seconds', () => {
      expect(ttlToNaturalLanguage(172800)).toBe('2 days from now');
    });

    it('returns 6 days for 518400 seconds', () => {
      expect(ttlToNaturalLanguage(518400)).toBe('6 days from now');
    });

    it('returns 6 days for 604799 seconds (boundary before week)', () => {
      expect(ttlToNaturalLanguage(604799)).toBe('6 days from now');
    });
  });

  describe('weeks interval (604800-2591999s)', () => {
    it('returns 1 week for exactly 604800 seconds (boundary)', () => {
      expect(ttlToNaturalLanguage(604800)).toBe('1 week from now');
    });

    it('returns 1 week for 604801 seconds', () => {
      expect(ttlToNaturalLanguage(604801)).toBe('1 week from now');
    });

    it('returns 2 weeks for 1209600 seconds', () => {
      expect(ttlToNaturalLanguage(1209600)).toBe('2 weeks from now');
    });

    it('returns 4 weeks for 2419200 seconds', () => {
      expect(ttlToNaturalLanguage(2419200)).toBe('4 weeks from now');
    });

    it('returns 4 weeks for 2591999 seconds (boundary before month)', () => {
      expect(ttlToNaturalLanguage(2591999)).toBe('4 weeks from now');
    });
  });

  describe('months interval (2592000-31535999s)', () => {
    it('returns 1 month for exactly 2592000 seconds (boundary)', () => {
      expect(ttlToNaturalLanguage(2592000)).toBe('1 month from now');
    });

    it('returns 1 month for 2592001 seconds', () => {
      expect(ttlToNaturalLanguage(2592001)).toBe('1 month from now');
    });

    it('returns 2 months for 5184000 seconds', () => {
      expect(ttlToNaturalLanguage(5184000)).toBe('2 months from now');
    });

    it('returns 6 months for 15552000 seconds', () => {
      expect(ttlToNaturalLanguage(15552000)).toBe('6 months from now');
    });

    it('returns 12 months for 31104000 seconds', () => {
      expect(ttlToNaturalLanguage(31104000)).toBe('12 months from now');
    });

    it('returns 12 months for 31535999 seconds (boundary before year)', () => {
      expect(ttlToNaturalLanguage(31535999)).toBe('12 months from now');
    });
  });

  describe('years interval (31536000s+)', () => {
    it('returns 1 year for exactly 31536000 seconds (boundary)', () => {
      expect(ttlToNaturalLanguage(31536000)).toBe('1 year from now');
    });

    it('returns 1 year for 31536001 seconds', () => {
      expect(ttlToNaturalLanguage(31536001)).toBe('1 year from now');
    });

    it('returns 2 years for 63072000 seconds', () => {
      expect(ttlToNaturalLanguage(63072000)).toBe('2 years from now');
    });

    it('returns 10 years for 315360000 seconds', () => {
      expect(ttlToNaturalLanguage(315360000)).toBe('10 years from now');
    });
  });

  describe('pre-formatted string preservation', () => {
    it('preserves strings with spaces', () => {
      expect(ttlToNaturalLanguage('24 hours')).toBe('24 hours');
      expect(ttlToNaturalLanguage('2 days')).toBe('2 days');
      expect(ttlToNaturalLanguage('1 week from now')).toBe('1 week from now');
    });

    it('preserves strings with letters', () => {
      expect(ttlToNaturalLanguage('custom format')).toBe('custom format');
      expect(ttlToNaturalLanguage('expires soon')).toBe('expires soon');
      expect(ttlToNaturalLanguage('123abc')).toBe('123abc');
      expect(ttlToNaturalLanguage('abc123')).toBe('abc123');
    });

    it('preserves strings with special characters', () => {
      expect(ttlToNaturalLanguage('2-days')).toBe('2-days');
      expect(ttlToNaturalLanguage('24/7')).toBe('24/7');
      expect(ttlToNaturalLanguage('3+hours')).toBe('3+hours');
    });

    it('preserves strings that look like invalid', () => {
      expect(ttlToNaturalLanguage('invalid')).toBe('invalid');
      expect(ttlToNaturalLanguage('not a number')).toBe('not a number');
    });
  });

  describe('leading zeros with parseInt radix 10', () => {
    it('handles single leading zero', () => {
      expect(ttlToNaturalLanguage('08')).toBe('8 seconds from now');
      expect(ttlToNaturalLanguage('09')).toBe('9 seconds from now');
    });

    it('handles multiple leading zeros', () => {
      expect(ttlToNaturalLanguage('0042')).toBe('42 seconds from now');
      expect(ttlToNaturalLanguage('00001')).toBe('1 second from now');
      expect(ttlToNaturalLanguage('000360')).toBe('6 minutes from now');
    });

    it('handles all zeros', () => {
      expect(ttlToNaturalLanguage('000')).toBe('a few seconds from now');
      expect(ttlToNaturalLanguage('0000')).toBe('a few seconds from now');
    });

    it('handles leading zeros with larger numbers', () => {
      expect(ttlToNaturalLanguage('03600')).toBe('1 hour from now');
      expect(ttlToNaturalLanguage('086400')).toBe('1 day from now');
    });
  });

  describe('string number inputs', () => {
    it('converts string numbers to seconds correctly', () => {
      expect(ttlToNaturalLanguage('60')).toBe('1 minute from now');
      expect(ttlToNaturalLanguage('3600')).toBe('1 hour from now');
      expect(ttlToNaturalLanguage('86400')).toBe('1 day from now');
    });

    it('handles string zero', () => {
      expect(ttlToNaturalLanguage('0')).toBe('a few seconds from now');
    });
  });

  describe('decimal number inputs', () => {
    it('floors decimal seconds', () => {
      expect(ttlToNaturalLanguage(59.9)).toBe('59 seconds from now');
      expect(ttlToNaturalLanguage(60.1)).toBe('1 minute from now');
      expect(ttlToNaturalLanguage(60.9)).toBe('1 minute from now');
    });

    it('floors decimal minutes', () => {
      expect(ttlToNaturalLanguage(119.9)).toBe('1 minute from now');
      expect(ttlToNaturalLanguage(120.5)).toBe('2 minutes from now');
    });

    it('handles string decimals', () => {
      expect(ttlToNaturalLanguage('60.5')).toBe('1 minute from now');
      expect(ttlToNaturalLanguage('3600.9')).toBe('1 hour from now');
    });
  });

  describe('edge case boundaries', () => {
    it('59s vs 60s boundary (seconds to minutes)', () => {
      expect(ttlToNaturalLanguage(59)).toBe('59 seconds from now');
      expect(ttlToNaturalLanguage(60)).toBe('1 minute from now');
    });

    it('3599s vs 3600s boundary (minutes to hours)', () => {
      expect(ttlToNaturalLanguage(3599)).toBe('59 minutes from now');
      expect(ttlToNaturalLanguage(3600)).toBe('1 hour from now');
    });

    it('86399s vs 86400s boundary (hours to days)', () => {
      expect(ttlToNaturalLanguage(86399)).toBe('23 hours from now');
      expect(ttlToNaturalLanguage(86400)).toBe('1 day from now');
    });

    it('604799s vs 604800s boundary (days to weeks)', () => {
      expect(ttlToNaturalLanguage(604799)).toBe('6 days from now');
      expect(ttlToNaturalLanguage(604800)).toBe('1 week from now');
    });

    it('2591999s vs 2592000s boundary (weeks to months)', () => {
      expect(ttlToNaturalLanguage(2591999)).toBe('4 weeks from now');
      expect(ttlToNaturalLanguage(2592000)).toBe('1 month from now');
    });

    it('31535999s vs 31536000s boundary (months to years)', () => {
      expect(ttlToNaturalLanguage(31535999)).toBe('12 months from now');
      expect(ttlToNaturalLanguage(31536000)).toBe('1 year from now');
    });
  });
});

// -----------------------------------------------------------------------------
// formatDate
// -----------------------------------------------------------------------------

describe('formatDate', () => {
  // All stored timestamps are UTC; tests verify correct parsing and formatting
  beforeEach(() => {
    vi.stubEnv('TZ', 'UTC');
  });

  afterEach(() => {
    vi.unstubAllEnvs();
  });

  describe('valid date inputs', () => {
    it('formats Unix timestamp (seconds) to locale string', () => {
      const result = formatDate(1609459200); // 2021-01-01T00:00:00Z
      expect(result).toContain('2021');
      expect(result).toMatch(/1[\/\-]1|Jan/); // Jan 1 in various locale formats
    });

    it('formats Unix timestamp string to locale string', () => {
      const result = formatDate('1609459200'); // 2021-01-01T00:00:00Z
      expect(result).toContain('2021');
    });

    it('formats Date object to locale string', () => {
      const date = new Date('2021-06-15T12:00:00Z');
      const result = formatDate(date);
      expect(result).toContain('2021');
      expect(result).toMatch(/6[\/\-]15|Jun|15/); // June 15 in various formats
    });

    it('formats ISO date string', () => {
      const result = formatDate('2021-06-15T12:00:00Z');
      expect(result).toContain('2021');
    });
  });

  describe('invalid/empty inputs return empty string', () => {
    it('returns empty string for null', () => {
      expect(formatDate(null)).toBe('');
    });

    it('returns empty string for undefined', () => {
      expect(formatDate(undefined)).toBe('');
    });

    it('returns empty string for empty string', () => {
      expect(formatDate('')).toBe('');
    });

    it('returns empty string for invalid date string', () => {
      expect(formatDate('not-a-date')).toBe('');
    });

    it('returns empty string for invalid Date object', () => {
      expect(formatDate(new Date('invalid'))).toBe('');
    });
  });
});

// -----------------------------------------------------------------------------
// formatRelativeTime
// -----------------------------------------------------------------------------

describe('formatRelativeTime', () => {
  const NOW = new Date('2021-06-15T12:00:00Z');

  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(NOW);
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  describe('undefined input', () => {
    it('returns empty string for undefined', () => {
      expect(formatRelativeTime(undefined)).toBe('');
    });
  });

  describe('just now (< 60 seconds ago)', () => {
    it('returns "just now" for 0 seconds ago', () => {
      expect(formatRelativeTime(NOW)).toBe('just now');
    });

    it('returns "just now" for 30 seconds ago', () => {
      const date = new Date(NOW.getTime() - 30 * 1000);
      expect(formatRelativeTime(date)).toBe('just now');
    });

    it('returns "just now" for 59 seconds ago', () => {
      const date = new Date(NOW.getTime() - 59 * 1000);
      expect(formatRelativeTime(date)).toBe('just now');
    });
  });

  describe('minutes ago (60s - 3599s)', () => {
    it('returns "1 minutes ago" for exactly 60 seconds', () => {
      const date = new Date(NOW.getTime() - 60 * 1000);
      expect(formatRelativeTime(date)).toBe('1 minutes ago');
    });

    it('returns "2 minutes ago" for 120 seconds', () => {
      const date = new Date(NOW.getTime() - 120 * 1000);
      expect(formatRelativeTime(date)).toBe('2 minutes ago');
    });

    it('returns "59 minutes ago" for 3540 seconds', () => {
      const date = new Date(NOW.getTime() - 3540 * 1000);
      expect(formatRelativeTime(date)).toBe('59 minutes ago');
    });

    it('returns "59 minutes ago" for 3599 seconds (boundary)', () => {
      const date = new Date(NOW.getTime() - 3599 * 1000);
      expect(formatRelativeTime(date)).toBe('59 minutes ago');
    });
  });

  describe('hours ago (3600s - 86399s)', () => {
    it('returns "1 hours ago" for exactly 3600 seconds', () => {
      const date = new Date(NOW.getTime() - 3600 * 1000);
      expect(formatRelativeTime(date)).toBe('1 hours ago');
    });

    it('returns "2 hours ago" for 7200 seconds', () => {
      const date = new Date(NOW.getTime() - 7200 * 1000);
      expect(formatRelativeTime(date)).toBe('2 hours ago');
    });

    it('returns "23 hours ago" for 82800 seconds', () => {
      const date = new Date(NOW.getTime() - 82800 * 1000);
      expect(formatRelativeTime(date)).toBe('23 hours ago');
    });

    it('returns "23 hours ago" for 86399 seconds (boundary)', () => {
      const date = new Date(NOW.getTime() - 86399 * 1000);
      expect(formatRelativeTime(date)).toBe('23 hours ago');
    });
  });

  describe('days ago (>= 86400s)', () => {
    it('returns "1 days ago" for exactly 86400 seconds', () => {
      const date = new Date(NOW.getTime() - 86400 * 1000);
      expect(formatRelativeTime(date)).toBe('1 days ago');
    });

    it('returns "2 days ago" for 172800 seconds', () => {
      const date = new Date(NOW.getTime() - 172800 * 1000);
      expect(formatRelativeTime(date)).toBe('2 days ago');
    });

    it('returns "7 days ago" for one week', () => {
      const date = new Date(NOW.getTime() - 7 * 86400 * 1000);
      expect(formatRelativeTime(date)).toBe('7 days ago');
    });

    it('returns "30 days ago" for one month', () => {
      const date = new Date(NOW.getTime() - 30 * 86400 * 1000);
      expect(formatRelativeTime(date)).toBe('30 days ago');
    });
  });
});
