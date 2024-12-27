// src/utils/parse/date.ts

/**
 * Date parsing utilities handling timestamps and date strings.
 * Converts various date formats to Date objects with validation.
 */

export const parseDateValue = (val: unknown): Date | null => {
  if (val === null || val === undefined || val === '') return null;
  if (val instanceof Date) return val;

  // If string, try parsing as ISO date first
  if (typeof val === 'string') {
    // Check if it's an ISO date string format
    if (val.includes('T') || val.includes('-')) {
      const dateFromString = new Date(val);
      if (!isNaN(dateFromString.getTime())) {
        return dateFromString;
      }
    }

    // If not ISO format, try as timestamp
    const timestamp = parseInt(val, 10);
    if (!isNaN(timestamp)) {
      return new Date(timestamp * 1000); // Convert seconds to milliseconds
    }
    return null;
  }

  // If number, treat as timestamp
  if (typeof val === 'number') {
    return new Date(val * 1000); // Convert seconds to milliseconds
  }

  return null;
};
