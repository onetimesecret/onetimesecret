// src/utils/format/index.ts

import { parseDateValue } from '../parse/date';

/**
 * Time duration formatting utilities.
 * Converts numeric durations to human-readable strings.
 */

/**
 * Transforms time-to-live values into human readable strings
 * Only transforms numeric values - preserves any existing string formatting
 * Uses radix 10 for string parsing to handle leading zeros correctly.
 * @param val - Raw TTL value (number in seconds) or pre-formatted string
 * @returns Formatted duration string or null
 * @example
 * ttlToNaturalLanguage(3600) // "1 hour from now"
 * ttlToNaturalLanguage("86400") // "1 day from now"
 * ttlToNaturalLanguage("08") // "8 seconds from now"
 * ttlToNaturalLanguage(-1) // null
 */
export function ttlToNaturalLanguage(val: unknown): string | null {
  if (val === null || val === undefined) return null;

  // If string with any non-numeric characters, preserve as-is
  if (typeof val === 'string' && /[^0-9.]/.test(val)) {
    return val;
  }

  // Parse number, using parseInt with radix 10 for strings to handle leading zeros
  //
  // The difference between `parseInt()` and `Number()`:
  // - `parseInt('08', 10)` correctly gives `8`
  // - `Number('08')` also gives `8` but doesn't handle octal notation in older JS engines
  // - Using `parseInt` with radix 10 is more explicit about our decimal number intentions
  //
  const seconds =
    typeof val === 'string'
      ? parseInt(val, 10) // Use radix 10 for strings (handles "08" correctly)
      : Number(val); // Use Number() for other types

  if (isNaN(seconds) || seconds < 0) return null;

  const intervals = [
    { label: 'year', seconds: 31536000 },
    { label: 'month', seconds: 2592000 },
    { label: 'week', seconds: 604800 },
    { label: 'day', seconds: 86400 },
    { label: 'hour', seconds: 3600 },
    { label: 'minute', seconds: 60 },
    { label: 'second', seconds: 1 },
  ];

  for (const interval of intervals) {
    const count = Math.floor(seconds / interval.seconds);
    if (count >= 1) {
      return count === 1
        ? `1 ${interval.label} from now`
        : `${count} ${interval.label}s from now`;
    }
  }
  return 'a few seconds from now';
}

/**
 * Format a date value (seconds/string) to localized string
 */
export const formatDate = (val: unknown): string => {
  const date = parseDateValue(val);
  return date?.toLocaleString() ?? '';
};

/**
 * Format a date as a relative time string (e.g. "2 hours ago")
 */
export const formatRelativeTime = (date: Date | undefined): string => {
  if (!date) return '';

  const now = new Date();
  const diffInSeconds = Math.floor((now.getTime() - date.getTime()) / 1000);

  if (diffInSeconds < 60) return 'just now';
  if (diffInSeconds < 3600) return `${Math.floor(diffInSeconds / 60)} minutes ago`;
  if (diffInSeconds < 86400) return `${Math.floor(diffInSeconds / 3600)} hours ago`;
  return `${Math.floor(diffInSeconds / 86400)} days ago`;
};
