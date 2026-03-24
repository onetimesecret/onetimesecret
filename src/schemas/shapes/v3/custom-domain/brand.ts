// src/schemas/shapes/v3/custom-domain/brand.ts
//
// V3 wire-format shapes for brand settings.
// Derives from contracts, adding V3-specific transforms.

import {
  brandSettingsCanonical,
  imagePropsCanonical,
} from '@/schemas/contracts';
import { z } from 'zod';

// Re-export UI helpers from shared location.
// Note: FontFamily and CornerStyle are both const objects and type aliases
// (via declaration merging), so a single export covers both value and type usage.
export {
  CornerStyle,
  cornerStyleClasses,
  cornerStyleDisplayMap,
  cornerStyleIconMap,
  cornerStyleOptions,
  FontFamily,
  fontDisplayMap,
  fontFamilyClasses,
  fontIconMap,
  fontOptions,
} from '@/shared/utils/brand-helpers';

// ─────────────────────────────────────────────────────────────────────────────
// V3 brand settings shape
// ─────────────────────────────────────────────────────────────────────────────

/**
 * V3 brand settings schema.
 *
 * V3 sends native types - booleans are native, no string transforms needed.
 * Extends contract with defaults for optional fields.
 *
 * @example
 * ```typescript
 * const brand = brandSettingsSchema.parse({
 *   primary_color: '#dc4a22',
 *   font_family: 'sans',
 *   button_text_light: false,
 * });
 * ```
 */
export const brandSettingsSchema = brandSettingsCanonical.extend({
  // V3 sends native booleans, add defaults
  button_text_light: z.boolean().default(false),
  allow_public_homepage: z.boolean().default(false),
  allow_public_api: z.boolean().default(false),
  passphrase_required: z.boolean().default(false),
  notify_enabled: z.boolean().default(false),
});

/**
 * V3 image properties schema.
 *
 * Image metadata for logo and icon fields.
 */
export const imagePropsSchema = imagePropsCanonical;

// ─────────────────────────────────────────────────────────────────────────────
// Type exports
// ─────────────────────────────────────────────────────────────────────────────

/** TypeScript type for V3 brand settings. */
export type BrandSettings = z.infer<typeof brandSettingsSchema>;

/** TypeScript type for V3 image properties. */
export type ImageProps = z.infer<typeof imagePropsSchema>;
