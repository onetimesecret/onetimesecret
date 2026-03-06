// ./tailwind.config.ts

import forms from '@tailwindcss/forms';
import typography from '@tailwindcss/typography';
import defaultTheme from 'tailwindcss/defaultTheme';

/**
 * Tailwind CSS Configuration
 *
 * npx prettier path/2/ComponentFile.vue --write --log-level debug
 * <!-- prettier-ignore-attribute class -->
 *
 **/

export default {
  content: [
    /**
     * `content` (Array): tells Tailwind CSS where to look for class
     * names to generate styles.
     *
     * - The `content` array specifies the paths to the files Tailwind
     *   should scan for class names.
     * - "./src/demo.html": Tailwind will scan this specific HTML file
     *   for class names.
     * - `"./src/*.{vue,js,ts,jsx,tsx}"`: Tailwind will also scan all
     *   files in the `src` directory (and subdirectories) with the
     *   extensions vue, js, ts, jsx, and tsx.
     *
     * Why does this matter?
     * - Tailwind generates CSS for the class names it finds in these
     *   files. If a file is listed, Tailwind looks inside it for class
     *   names to style.
     * - If "demo.html" exists, Tailwind includes styles for classes
     *   found in it. If it doesn't, those styles won't be generated.
     * - This setup helps keep the final CSS file size small because
     *   Tailwind only generates styles for class names it actually
     *   finds in these files.
     *
     * ELI10:
     * Imagine you're drawing pictures but only want to use colors you
     * see in your coloring books (files). You tell Tailwind (your color
     * finder) to look in specific books ("demo.html" and others in
     * `src`). Tailwind then makes sure you have just the right colors
     * (styles) for the pictures you're actually going to color (class
     * names in those files).
     *
     * ELIDELANO:
     * Make sure that demo.html is included in the content array so that
     * Tailwind CSS can generate styles for the classes found in it. And
     * make sure that it is up to date with header.html and footer.html.
     * Without demo.html, there was no <body> tag in the Vue app, and the
     * styles for the body tag were not generated. This causes the app to
     * display darkmode styles in bits and pieces rather than the whole
     * page for example. OR alternatively, include the rack app template
     * files in the content array as well.
     *
     */
    './src/*.html',
    './src/**/*.{vue,js,ts,jsx,tsx,mjs}',
    './templates/web/**/*.html',
    './apps/web/auth/views/**/*.erb',  // Include auth service templates
    './src/assets/tailwind-safelist.ts',  // v4 safelist workaround for dynamic classes
  ],
  // Note: Tailwind v4 removed the safelist option. Dynamic classes must be
  // explicitly present in source files for the scanner to detect them.
  // See: src/assets/tailwind-safelist.ts
  darkMode: 'class',
  theme: {
    fontFamily: {
      serif: defaultTheme.fontFamily.serif,
      sans: defaultTheme.fontFamily.sans,
      /* In CSS: font-family: theme('fontFamily.brand'); */
      brand: ['Zilla Slab', ...defaultTheme.fontFamily.serif],
      mono: defaultTheme.fontFamily.mono,
    },
    extend: {
      // Brand colors defined in src/assets/style.css @theme block
      // (canonical source in Tailwind v4, overridable at runtime)
      // Custom animations in style.css @theme and @keyframes
      // Background sizes in style.css @theme
    },
  },
  plugins: [
    forms(),
    typography(),
    // Font-face definitions moved to src/assets/style.css @layer base (Tailwind v4)
  ],
};
