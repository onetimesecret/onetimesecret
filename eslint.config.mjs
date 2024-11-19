import pluginVueI18n from '@intlify/eslint-plugin-vue-i18n';
import tseslint from '@typescript-eslint/eslint-plugin';
import parserTs from '@typescript-eslint/parser';
import pluginVue from 'eslint-plugin-vue';
import globals from 'globals';
import path from 'path';
import vueEslintParser from 'vue-eslint-parser';
import importPlugin from 'eslint-plugin-import';
import pluginTailwindCSS from 'eslint-plugin-tailwindcss';


export default [
  // Ignore everything except src directory and vite.config.ts
  {
    ignores: ['**/*', '!src/**', '!*.config.ts'],
  },
  {
    files: ['src/**/*.{js,mjs,cjs,ts,vue}', 'vite.config.ts'],
    languageOptions: {
      globals: {
        ...globals.browser,
        process: true,
      },
      parserOptions: {
        ecmaVersion: 'latest',
        sourceType: 'module',
        // Specify TypeScript parser for TypeScript files
        parser: ['.ts', '.tsx'].includes(path.extname(import.meta.url)) ? parserTs : undefined,
      },
    },
    plugins: {
      import: importPlugin,
    },
    rules: {
      'no-undef': 'error', // Warns on the use of undeclared variables,
      'import/order': [
        'error',
        {
          groups: [['builtin', 'external', 'internal']],
          pathGroups: [
            {
              pattern: '@/**',
              group: 'internal',
            },
          ],
          pathGroupsExcludedImportTypes: ['builtin'],
          'newlines-between': 'always',
          alphabetize: {
            order: 'asc',
            caseInsensitive: true,
          },
        },
      ],
    },
    settings: {
      'import/resolver': {
        typescript: {},
      },
    },
  },
  // Include recommended TypeScript rules directly
  {
    files: ['src/**/*.{ts,tsx}'],
    languageOptions: {
      parser: parserTs,
      parserOptions: {
        ecmaVersion: 'latest',
        sourceType: 'module',
      },
    },
    plugins: {
      '@typescript-eslint': tseslint,
    },
    rules: {
      ...tseslint.configs.recommended.rules,
      '@typescript-eslint/no-unused-vars': 'error', // Add the rule here
    },
  },
  ...pluginVue.configs['flat/strongly-recommended'],
  {
    files: ['src/**/*.vue'],
    languageOptions: {
      parser: vueEslintParser,
      parserOptions: {
        parser: parserTs,
        ecmaVersion: 'latest',
        sourceType: 'module',
      },
    },
    rules: {
      'vue/valid-template-root': 'error',
    },
    plugins: {
      'vue': pluginVue,
    },
  },
  // Override specific rules for certain Vue files
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
      'tailwindcss/classnames-order': 'warn',
      'tailwindcss/no-custom-classname': 'warn',
    },
  },
];
