// src/schemas/transforms/index.ts

/**
 * Core string transformers for API/Redis data conversion.
 *
 * These transforms handle the conversion of wire-format data (strings from APIs/Redis)
 * into typed domain values (Date, number, boolean) for use in Vue components and Pinia stores.
 *
 * Uses z.string().transform() over z.coerce() because:
 *
 * 1. Explicit handling of null/undefined/empty strings
 * 2. Support for Redis bool formats ("0"/"1", "true"/"false")
 * 3. Unix timestamp string conversion to JS dates
 *
 * Space characters (spaces, tabs, newlines) are handled in UI components:
 * - Preserves data fidelity
 * - Keeps schema validation separate from display formatting
 * - Allows field-specific space handling
 *
 * Note: This level of detail is standard practice for large apps.
 * It centralizes conversions, handles edge cases, and ensures
 * consistency across the codebase.
 *
 * @category Transforms
 * @see {@link parseBoolean} - Boolean parsing utility
 * @see {@link parseDateValue} - Date parsing utility
 * @see {@link parseNumber} - Number parsing utility
 *
 * @example
 * ```typescript
 * import { transforms } from '@/schemas/transforms';
 * import { z } from 'zod';
 *
 * // Use in a schema definition
 * const mySchema = z.object({
 *   created: transforms.fromString.date,
 *   count: transforms.fromString.number,
 *   isActive: transforms.fromString.boolean,
 * });
 *
 * // Parse API response
 * const data = mySchema.parse({
 *   created: "1609459200",  // Unix timestamp string
 *   count: "42",
 *   isActive: "true",
 * });
 * // Result: { created: Date, count: 42, isActive: true }
 * ```
 */

import { fromNumber } from './from-number';
import { fromObject } from './from-object';
import { fromString } from './from-string';

export const transforms = {
  fromString,
  fromNumber,
  fromObject,
} as const;

// Re-export individual modules for direct imports if needed
export { fromNumber, fromObject, fromString };
