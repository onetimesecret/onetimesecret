import defaultTheme from 'tailwindcss/defaultTheme';
import typography from '@tailwindcss/typography';

export default {
  darkMode: 'class',
  content: [
    "./src/index.html",
    "./src/**/*.{vue,js,ts,jsx,tsx}",
  ],
  theme: {
    fontFamily: {
      serif: ['ui-serif', 'Georgia', 'Cambria', 'Times New Roman', 'Times', 'serif'],
      sans: ['ui-sans-serif', 'system-ui', '-apple-system', 'BlinkMacSystemFont', '"Segoe UI"', 'Roboto', '"Helvetica Neue"', 'Arial', '"Noto Sans"', 'sans-serif'],
      /* In CSS: font-family: theme('fontFamily.brand'); */
      brand: ['Zilla Slab', ...defaultTheme.fontFamily.serif],
    },
    extend: {

      colors: {
        brand: {
          50: '#f0f9ff',
          100: '#e0f2fe',
          200: '#bae6fd',
          300: '#7dd3fc',
          400: '#38bdf8', // TODO: replace with actual
          500: '#0ea5e9',
          600: '#0284c7',
          700: '#0369a1',
          800: '#075985',
          900: '#0c4a6e',
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
