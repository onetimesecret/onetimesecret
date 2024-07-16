const defaultTheme = require('tailwindcss/defaultTheme')

export default {
  content: [
    "./src/index.html",
    "./src/**/*.{vue,js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {
      fontFamily: {
        sans: ['Zilla Slab', ...defaultTheme.fontFamily.serif],
      }
    }
  },
  plugins: [
    require('@tailwindcss/typography'),
  ],
};
