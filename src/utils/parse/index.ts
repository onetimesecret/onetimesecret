// src/utils/parse/index.ts

/**
 * Core parsing utilities for converting unknown values to typed data.
 * Used primarily for API/form data processing and schema validation.
 */

export * from './date';

export function parseBoolean(val: unknown): boolean {
  if (val === null || val === undefined || val === '') return false;
  if (typeof val === 'boolean') return val;
  return val === 'true' || val === '1';
}

export function parseNumber(val: unknown): number | null {
  if (val === null || val === undefined || val === '') return null;
  if (typeof val === 'number') return val;
  const num = Number(val);
  return isNaN(num) ? null : num;
}

export function parseNestedObject(val: unknown) {
  return val && typeof val === 'object' && Object.keys(val).length > 0 ? val : {}; // default to empty object
}
