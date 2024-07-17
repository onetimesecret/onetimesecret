import defaultTheme from 'tailwindcss/defaultTheme';
import typography from '@tailwindcss/typography';

export default {
  darkMode: 'class',
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
    typography,
  ],
};
