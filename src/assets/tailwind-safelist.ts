// src/assets/tailwind-safelist.ts

/**
 * Tailwind v4 Safelist Workaround
 *
 * Tailwind v4 removed the safelist option. To ensure dynamically generated
 * classes (like those in SplitButton) are included in the build, we explicitly
 * reference them here so Tailwind's scanner can detect them.
 *
 * This file is scanned via the @source globs in src/assets/style.css.
 */

// SplitButton corner classes - dynamically generated via string concatenation
// in processCornerClass() method, so Tailwind can't detect them automatically
export const SPLIT_BUTTON_CORNERS = [
  'rounded-l-sm', 'rounded-r-sm',
  'rounded-l-md', 'rounded-r-md',
  'rounded-l-lg', 'rounded-r-lg',
  'rounded-l-xl', 'rounded-r-xl',
  'rounded-l-2xl', 'rounded-r-2xl',
  'rounded-l-3xl', 'rounded-r-3xl',
  'rounded-l-full', 'rounded-r-full',
  // Brand radius token (#3646): cornerClass resolves to `rounded-brand` when a
  // domain sets border_radius, so processCornerClass() emits `rounded-l/r-brand`.
  // Without these the pill/brand radius silently drops on the split CTA button.
  'rounded-l-brand', 'rounded-r-brand',
] as const;

/**
 * Usage example for reference:
 *
 * const className = `rounded-l-lg rounded-r-lg`; // ✅ Tailwind detects this
 * const className = `rounded-${dir}-lg`;        // ❌ Tailwind CANNOT detect this
 *
 * SplitButton uses the second pattern, hence this safelist file.
 */

/**
 * Expanded brand token utilities (#3646).
 *
 * These resolve to runtime-injected CSS variables (`--color-brand2-*`,
 * `--color-brandbg`, `--color-brandtext`, `--radius-brand`) and the curated
 * `--font-brand-*` families. They're referenced statically in migrated
 * components and in brand-helpers.ts maps, but are listed here so the build
 * always emits them even when a consumer builds the class name dynamically.
 */
export const BRAND_TOKEN_UTILITIES = [
  // Secondary color scale
  'bg-brand2-50', 'bg-brand2-100', 'bg-brand2-500', 'bg-brand2-600', 'bg-brand2-700',
  'text-brand2-500', 'text-brand2-600', 'text-brand2-700',
  'border-brand2-500', 'ring-brand2-500',
  // Surface / ink single tokens
  'bg-brandbg', 'text-brandbg', 'border-brandbg',
  'bg-brandtext', 'text-brandtext', 'border-brandtext',
  // Brand radius
  'rounded-brand',
  // Curated font families
  'font-brand-system', 'font-brand-slab', 'font-brand-rounded',
  'font-brand-humanist', 'font-brand-geometric',
] as const;
