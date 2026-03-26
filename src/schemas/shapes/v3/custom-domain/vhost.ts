// src/schemas/shapes/v3/custom-domain/vhost.ts
//
// V3 wire-format shapes for vhost.
// Derives from contracts, adding V3-specific transforms.

import { vhostCanonical } from '@/schemas/contracts';
import { transforms } from '@/schemas/transforms';
import { parseDateValue } from '@/utils/parse/index';
import { z } from 'zod';

// ─────────────────────────────────────────────────────────────────────────────
// V3 vhost shape
// ─────────────────────────────────────────────────────────────────────────────

/**
 * V3 vhost schema.
 *
 * Extends contract with timestamp transforms for date fields.
 *
 * IMPORTANT: Vhost data comes verbatim from Approximated API, which returns
 * timestamps as strings (ISO 8601 or similar), NOT Unix epoch numbers.
 * Therefore we use fromString transforms here, not fromNumber.
 *
 * @example
 * ```typescript
 * const vhost = vhostSchema.parse({
 *   status: 'active',
 *   has_ssl: true,
 *   is_resolving: true,
 *   last_monitored_unix: '2021-01-01T00:00:00Z',
 * });
 *
 * console.log(vhost.last_monitored_unix instanceof Date); // true
 * ```
 */
export const vhostSchema = vhostCanonical.extend({
  // V3 sends booleans as native types
  apx_hit: z.boolean().optional(),
  has_ssl: z.boolean().optional(),
  is_resolving: z.boolean().optional(),

  // Approximated API sends timestamps as strings or numbers depending on field.
  // All timestamp fields are optional - external API may omit them,
  // and historical data may predate these fields.
  created_at: transforms.fromString.date.optional(),
  last_monitored_unix: z.union([z.string(), z.number()]).transform((val): Date => {
    const date = parseDateValue(val);
    if (!date) throw new Error('Valid date is required');
    return date;
  }).optional(),
  ssl_active_from: transforms.fromString.dateNullable.optional(),
  ssl_active_until: transforms.fromString.dateNullable.optional(),
});

// ─────────────────────────────────────────────────────────────────────────────
// Type exports
// ─────────────────────────────────────────────────────────────────────────────

/** TypeScript type for V3 vhost. */
export type VHost = z.infer<typeof vhostSchema>;
