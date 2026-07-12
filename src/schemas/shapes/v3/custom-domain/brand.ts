// src/schemas/shapes/v3/custom-domain/brand.ts
//
// V3 wire-format shapes for brand settings.
// Derives from contracts, adding V3-specific transforms.

import {
  brandSettingsCanonical,
  imagePropsCanonical,
  isValidBorderRadius,
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
 *   primary_color: '#3B82F6',
 *   font_family: 'sans',
 *   button_text_light: false,
 * });
 * ```
 */
export const brandSettingsSchema = brandSettingsCanonical.extend({
  // V3 sends native booleans, add defaults.
  // allow_public_homepage / allow_public_api are intentionally absent — they
  // were retired from BrandSettings in #3026; consume HomepageConfig.enabled
  // and ApiConfig.enabled (e.g. via the identity store / homepage_config
  // response field) instead.
  // Default true to match the canonical contract (brand-config.ts) and
  // NEUTRAL_BRAND_DEFAULTS. A false default here silently shadowed the
  // identityStore fallback (`brand?.button_text_light ?? DEFAULT_BUTTON_TEXT_LIGHT`),
  // so unbranded domains rendered dark button text instead of the intended light.
  button_text_light: z.boolean().default(true),
  passphrase_required: z.boolean().default(false),
  notify_enabled: z.boolean().default(false),

  // Read-tolerance for a cosmetic field. The canonical contract REJECTS an
  // invalid border_radius (that strictness is the save/write authority, mirrored
  // by the Ruby `validate_border_radius_field!` on PUT). But a stale value in an
  // already-stored brand record (e.g. the retired `'custom'`/`'full'` presets)
  // must NOT fail the whole domain response and brick loading — the field is
  // purely visual. On READ we coerce an unrecognized value to `undefined`
  // (unset → falls back to corner_style/default), exactly as `borderRadiusToCss`
  // already returns null for it. Valid presets/px pass through untouched.
  border_radius: z
    .union([z.string(), z.number()])
    .transform((val) => (isValidBorderRadius(val) ? val : undefined))
    .nullish(),
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
