
import pluginVueI18n from '@intlify/eslint-plugin-vue-i18n';
import tseslint from '@typescript-eslint/eslint-plugin';
import parserTs from '@typescript-eslint/parser';
import pluginVue from 'eslint-plugin-vue';
import globals from 'globals';
import path from 'path';
import vueEslintParser from 'vue-eslint-parser';
import * as importPlugin from 'eslint-plugin-import';
import pluginTailwindCSS from 'eslint-plugin-tailwindcss';

export default [

  /**
   * Base Ignore Patterns
   * Excludes all files except source and config files
   */
  {
    ignores: ['**/*', '!src/**', '!*.config.ts'],
  },

  /**
   * Global Project Configuration
   * Applies to all JavaScript, TypeScript and Vue files
   * Handles basic ES features and import ordering
   */
  {
    files: ['src/**/*.{js,mjs,cjs,ts,vue}', 'vite.config.ts'],
    languageOptions: {
      globals: {
        ...globals.browser,
        process: true, // Allow process global for environment variables
      },
      parserOptions: {
        ecmaVersion: 'latest',
        sourceType: 'module',
        parser: ['.ts', '.tsx'].includes(path.extname(import.meta.url)) ? parserTs : undefined,
      },
    },
    plugins: {
      import: importPlugin,
      vue: pluginVue, // Make sure this is included
    },
    rules: {
      'no-undef': 'error', // Prevent usage of undeclared variables
      // Enforce consistent import ordering
      'import/order': [
        'error',
        {
          groups: [['builtin', 'external', 'internal']], // Group imports by type
          pathGroups: [{ pattern: '@/**', group: 'internal' }], // Treat @ imports as internal
          pathGroupsExcludedImportTypes: ['builtin'],
          'newlines-between': 'always', // Require line breaks between import groups
          alphabetize: { order: 'asc', caseInsensitive: true }, // Sort imports alphabetically
        },
      ],
      // Omit file extensions for JS/TS/Vue imports, ignore node_modules
      'import/extensions': [
        'error',
        'ignorePackages',
        {
          'js': 'never',
          'jsx': 'never',
          'ts': 'never',
          'tsx': 'never',
          'vue': 'never'
        }
      ],      // Add this rule configuration
      'vue/component-tags-order': ['error', {
        order: ['script', 'template', 'style']
      }]
    },
    settings: {
      'import/resolver': { typescript: {} }, // Enable TypeScript import resolution
    },
  },

  /**
   * TypeScript Specific Rules
   * Applies to .ts and .vue files
   * Configures TypeScript, i18n, and Tailwind linting
   */
  {
    files: ['src/**/*.{ts,vue}'],
    languageOptions: {
      parser: parserTs,
      parserOptions: {
        ecmaVersion: 'latest',
        sourceType: 'module',
        project: './tsconfig.json', // Link to TypeScript configuration
        extraFileExtensions: ['.vue'], // Add this line
      },
    },
    plugins: {
      '@typescript-eslint': tseslint,
      '@intlify/vue-i18n': pluginVueI18n,
      'tailwindcss': pluginTailwindCSS,
    },
    rules: {
      ...tseslint.configs.recommended.rules,
      '@typescript-eslint/no-unused-vars': 'error', // Prevent unused variables
      '@typescript-eslint/no-unused-expressions': ['error', {
        allowShortCircuit: true, // Allow logical short-circuit evaluations
        allowTernary: true, // Allow ternary expressions
      }],
      '@intlify/vue-i18n/no-deprecated-modulo-syntax': 'error', // Enforce modern i18n syntax
      'tailwindcss/classnames-order': 'warn', // Maintain consistent class ordering
      'tailwindcss/no-custom-classname': 'warn', // Flag undefined Tailwind classes
      'max-len': ['warn', {
        code: 100,
        // Apply max-len only to lines containing class="
        // This requires a custom pattern that matches lines with class="
        // and enforces the length, while ignoring others.
        // ESLint doesn't support "only" patterns directly,
        // so we use a combination of rules or a custom plugin.
        // As a workaround, you can use a regex to enforce max-len on matching lines.
        // However, this isn't natively supported by ESLint's max-len rule.
        // Consider using a custom rule or plugin for this functionality.
        ignorePattern: '^((?!class=").)*$',
        ignoreUrls: true,
      }],
    },
  },

  // Include Vue.js recommended configuration directly
  ...pluginVue.configs['flat/strongly-recommended'],

  /**
   * Vue Template Rules
   * Specific rules for Vue single-file components
   */
  {
    files: ['src/**/*.vue'],
    languageOptions: {
      parser: vueEslintParser,
      parserOptions: {
        parser: parserTs,
        project: './tsconfig.json',
        extraFileExtensions: ['.vue'],
        ecmaVersion: 'latest',
        sourceType: 'module',
      },
    },
    plugins: {
      vue: pluginVue,
    },
    rules: {
      // Prefer camelCase over kebab-case
      // https://eslint.vuejs.org/rules/attribute-hyphenation.html
      "vue/attribute-hyphenation": ["warn", "always", {
        "ignore": [],
      }],

      // Ensure valid template root
      'vue/valid-template-root': 'error',
      // Configure self-closing tag behavior
      'vue/html-self-closing': ['error', {
        'html': {
          'void': 'always',
          'normal': 'never',
          'component': 'always'
        },
        'svg': 'always',
        'math': 'always'
      }],
      // Avoid attribute clutter
      "vue/max-attributes-per-line": ["error", {
        "singleline": 2,
        "multiline": 1
      }],
      // Enforce consistent line breaks in template elements
      "vue/html-closing-bracket-newline": [
        "error",
        {
          "singleline": "never",
          "multiline": "never",
          "selfClosingTag": {
            "singleline": "never",
            "multiline": "always"
          }
        }
      ],
    },
  },

  /**
   * Page and Layout Components Exception
   * Relaxes naming convention for top-level components
   */
  {
    files: ['src/views/*.vue', 'src/layouts/*.vue'],
    rules: {
      'vue/multi-word-component-names': 'off', // Allow single-word names for pages/layouts
    },
  },

  // Include Tailwind recommended configuration
  ...pluginTailwindCSS.configs['flat/recommended'],

  // Use this prettier plugin for eslint, which disables conflicting rules.
  // This plugin is a workaround for ESLint and Prettier conflicts. Simply,
  // uncomment the next line to enable it (don't forget to import it at the
  //  top): `import eslintConfigPrettier from 'eslint-config-prettier';
  // eslintConfigPrettier,
];
