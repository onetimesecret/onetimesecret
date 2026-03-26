// src/shared/utils/brand-helpers.ts
//
// UI helpers for brand settings - CSS classes, display names, and icons.
// These are presentation-layer utilities that map brand setting values
// to their visual representations.

import {
  cornerStyleValues,
  fontFamilyValues,
} from '@/schemas/contracts';

// ─────────────────────────────────────────────────────────────────────────────
// Type definitions (derived from contract values)
// ─────────────────────────────────────────────────────────────────────────────

/** Font family type - union of valid values. */
export type FontFamily = (typeof fontFamilyValues)[number];

/** Corner style type - union of valid values. */
export type CornerStyle = (typeof cornerStyleValues)[number];

// ─────────────────────────────────────────────────────────────────────────────
// Enum-like objects for convenience
// ─────────────────────────────────────────────────────────────────────────────

/**
 * FontFamily enum-like object for runtime value access.
 *
 * @example
 * ```typescript
 * const defaultFont = FontFamily.SANS; // 'sans'
 * ```
 */
export const FontFamily = {
  SANS: 'sans',
  SERIF: 'serif',
  MONO: 'mono',
} as const satisfies Record<string, FontFamily>;

/**
 * CornerStyle enum-like object for runtime value access.
 *
 * @example
 * ```typescript
 * const defaultCorner = CornerStyle.ROUNDED; // 'rounded'
 * ```
 */
export const CornerStyle = {
  ROUNDED: 'rounded',
  PILL: 'pill',
  SQUARE: 'square',
} as const satisfies Record<string, CornerStyle>;

// ─────────────────────────────────────────────────────────────────────────────
// Options arrays (for form selects, etc.)
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Array of valid font family values for form options.
 */
export const fontOptions = [...fontFamilyValues];

/**
 * Array of valid corner style values for form options.
 */
export const cornerStyleOptions = [...cornerStyleValues];

// ─────────────────────────────────────────────────────────────────────────────
// CSS class mappings
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Maps font family values to Tailwind CSS font classes.
 */
export const fontFamilyClasses: Record<FontFamily, string> = {
  sans: 'font-sans',
  serif: 'font-serif',
  mono: 'font-mono',
};

/**
 * Maps corner style values to Tailwind CSS border-radius classes.
 */
export const cornerStyleClasses: Record<CornerStyle, string> = {
  rounded: 'rounded-md',
  pill: 'rounded-xl',
  square: 'rounded-none',
};

// ─────────────────────────────────────────────────────────────────────────────
// Display name mappings
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Human-readable display names for font families.
 */
export const fontDisplayMap: Record<FontFamily, string> = {
  sans: 'Sans Serif',
  serif: 'Serif',
  mono: 'Monospace',
};

/**
 * Human-readable display names for corner styles.
 */
export const cornerStyleDisplayMap: Record<CornerStyle, string> = {
  rounded: 'Rounded',
  pill: 'Pill Shape',
  square: 'Square',
};

// ─────────────────────────────────────────────────────────────────────────────
// Icon mappings
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Icon class names for font family options.
 */
export const fontIconMap: Record<FontFamily, string> = {
  sans: 'ph-text-aa-bold',
  serif: 'ph-text-t-bold',
  mono: 'ph-code',
};

/**
 * Icon class names for corner style options.
 */
export const cornerStyleIconMap: Record<CornerStyle, string> = {
  rounded: 'tabler-border-corner-rounded',
  pill: 'tabler-border-corner-pill',
  square: 'tabler-border-corner-square',
};
