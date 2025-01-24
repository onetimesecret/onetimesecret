// src/utils/parse/date.ts

/**
 * Date parsing utilities handling timestamps and date strings.
 * Converts various date formats to Date objects with validation.
 *
 * @test tests/unit/vue/utils/parse.spec.ts
 */

/**
 *
 * Handles unix time in seconds or milliseconds, and ISO date strings.
 */
/* eslint-disable complexity */
/* eslint-disable max-depth */
export const parseDateValue = (val: unknown): Date | null => {
  if (val === null || val === undefined || val === '') return null;
  if (val instanceof Date && !isNaN(val.getTime())) return val;

  try {
    // Handle string inputs
    if (typeof val === 'string') {
      // Try ISO string first
      if (val.includes('T') || val.includes('-')) {
        const date = new Date(val);
        if (!isNaN(date.getTime())) return date;
      }

      // Try timestamp (both seconds and milliseconds)
      const num = parseInt(val, 10);
      if (!isNaN(num)) {
        // If length > 10, assume milliseconds, otherwise assume seconds
        const date = new Date(String(num).length > 10 ? num : num * 1000);
        if (!isNaN(date.getTime())) return date;
      }
    }

    // Handle number inputs
    if (typeof val === 'number') {
      // If length > 10, assume milliseconds, otherwise assume seconds
      const date = new Date(String(val).length > 10 ? val : val * 1000);
      if (!isNaN(date.getTime())) return date;
    }
  } catch (e) {
    // If any parsing fails, return null
    // NOTE: Send to log somewhere so it's not a silent killer
    console.error('[parseDateValue] Failed to parse date value:', val, e);
    return null;
  }

  return null;
};

export const formatLocalDateTime = (date: Date): string =>
  date.toLocaleString(undefined, {
    year: 'numeric',
    month: 'numeric',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  });

// original:
// export const parseDateValue = (val: unknown): Date | null => {
//   if (val === null || val === undefined || val === '') return null;
//   if (val instanceof Date) return val;

//   // If string, try parsing as ISO date first
//   if (typeof val === 'string') {
//     // Check if it's an ISO date string format
//     if (val.includes('T') || val.includes('-')) {
//       const dateFromString = new Date(val);
//       if (!isNaN(dateFromString.getTime())) {
//         return dateFromString;
//       }
//     }

//     // If not ISO format, try as timestamp
//     const timestamp = parseInt(val, 10);
//     if (!isNaN(timestamp)) {
//       return new Date(timestamp * 1000); // Convert seconds to milliseconds
//     }
//     return null;
//   }

//   // If number, treat as timestamp
//   if (typeof val === 'number') {
//     return new Date(val * 1000); // Convert seconds to milliseconds
//   }

//   return null;
// };
