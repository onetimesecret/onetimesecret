// ./tailwind.config.ts
// Tailwind CSS v4 Configuration

import forms from '@tailwindcss/forms';
import typography from '@tailwindcss/typography';

/**
 * Tailwind CSS v4 Configuration
 *
 * In Tailwind v4, most theme configuration has been moved to CSS using the @theme directive.
 * See src/assets/style.css for:
 * - Custom colors (brand, branddim, brandcomp, brandcompdim)
 * - Custom animations (spin-slow, kitt-rider, gradient-x)
 * - Font families (brand font using Zilla Slab)
 * - @font-face definitions
 * - Custom keyframes
 *
 * This config file now primarily handles:
 * - Content paths (where to scan for class names)
 * - Safelist (classes to always include)
 * - Plugins
 *
 * Migration notes:
 * - darkMode: 'class' is no longer needed in v4 (use dark: variant prefix)
 * - Theme customization now uses CSS custom properties in @theme directive
 * - Custom plugins using addBase are replaced with @layer base in CSS
 **/

export default {
  content: [
    /**
     * Content paths - tells Tailwind CSS where to look for class names
     * to generate styles.
     *
     * Scans these files for Tailwind class names:
     * - HTML files in src/ and templates/web/
     * - Vue, JS, TS, JSX, TSX, MJS files in src/
     */
    './src/*.html',
    './src/**/*.{vue,js,ts,jsx,tsx,mjs}',
    './templates/web/**/*.html',
  ],

  /**
   * Safelist - classes to always include in the final CSS
   * These rounded utilities are dynamically used in the application
   */
  safelist: [
    'rounded-l-sm',
    'rounded-r-sm',
    'rounded-l-md',
    'rounded-r-md',
    'rounded-l-lg',
    'rounded-r-lg',
    'rounded-l-xl',
    'rounded-r-xl',
    'rounded-l-2xl',
    'rounded-r-2xl',
    'rounded-l-3xl',
    'rounded-r-3xl',
    'rounded-l-full',
    'rounded-r-full',
  ],

  /**
   * Plugins
   * Official Tailwind plugins for forms and typography
   */
  plugins: [forms(), typography()],
};
