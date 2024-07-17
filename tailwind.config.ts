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
