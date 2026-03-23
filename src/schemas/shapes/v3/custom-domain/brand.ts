// src/schemas/shapes/v3/custom-domain/brand.ts
//
// V3 wire-format shapes for brand settings.
// Derives from contracts, adding V3-specific transforms.

import {
  brandSettingsCanonical,
  imagePropsCanonical,
} from '@/schemas/contracts';
import { z } from 'zod';

// ─────────────────────────────────────────────────────────────────────────────
// V3 brand settings shape
// ─────────────────────────────────────────────────────────────────────────────

/**
 * V3 brand settings record.
 *
 * V3 sends native types - booleans are native, no string transforms needed.
 * Extends contract with defaults for optional fields.
 *
 * @example
 * ```typescript
 * const brand = brandSettingsRecord.parse({
 *   primary_color: '#dc4a22',
 *   font_family: 'sans',
 *   button_text_light: false,
 * });
 * ```
 */
export const brandSettingsRecord = brandSettingsCanonical.extend({
  // V3 sends native booleans, add defaults
  button_text_light: z.boolean().default(false),
  allow_public_homepage: z.boolean().default(false),
  allow_public_api: z.boolean().default(false),
  passphrase_required: z.boolean().default(false),
  notify_enabled: z.boolean().default(false),
});

/**
 * V3 image properties record.
 *
 * Image metadata for logo and icon fields.
 */
export const imagePropsRecord = imagePropsCanonical;

// ─────────────────────────────────────────────────────────────────────────────
// Type exports
// ─────────────────────────────────────────────────────────────────────────────

/** TypeScript type for V3 brand settings record. */
export type BrandSettingsRecord = z.infer<typeof brandSettingsRecord>;

/** TypeScript type for V3 image properties record. */
export type ImagePropsRecord = z.infer<typeof imagePropsRecord>;
