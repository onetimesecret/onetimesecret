
import { z } from 'zod';

/**
 * Zod schema for transforming various date inputs to Date objects
 * Handles:
 * - Unix timestamps (seconds)
 * - ISO strings
 * - Date objects
 */
export const dateSchema = z.union([
  z.date(),
  z.number().transform(seconds => new Date(seconds * 1000)),
  z.string().transform(val => {
    const num = Number(val);
    if (!isNaN(num)) {
      return new Date(num * 1000); // Assume seconds
    }
    const date = new Date(val);
    if (isNaN(date.getTime())) {
      throw new Error('Invalid date string format');
    }
    return date;
  })
]);

/**
 * Transform any supported date format to a Date object
 * @throws {Error} if value cannot be converted to a valid date
 */
export const toDate = (val: unknown): Date => {
  try {
    return dateSchema.parse(val);
  } catch {
    throw new Error(`Invalid date value: ${String(val)}`);
  }
};

/**
 * Format a date value (seconds/string) to localized string
 */
export const formatDate = (val: unknown): string => {
  const date = toDate(val);
  return date.toLocaleString();
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
