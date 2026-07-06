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
 * CSS `font-family` stacks for each curated font. Injected at runtime as the
 * `--font-brand-body` / `--font-brand-heading` variables by useBrandTheme, and
 * mirrored as `--font-brand-*` theme defaults in style.css. Kept in lockstep
 * with the Ruby allowlist (BrandSettingsConstants::FONTS).
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
 * (square → rounded → pill) so the CycleButton shows a meaningful glyph per
 * step — without an icon-map the control renders a generic question mark, since
 * CycleButton's only visible content is the icon.
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

// ─────────────────────────────────────────────────────────────────────────────
// Theme presets (#3646)
// ─────────────────────────────────────────────────────────────────────────────

/**
 * A curated combination of brand tokens — the zero-effort path for customers
 * who don't want to hand-pick each value. Applying a preset is a shallow merge
 * of these fields onto the current BrandSettings.
 *
 * Only the cosmetic token subset is included; identity fields (logo, name,
 * instructions) are never touched by a preset. All colors clear WCAG AA (3:1
 * vs white for accent colors, 4.5:1 for text-on-background).
 */
export interface BrandPreset {
  /** Stable id used as a v-for key and selection marker. */
  id: string;
  /** Human-readable name shown in the picker. */
  name: string;
  /** Token values applied on selection. */
  tokens: {
    primary_color: string;
    secondary_color: string;
    background_color: string;
    text_color: string;
    font_family: FontFamily;
    heading_font: FontFamily;
    border_radius: BorderRadiusPreset;
    button_text_light: boolean;
  };
}

/**
 * Designed token combinations offered as one-click starting points. Kept small
 * and opinionated; each pairs an accent + complement, a surface/ink pair, a
 * font pairing, and a corner rounding. Contrast-checked against WCAG AA.
 */
export const brandPresets: readonly BrandPreset[] = [
  {
    id: 'midnight',
    name: 'Midnight',
    tokens: {
      primary_color: '#4F46E5',
      secondary_color: '#0EA5E9',
      background_color: '#0F172A',
      text_color: '#E2E8F0',
      font_family: 'sans',
      heading_font: 'geometric',
      border_radius: 'md',
      button_text_light: true,
    },
  },
  {
    id: 'forest',
    name: 'Forest',
    tokens: {
      primary_color: '#047857',
      secondary_color: '#65A30D',
      background_color: '#F7FBF9',
      text_color: '#14261E',
      font_family: 'humanist',
      heading_font: 'slab',
      border_radius: 'lg',
      button_text_light: true,
    },
  },
  {
    id: 'sunset',
    name: 'Sunset',
    tokens: {
      primary_color: '#DB2777',
      secondary_color: '#F97316',
      background_color: '#FFF7F9',
      text_color: '#2B1220',
      font_family: 'rounded',
      heading_font: 'rounded',
      border_radius: 'xl',
      button_text_light: true,
    },
  },
  {
    id: 'slate',
    name: 'Slate',
    tokens: {
      primary_color: '#334155',
      secondary_color: '#0891B2',
      background_color: '#FFFFFF',
      text_color: '#1E293B',
      font_family: 'system',
      heading_font: 'system',
      border_radius: 'sm',
      button_text_light: true,
    },
  },
  {
    id: 'royal',
    name: 'Royal',
    tokens: {
      primary_color: '#6D28D9',
      secondary_color: '#DB2777',
      background_color: '#FBF9FF',
      text_color: '#241633',
      font_family: 'serif',
      heading_font: 'slab',
      border_radius: 'md',
      button_text_light: true,
    },
  },
  {
    id: 'terminal',
    name: 'Terminal',
    tokens: {
      primary_color: '#15803D',
      secondary_color: '#4ADE80',
      background_color: '#0B0F0C',
      text_color: '#D1FAE5',
      font_family: 'mono',
      heading_font: 'mono',
      border_radius: 'none',
      button_text_light: true,
    },
  },
  {
    id: 'coral',
    name: 'Coral',
    tokens: {
      primary_color: '#E11D48',
      secondary_color: '#F59E0B',
      background_color: '#FFFBF7',
      text_color: '#2A1512',
      font_family: 'sans',
      heading_font: 'humanist',
      border_radius: 'lg',
      button_text_light: true,
    },
  },
  {
    id: 'ocean',
    name: 'Ocean',
    tokens: {
      primary_color: '#0369A1',
      secondary_color: '#0D9488',
      background_color: '#F5FBFF',
      text_color: '#0C2231',
      font_family: 'geometric',
      heading_font: 'geometric',
      border_radius: 'md',
      button_text_light: true,
    },
  },
  // Accessibility presets: maximum-contrast light/dark pairs modeled on the
  // OS-level "High Contrast" themes (WCAG AAA — text-on-bg is 21:1). System
  // font for legibility, minimal rounding, no decorative tints.
  {
    id: 'high-contrast',
    name: 'High Contrast',
    tokens: {
      primary_color: '#000000',
      secondary_color: '#1D4ED8',
      background_color: '#FFFFFF',
      text_color: '#000000',
      font_family: 'system',
      heading_font: 'system',
      border_radius: 'sm',
      button_text_light: true,
    },
  },
  {
    id: 'high-contrast-dark',
    name: 'High Contrast Dark',
    tokens: {
      // Primary is still validated against white (3:1), so a mid-dark blue
      // rather than pure white — it reads as a button on the black surface too.
      primary_color: '#2563EB',
      secondary_color: '#FDE047',
      background_color: '#000000',
      text_color: '#FFFFFF',
      font_family: 'system',
      heading_font: 'system',
      border_radius: 'sm',
      button_text_light: true,
    },
  },
] as const;
