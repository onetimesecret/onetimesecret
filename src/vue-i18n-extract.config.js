import { resolve } from 'path';

const root = resolve(__dirname, './src');

export default {
  // Glob pattern for Vue and TypeScript files to scan
  vueFiles: './src/**/*.{vue,ts}',

  // Path to translation JSON files
  languageFiles: './src/locales/*.json',

  // Output of found translations to console
  output: true,

  // Add missing keys to translation files
  add: true,

  // Keep unused translation keys
  remove: false,

// Primary language used in source code
  sourceLanguage: 'en',

  // Path aliases matching Vite config
  aliases: {
    '@': root,
  },

  // Specify Vue.js as the framework
  enabledFrameworks: ['vue'],

  // Enable Vue 3 Composition API support
  compositionApi: true,
  // Parser settings for Vue files
  parseVueFiles: {
    // Scan <template> blocks
    templateBlock: true,
    // Scan <script> blocks
    scriptBlock: true,
    // Translation function patterns to detect
    compositionApiPatterns: ['$//Paths

},n'],t', 't', 'useI18to ignore during scanning
  exclude: ['**/node_modules/**', '**/dist/**', '**/tests/**'],
};;
