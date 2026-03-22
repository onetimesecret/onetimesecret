// src/utils/format/index.ts

import { format } from 'date-fns';
import { getBootstrapValue } from '@/services/bootstrap.service';
import { parseDateValue } from '../parse/date';

// Track patterns that have already warned to avoid console spam
const warnedPatterns = new Set<string>();

/**
 * Safely format a date with a date-fns pattern, falling back on error.
 * Invalid patterns will log a warning once and use the fallback.
 */
const safeFormat = (date: Date, pattern: string, fallback: () => string): string => {
  try {
    return format(date, pattern);
  } catch (e) {
    if (!warnedPatterns.has(pattern)) {
      warnedPatterns.add(pattern);
      console.warn(`Invalid date format pattern "${pattern}", using fallback.`, e);
    }
    return fallback();
  }
};

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
 * Format a Date object as ISO8601 date only: yyyy-MM-dd
 */
export const formatISODate = (date: Date): string => format(date, 'yyyy-MM-dd');

/**
 * Format a Date object as ISO8601 date and time: yyyy-MM-dd HH:mm:ss
 */
export const formatISODateTime = (date: Date): string => format(date, 'yyyy-MM-dd HH:mm:ss');

/**
 * Regional date format presets.
 *
 * These shorthand keywords resolve to date-fns format patterns so that
 * operators don't need to memorize token syntax. Each entry provides a
 * date-only pattern and a date+time pattern.
 *
 *  Keyword   | Date           | DateTime                | Region
 *  ----------|----------------|-------------------------|---------------------------
 *  iso8601   | 2026-03-21     | 2026-03-21 14:30:00     | International / technical
 *  us        | 03/21/2026     | 03/21/2026 2:30:00 PM   | United States
 *  eu        | 21/03/2026     | 21/03/2026 14:30        | Most of Europe (slash)
 *  eu-dot    | 21.03.2026     | 21.03.2026 14:30        | Germany, Austria, CH, etc.
 *  uk        | 21 Mar 2026    | 21 Mar 2026 14:30       | UK / Commonwealth
 *  long      | March 21, 2026 | March 21, 2026 2:30 PM  | Formal / editorial
 */
const DATE_FORMAT_PRESETS: Record<string, { date: string; datetime: string }> = {
  iso8601:  { date: 'yyyy-MM-dd',    datetime: 'yyyy-MM-dd HH:mm:ss' },
  us:       { date: 'MM/dd/yyyy',    datetime: 'MM/dd/yyyy h:mm:ss a' },
  eu:       { date: 'dd/MM/yyyy',    datetime: 'dd/MM/yyyy HH:mm' },
  'eu-dot': { date: 'dd.MM.yyyy',    datetime: 'dd.MM.yyyy HH:mm' },
  uk:       { date: 'dd MMM yyyy',   datetime: 'dd MMM yyyy HH:mm' },
  long:     { date: 'MMMM d, yyyy',  datetime: 'MMMM d, yyyy h:mm a' },
};

/**
 * Resolve a format setting to a date-fns pattern string.
 *
 * @param setting - 'locale', a preset keyword, or a raw date-fns pattern
 * @param variant - Whether to resolve the 'date' or 'datetime' pattern
 * @returns The resolved pattern, or null when 'locale' (caller uses browser-native)
 */
function resolveFormatPattern(
  setting: string,
  variant: 'date' | 'datetime',
): string | null {
  if (setting === 'locale') return null;
  const preset = DATE_FORMAT_PRESETS[setting];
  if (preset) return preset[variant];
  return setting; // raw date-fns pattern
}

/**
 * Format a Date as a date-only string, respecting the configured date_format.
 *
 * Accepts:
 * - 'locale' (default): browser-native toLocaleDateString()
 * - A preset keyword: 'iso8601', 'us', 'eu', 'eu-dot', 'uk', 'long'
 * - A date-fns format pattern: e.g. 'dd/MM/yyyy', 'EEEE, MMMM do yyyy'
 *
 * @see https://date-fns.org/docs/format
 */
export const formatDisplayDate = (date: Date): string => {
  const setting = getBootstrapValue('date_format') ?? 'locale';
  const pattern = resolveFormatPattern(setting, 'date');
  return pattern
    ? safeFormat(date, pattern, () => date.toLocaleDateString())
    : date.toLocaleDateString();
};

/**
 * Format a Date as a date+time string.
 *
 * Resolution order:
 * 1. datetime_format (if explicitly set to something other than 'locale')
 * 2. date_format (uses its datetime variant — so a single `date_format: eu`
 *    controls both date-only and datetime display)
 * 3. Falls back to browser-native toLocaleString()
 *
 * Accepts:
 * - 'locale' (default): browser-native toLocaleString()
 * - A preset keyword: 'iso8601', 'us', 'eu', 'eu-dot', 'uk', 'long'
 * - A date-fns format pattern: e.g. 'dd/MM/yyyy HH:mm:ss', 'MMM d, yyyy h:mm a'
 *
 * @see https://date-fns.org/docs/format
 */
export const formatDisplayDateTime = (date: Date): string => {
  const datetimeSetting = getBootstrapValue('datetime_format') ?? 'locale';

  // If datetime_format is explicitly configured, use it directly
  if (datetimeSetting !== 'locale') {
    const pattern = resolveFormatPattern(datetimeSetting, 'datetime');
    return pattern
      ? safeFormat(date, pattern, () => date.toLocaleString())
      : date.toLocaleString();
  }

  // Fall back to date_format's datetime variant (so `date_format: eu` covers both)
  const dateSetting = getBootstrapValue('date_format') ?? 'locale';
  const pattern = resolveFormatPattern(dateSetting, 'datetime');
  return pattern
    ? safeFormat(date, pattern, () => date.toLocaleString())
    : date.toLocaleString();
};

/**
 * Format a date value (seconds/string) to a display string,
 * respecting the configured datetime_format (or date_format fallback).
 */
export const formatDate = (val: unknown): string => {
  const date = parseDateValue(val);
  return date ? formatDisplayDateTime(date) : '';
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
