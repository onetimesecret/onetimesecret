// eslint.config.mjs
import globals from 'globals';
import pluginJs from '@eslint/js';
import tseslint from 'typescript-eslint';
import pluginVue from 'eslint-plugin-vue';
import pluginVueI18n from '@intlify/eslint-plugin-vue-i18n';
import pluginTailwindCSS from 'eslint-plugin-tailwindcss';


export default [
  // Ignore everything except src directory
  {
    ignores: ['**/**', '!src/**', '!vite.config.ts'],
  },
  {
    files: ['src/**/*.{js,mjs,cjs,ts,vue}', 'vite.config.ts'],
    languageOptions: {
      globals: globals.browser,
      parserOptions: {
        ecmaVersion: 'latest',
        sourceType: 'module',
      },
    },
    rules: {
      'no-undef': 'error', // Warns on the use of undeclared variables
    },
  },
  ...tseslint.configs.recommended,
  ...pluginVue.configs['flat/strongly-recommended'],
  {
    files: ['src/**/*.vue'],
    languageOptions: {
      parserOptions: {
        parser: tseslint.parser,
      },
    },
    rules: {
      'vue/valid-template-root': 'error',
    },
  },
  // Directly integrate what would have been an override
  {
    files: ['src/views/*.vue', 'src/layouts/*.vue'], // Target files in the views directory
    rules: {
      'vue/multi-word-component-names': 'off', // Turn off the rule
    },
  },
  // Add Vue I18n plugin configuration
  {
    files: ['src/**/*.{ts,vue}'],
    plugins: {
      '@intlify/vue-i18n': pluginVueI18n,
    },
    rules: {
      '@intlify/vue-i18n/no-deprecated-modulo-syntax': 'error',
    },
  },
  // Add Tailwind CSS plugin configuration
  ...pluginTailwindCSS.configs['flat/recommended'],
  {
    files: ['src/**/*.{ts,vue}'],
    plugins: {
      'tailwindcss': pluginTailwindCSS,
    },
    rules: {
      'tailwindcss/classnames-order': '',
      'tailwindcss/no-custom-classname': 'on',
    },
  },
];
