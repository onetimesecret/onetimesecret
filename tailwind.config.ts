import defaultTheme from 'tailwindcss/defaultTheme';
import typography from '@tailwindcss/typography';

/**
 * Tailwind CSS Configuration
 *
**/

export default {

  content: [
    /**
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
    "./src/demo.html",
    "./templates/web/**/*.html",
    "./src/**/*.{vue,js,ts,jsx,tsx}",
  ],

  darkMode: 'class',
  theme: {
    fontFamily: {
      serif: defaultTheme.fontFamily.serif,
      sans: defaultTheme.fontFamily.sans,
      /* In CSS: font-family: theme('fontFamily.brand'); */
      brand: ['Zilla Slab', ...defaultTheme.fontFamily.serif],
    },
    extend: {
      colors: {
        brand: {
          50: '#fcf8f2',
          100: '#fcf4e8',
          200: '#f7dec3',
          300: '#f0c39e',
          400: '#e68b5e',
          500: '#dc4a22',
          600: '#c43d1b',
          700: '#a32d12',
          800: '#85200c',
          900: '#631507',
          950: '#400b03'
        },
      },
    }
  },
  plugins: [
    typography,

    /* TODO: Check if we can use this in place of the fonts.css */
    //function({ addBase, theme }) {
    //  addBase({
    //    '@font-face': [
    //      {
    //        fontFamily: 'Zilla Slab',
    //        fontWeight: '400',
    //        fontStyle: 'normal',
    //        fontDisplay: 'swap',
    //        src: 'url("/fonts/ZillaSlab-Regular.woff2") format("woff2")',
    //      },
    //      {
    //        fontFamily: 'Zilla Slab',
    //        fontWeight: '700',
    //        fontStyle: 'normal',
    //        fontDisplay: 'swap',
    //        src: 'url("/fonts/ZillaSlab-Bold.woff2") format("woff2")',
    //      },
    //    ],
    //  })
    //},
  ],
};
