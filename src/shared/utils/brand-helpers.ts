// src/shared/utils/brand-helpers.ts
//
// UI helpers for brand settings - CSS classes, display names, and icons.
// These are presentation-layer utilities that map brand setting values
// to their visual representations.

import {
  borderRadiusPresets,
  cornerStyleValues,
  fontFamilyValues,
  isValidBorderRadius,
  type BorderRadiusPreset,
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
  SYSTEM: 'system',
  SLAB: 'slab',
  ROUNDED: 'rounded',
  HUMANIST: 'humanist',
  GEOMETRIC: 'geometric',
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
 * Maps font family values to Tailwind CSS font-family utility classes.
 *
 * The original sans/serif/mono trio reuses Tailwind's built-in families. The
 * expanded values map to `font-brand-*` utilities backed by `--font-brand-*`
 * theme tokens defined in `src/assets/style.css` (@theme static), so the
 * scanner always sees a static class and the utility resolves at runtime.
 */
export const fontFamilyClasses: Record<FontFamily, string> = {
  sans: 'font-sans',
  serif: 'font-serif',
  mono: 'font-mono',
  system: 'font-brand-system',
  slab: 'font-brand-slab',
  rounded: 'font-brand-rounded',
  humanist: 'font-brand-humanist',
  geometric: 'font-brand-geometric',
};

/**
 * CSS `font-family` stacks for each curated font.
 *
 * These back the `font-brand-*` utilities via the matching `--font-brand-*`
 * tokens declared in `@theme static` (style.css) — the font pipeline is
 * class-based (fontFamilyClasses), NOT runtime CSS-variable injection like the
 * colors. This map is the single source these stacks are authored from; the
 * style.css tokens must mirror it. Kept in lockstep with the Ruby allowlist
 * (BrandSettingsConstants::FONTS).
 */
export const fontFamilyStacks: Record<FontFamily, string> = {
  sans: 'ui-sans-serif, system-ui, -apple-system, "Segoe UI", Roboto, Helvetica, Arial, sans-serif',
  serif: 'ui-serif, Georgia, Cambria, "Times New Roman", Times, serif',
  mono: 'ui-monospace, "SF Mono", SFMono-Regular, Menlo, Consolas, "Liberation Mono", monospace',
  system: 'system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif',
  slab: '"Zilla Slab", ui-serif, Georgia, Cambria, "Times New Roman", Times, serif',
  rounded: 'ui-rounded, "SF Pro Rounded", "Hiragino Maru Gothic ProN", "Nunito", system-ui, sans-serif',
  humanist: '"Segoe UI", "Helvetica Neue", "Optima", Candara, Calibri, system-ui, sans-serif',
  geometric: '"Avenir Next", Avenir, "Century Gothic", "Futura", system-ui, sans-serif',
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
// Border radius (expanded, #3646)
// ─────────────────────────────────────────────────────────────────────────────

/** Named border-radius presets mapped to CSS length values (rem/px). */
export const borderRadiusPresetCss: Record<BorderRadiusPreset, string> = {
  none: '0px',
  sm: '0.25rem',
  md: '0.5rem',
  lg: '0.75rem',
  xl: '1rem',
  full: '9999px',
};

/** Array of named border-radius presets for form options. */
export const borderRadiusOptions = [...borderRadiusPresets];

/** Human-readable display names for border-radius presets. */
export const borderRadiusDisplayMap: Record<BorderRadiusPreset, string> = {
  none: 'Square',
  sm: 'Slightly Rounded',
  md: 'Rounded',
  lg: 'Very Rounded',
  xl: 'Extra Rounded',
  full: 'Pill',
};

/**
 * Icon class names for border-radius presets. Reuses the tabler corner icons
 * (square → rounded → pill) so the corner control shows a meaningful glyph per
 * step — without an icon-map an icon-only control renders a generic question
 * mark.
 */
export const borderRadiusIconMap: Record<BorderRadiusPreset, string> = {
  none: 'tabler-border-corner-square',
  sm: 'tabler-border-corner-rounded',
  md: 'tabler-border-corner-rounded',
  lg: 'tabler-border-corner-rounded',
  xl: 'tabler-border-corner-pill',
  full: 'tabler-border-corner-pill',
};

/**
 * Resolves a `border_radius` value (preset keyword or px number/string) to a
 * CSS length for the `--radius-brand` variable. Returns null for unset or
 * invalid input so callers can fall back to the compiled `@theme` default.
 *
 * Mirrors the Ruby `BrandSettings.valid_border_radius?` acceptance rules.
 */
export function borderRadiusToCss(
  value: string | number | null | undefined
): string | null {
  if (value == null || value === '') return null;
  if (!isValidBorderRadius(value)) return null;

  const str = String(value).trim().toLowerCase();
  if (str in borderRadiusPresetCss) {
    return borderRadiusPresetCss[str as BorderRadiusPreset];
  }
  // Numeric px value.
  return `${Number(str)}px`;
}

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
  system: 'System UI',
  slab: 'Slab Serif',
  rounded: 'Rounded',
  humanist: 'Humanist',
  geometric: 'Geometric',
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
  system: 'ph-desktop-bold',
  slab: 'ph-text-b-bold',
  rounded: 'ph-circle-bold',
  humanist: 'ph-text-aa',
  geometric: 'ph-triangle-bold',
};

/**
 * Icon class names for corner style options.
 */
export const cornerStyleIconMap: Record<CornerStyle, string> = {
  rounded: 'tabler-border-corner-rounded',
  pill: 'tabler-border-corner-pill',
  square: 'tabler-border-corner-square',
};
