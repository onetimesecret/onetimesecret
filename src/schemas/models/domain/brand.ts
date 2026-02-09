// src/schemas/models/domain/brand.ts

import { localeCodeSchema } from '@/schemas/i18n/locale';
import { transforms } from '@/schemas/transforms';
import { z } from 'zod';

/**
 * Strips HTML tags from a string for XSS prevention at the schema boundary.
 * Defense-in-depth: primary sanitization happens server-side in Ruby (Sanitize gem).
 * This regex approach is adequate because these fields only receive API response
 * data that the backend already sanitized. If these fields ever accept direct
 * user input on the frontend (bypassing the API), replace this with DOMPurify
 * or the browser's native DOMParser.
 * @param val - The string value to sanitize, or null/undefined
 * @returns The sanitized string with HTML tags removed, or null/undefined
 */
function stripHtmlTags(val: string | null | undefined): string | null | undefined {
  if (val == null) return val;
  // Loop until stable to handle nested tags like <scr<script>ipt>
  let result = val;
  let prev: string;
  do {
    prev = result;
    result = result.replace(/<[^>]*>/g, '');
  } while (result !== prev);
  // Strip stray angle brackets left by split-tag attacks
  return result.replace(/[<>]/g, '').trim();
}

/**
 * @fileoverview Brand settings schema for API transformation boundaries
 *
 * Model Organization:
 * While Brand is a nested model of Domain, it exists as a separate file because:
 * 1. It has distinct validation rules and complex type definitions
 * 2. It maintains separation of concerns and code organization
 * 3. It allows direct imports of Brand-specific logic where needed
 * 4. It keeps Domain model focused on core domain logic
 *
 * Default Value Strategy:
 * This schema intentionally avoids Zod .default() for primary_color.
 * The schema's job is validation (is this a valid hex color?), not
 * defaulting. Default resolution is handled by identityStore's
 * 3-step fallback chain:
 *
 *   1. domain_branding.primary_color  (per-domain, from Redis)
 *   2. bootstrapStore.brand_primary_color  (per-installation, from config)
 *   3. NEUTRAL_BRAND_DEFAULTS.primary_color  (hardcoded fallback)
 *
 * If the schema eagerly fills in a default via .default(), the nullish
 * coalescing (??) in the fallback chain never reaches step 2, making
 * the global brand config ineffective. This matters for:
 *   - Multi-tenant: domains without a color fall through to the
 *     installation default (step 2) or the hardcoded default (step 3)
 *   - Single-tenant elite: the installation sets its brand color in
 *     config (step 2), and the schema must not mask it
 */

// 1. Base enums
enum FontFamily {
  SANS = 'sans',
  SERIF = 'serif',
  MONO = 'mono',
}

enum CornerStyle {
  ROUNDED = 'rounded',
  PILL = 'pill',
  SQUARE = 'square',
}

// 2. Options arrays
const fontOptions = Object.values(FontFamily) as [string, ...string[]];
const cornerStyleOptions = Object.values(CornerStyle) as [string, ...string[]];

// 3. Display maps
const fontDisplayMap: Record<FontFamily, string> = {
  [FontFamily.SANS]: 'Sans Serif',
  [FontFamily.SERIF]: 'Serif',
  [FontFamily.MONO]: 'Monospace',
};

export const fontFamilyClasses: Record<FontFamily, string> = {
  [FontFamily.SANS]: 'font-sans',
  [FontFamily.SERIF]: 'font-serif',
  [FontFamily.MONO]: 'font-mono',
};

export const cornerStyleClasses: Record<CornerStyle, string> = {
  [CornerStyle.ROUNDED]: 'rounded-md',
  [CornerStyle.PILL]: 'rounded-xl',
  [CornerStyle.SQUARE]: 'rounded-none',
};

const cornerStyleDisplayMap: Record<CornerStyle, string> = {
  [CornerStyle.ROUNDED]: 'Rounded',
  [CornerStyle.PILL]: 'Pill Shape',
  [CornerStyle.SQUARE]: 'Square',
};

// 4. Icon maps
const fontIconMap: Record<FontFamily, string> = {
  [FontFamily.SANS]: 'ph-text-aa-bold',
  [FontFamily.SERIF]: 'ph-text-t-bold',
  [FontFamily.MONO]: 'ph-code',
};

const cornerStyleIconMap: Record<CornerStyle, string> = {
  [CornerStyle.ROUNDED]: 'tabler-border-corner-rounded',
  [CornerStyle.PILL]: 'tabler-border-corner-pill',
  [CornerStyle.SQUARE]: 'tabler-border-corner-square',
};

export const brandSettingSchema = z
  .object({
    primary_color: z
      .string()
      .regex(/^#(?:[0-9A-F]{6}|[0-9A-F]{3})$/i, 'Invalid hex color')
      .transform((val) => {
        // Normalize 3-digit hex to 6-digit (e.g. #F00 -> #FF0000)
        if (val && /^#[0-9A-F]{3}$/i.test(val)) {
          const [, r, g, b] = val.split('');
          return `#${r}${r}${g}${g}${b}${b}`.toUpperCase();
        }
        return val;
      })
      .nullish(), // No default here — identityStore fallback chain handles defaults
    colour: z.string().optional(),
    product_name: z.string().transform(stripHtmlTags).nullish(),
    product_domain: z.string().nullish(),
    support_email: z.string().email().nullish(),
    footer_text: z.string().transform(stripHtmlTags).nullish(),
    logo_url: z.string().url().nullish(),
    logo_dark_url: z.string().url().nullish(),
    favicon_url: z.string().url().nullish(),
    instructions_pre_reveal: z.string().transform(stripHtmlTags).nullish(),
    instructions_reveal: z.string().transform(stripHtmlTags).nullish(),
    instructions_post_reveal: z.string().transform(stripHtmlTags).nullish(),
    description: z.string().transform(stripHtmlTags).optional(),
    button_text_light: transforms.fromString.boolean.default(true),
    allow_public_homepage: transforms.fromString.boolean.nullish(), // No default — identityStore fallback chain handles defaults
    allow_public_api: transforms.fromString.boolean.nullish(), // No default — identityStore fallback chain handles defaults
    font_family: z.enum(fontOptions).default(FontFamily.SANS),
    corner_style: z.enum(cornerStyleOptions).default(CornerStyle.ROUNDED),
    locale: localeCodeSchema.default('en'),
    default_ttl: transforms.fromString.number.nullish(),
    passphrase_required: transforms.fromString.boolean.default(false),
    notify_enabled: transforms.fromString.boolean.default(false),
  })
  .partial(); // Makes all fields optional;

/** @deprecated Use brandSettingSchema instead */
export const brandSettingschema = brandSettingSchema;

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

export type BrandSettings = z.infer<typeof brandSettingSchema>;
export type ImageProps = z.infer<typeof imagePropsSchema>;

export {
  CornerStyle,
  cornerStyleDisplayMap,
  cornerStyleIconMap,
  cornerStyleOptions,
  fontDisplayMap,
  FontFamily,
  fontIconMap,
  fontOptions,
};
