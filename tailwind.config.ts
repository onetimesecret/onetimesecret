// ./tailwind.config.ts

import forms from '@tailwindcss/forms';
import typography from '@tailwindcss/typography';

/**
 * Tailwind CSS v4 Configuration
 *
 * Theme configuration has been migrated to CSS using @theme directive.
 * See src/assets/style.css for custom colors, fonts, and animations.
 */

export default {
  content: [
    './src/*.html',
    './src/**/*.{vue,js,ts,jsx,tsx,mjs}',
    './templates/web/**/*.html',
    './apps/web/auth/views/**/*.erb',  // Include auth service templates
  ],
  safelist: [
    // Dynamically generated classes that must not be purged
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
  plugins: [forms(), typography()],
};
