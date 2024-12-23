// src/utils/parse/date.ts

/**
 * Date parsing utilities handling timestamps and date strings.
 * Converts various date formats to Date objects with validation.
 */

export const parseDateValue = (val: unknown): Date | null => {
  if (val === null || val === undefined || val === '') return null;
  if (val instanceof Date) return val;

  let timestamp: number;
  if (typeof val === 'string') {
    // Try parsing as timestamp first
    timestamp = parseInt(val, 10);
    // If not a valid timestamp, try as date string
    if (isNaN(timestamp)) {
      const dateFromString = new Date(val);
      return isNaN(dateFromString.getTime()) ? null : dateFromString;
    }
  } else {
    timestamp = val as number;
  }

  return isNaN(timestamp) ? null : new Date(timestamp * 1000);
};
