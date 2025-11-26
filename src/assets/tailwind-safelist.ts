// src/assets/tailwind-safelist.ts

/**
 * Tailwind v4 Safelist Workaround
 *
 * Tailwind v4 removed the safelist option. To ensure dynamically generated
 * classes (like those in SplitButton) are included in the build, we explicitly
 * reference them here so Tailwind's scanner can detect them.
 *
 * This file is included in tailwind.config.ts content configuration.
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
] as const;

/**
 * Usage example for reference:
 *
 * const className = `rounded-l-lg rounded-r-lg`; // ✅ Tailwind detects this
 * const className = `rounded-${dir}-lg`;        // ❌ Tailwind CANNOT detect this
 *
 * SplitButton uses the second pattern, hence this safelist file.
 */
