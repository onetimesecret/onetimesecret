// src/schemas/shapes/v2/custom-domain/brand.ts
//
// V2 wire-format shapes for brand settings.
// Uses string transforms for boolean fields (V2 sends "true"/"false" strings).

import { localeSchema } from '@/schemas/i18n/locale';
import { transforms } from '@/schemas/transforms';
import { fontFamilyValues, cornerStyleValues } from '@/schemas/contracts';
import { z } from 'zod';

// Re-export UI helpers from shared location for backward compatibility.
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
// V2 brand settings schema
// ─────────────────────────────────────────────────────────────────────────────

/**
 * V2 brand settings schema.
 *
 * V2 sends booleans as strings ("true"/"false"), so we use string transforms.
 * All fields are partial (optional) for PATCH-style updates.
 *
 * @deprecated Use brandSettingsSchema (correct spelling with capital S)
 *
 * @example
 * ```typescript
 * const brand = brandSettingsSchema.parse({
 *   primary_color: '#dc4a22',
 *   button_text_light: 'false', // V2 sends as string
 * });
 * ```
 */
export const brandSettingschema = z
  .object({
    primary_color: z
      .string()
      .regex(/^#[0-9A-F]{6}$/i, 'Invalid hex color')
      .default('#dc4a22'), // Default to Onetime Secret brand colour
    colour: z.string().optional(),
    instructions_pre_reveal: z.string().nullish(),
    instructions_reveal: z.string().nullish(),
    instructions_post_reveal: z.string().nullish(),
    description: z.string().optional(),
    button_text_light: transforms.fromString.boolean.default(false),
    allow_public_homepage: transforms.fromString.boolean.default(false),
    allow_public_api: transforms.fromString.boolean.default(false),
    font_family: z.enum(fontFamilyValues).default('sans'),
    corner_style: z.enum(cornerStyleValues).default('rounded'),
    locale: localeSchema.default('en'),
    default_ttl: transforms.fromString.number.nullish(),
    passphrase_required: transforms.fromString.boolean.default(false),
    notify_enabled: transforms.fromString.boolean.default(false),
  })
  .partial(); // Makes all fields optional

/**
 * V2 image properties schema.
 *
 * Image metadata for logo and icon fields. V2 sends numeric fields as strings.
 */
export const imagePropsSchema = z
  .object({
    encoded: z.string().optional(),
    content_type: z.string().optional(),
    filename: z.string().optional(),
    bytes: transforms.fromString.number.optional(),
    width: transforms.fromString.number.optional(),
    height: transforms.fromString.number.optional(),
    ratio: transforms.fromString.number.optional(),
  })
  .partial(); // Makes all fields optional

// ─────────────────────────────────────────────────────────────────────────────
// Type exports
// ─────────────────────────────────────────────────────────────────────────────

/** TypeScript type for V2 brand settings. */
export type BrandSettings = z.infer<typeof brandSettingschema>;

/** TypeScript type for V2 image properties. */
export type ImageProps = z.infer<typeof imagePropsSchema>;

// Correct spelling alias for migration
export { brandSettingschema as brandSettingsSchema };
