/**
 * ESLint Flat Config
 *
 * IMPORTANT: Beware of conditional ts parser assignment based on the extension of this file.
 *
 * Problem Pattern:
 * - Using `path.extname(import.meta.url)` to conditionally set parser
 * - Works correctly when config file is .ts
 * - BREAKS when config file is changed to .mjs
 *
 * Why It Breaks:
 * - `path.extname(import.meta.url)` returns the extension of the current config file
 * - For .mjs files, this returns '.mjs', which doesn't match ['.ts', '.tsx']
 * - Result: Parser is set to `undefined`
 *
 * Solution Patterns:
 * 1. Direct Parser Assignment (Recommended):
 *    parser: parserTs  // Always use TypeScript parser
 *
 * 2. Explicit Type Checking:
 *    parser: fileExtension === '.ts' ? parserTs : someOtherParser
 *
 * 3. Add .mjs to Extension Array:
 *    parser: ['.ts', '.tsx', '.mjs'].includes(fileExtension) ? parserTs : undefined
 *
 * 4. Rename eslint.config.mjs to eslint.config.ts:
 *    - Use TypeScript-specific import syntax
 *    - Adjust module resolution if needed
 *    - Ensure TypeScript compiler and ESLint configs handle ES modules
 *
 * REQUIRED VS CODE SETTINGS:
 * Add to either .vscode/settings.json (project) or User Settings (global):
 * {
 *   "eslint.useFlatConfig": true,
 *   "eslint.validate": [
 *     "javascript",
 *     "javascriptreact",
 *     "typescript",
 *     "typescriptreact",
 *     "vue"
 *   ]
 * }
 *
 * Add to .vscode/settings.json (project-specific):
 * {
 *   "eslint.options": {
 *     "overrideConfigFile": "eslint.config.ts"
 *   }
 * }
 */

import pluginVueI18n from '@intlify/eslint-plugin-vue-i18n';
import tseslint from '@typescript-eslint/eslint-plugin';
import parserTs from '@typescript-eslint/parser';
import * as importPlugin from 'eslint-plugin-import';
import pluginTailwindCSS from 'eslint-plugin-tailwindcss';
import pluginVue from 'eslint-plugin-vue';
import globals from 'globals';
import path from 'path';
import vueEslintParser from 'vue-eslint-parser';

export default [
  /**
   * Base Ignore Patterns
   * Excludes all files except source and config files
   */
  {
    ignores: ['**/*', '!src/**', '!tests/**', '!*.config.ts', '!*.config.*js'],
  },

  /**
   * Global Project Configuration
   * Applies to all JavaScript, TypeScript and Vue files
   * Handles basic ES features and import ordering
   */
  {
    files: [
      'src/**/*.{js,mjs,cjs,ts,vue}',
      //'tests/**/*.{js,mjs,cjs,ts,vue}',
      'vite.config.ts',
      'eslint.config.ts',
    ],
    languageOptions: {
      globals: {
        ...globals.browser,
        process: true, // Allow process global for environment variables
      },
      parser: ['.ts', '.tsx'].includes(path.extname(import.meta.url)) ? parserTs : undefined,
      parserOptions: {
        ecmaVersion: 'latest',
        sourceType: 'module',
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
        'warn',
        {
          groups: [['builtin', 'external', 'internal']], // Group imports by type
          pathGroups: [{ pattern: '@/**', group: 'internal' }], // Treat @ imports as internal
          pathGroupsExcludedImportTypes: ['builtin'],
          'newlines-between': 'always', // Require line breaks between import groups
          alphabetize: { order: 'asc', caseInsensitive: true }, // Sort imports alphabetically
        },
      ],
      // Omit file extensions for TS/Vue imports, ignore node_modules
      'import/extensions': [
        'error',
        'ignorePackages',
        {
          ts: 'never',
          vue: 'always',
        },
      ], // Add this rule configuration
      'vue/component-tags-order': [
        'error',
        {
          order: ['script', 'template', 'style'],
        },
      ],
    },
    settings: {
      // Enable TypeScript import resolution
      'import/resolver': {
        typescript: {
          alwaysTryTypes: true,
          project: './tsconfig.json',
        },
        node: {
          extensions: ['.ts', '.vue'],
        },
      },
    },
  },
  /**
   * Typescript Rules
   * Applies to .ts et al. files
   * Configures TypeScript, i18n
   */
  {
    files: ['src/**/*.{ts,d.ts}'],
    languageOptions: {
      parserOptions: {
        parser: parserTs,
        ecmaVersion: 'latest',
        sourceType: 'module',
        project: './tsconfig.json', // Link to TypeScript configuration
        extraFileExtensions: ['.vue'], // Add this line
      },
    },
    plugins: {
      '@typescript-eslint': tseslint,
      '@intlify/vue-i18n': pluginVueI18n,
    },
    rules: {
      // ...tseslint.configs.recommended.rules,
      '@typescript-eslint/no-unused-vars': 'error', // Prevent unused variables

      // Note: you must disable the base rule as it can report incorrect errors
      'no-unused-expressions': 'off',
      '@typescript-eslint/no-unused-expressions': [
        'error',
        {
          allowShortCircuit: true,
          allowTernary: true,
          allowTaggedTemplates: true,
        },
      ],

      // Only warn explicit any in declaration files
      '@typescript-eslint/no-explicit-any': 'warn',

      '@intlify/vue-i18n/no-deprecated-modulo-syntax': 'error', // Enforce modern i18n syntax
      // https://github.com/francoismassart/eslint-plugin-tailwindcss/tree/master/docs/rules

      // Code Structure & Complexity
      'max-depth': ['error', 3], // Limit nesting depth (if/while/for/etc) to 3 levels. Deep nesting is a strong indicator
      // that code should be refactored using early returns, guard clauses, or helper functions.
      // Example - Instead of:
      //   if (a) { if (b) { if (c) { ... } } }
      // Use:
      //   if (!a || !b || !c) return;
      //   // happy path code here

      'max-nested-callbacks': ['error', 3], // Stricter than test files (4) because nested callbacks in production code almost always
      // indicate a need for async/await, Promises, or function extraction.
      // Example - Instead of:
      //   getData(id, (err, data) => { processData(data, (err, result) => { ... }) })
      // Use:
      //   const data = await getData(id);
      //   const result = await processData(data);

      complexity: [
        'error',
        {
          max: 13, // Cyclomatic complexity limit. Each path through code (if/else, switches, loops)
          // adds complexity. High complexity = harder to test & maintain.
          // Break complex functions into smaller, focused ones.
        },
      ],

      'max-lines-per-function': [
        'error',
        {
          max: 70, // Target length for most functions
          skipBlankLines: true,
          skipComments: true,
          IIFEs: true, // Include immediately-invoked function expressions
        },
      ],

      'max-params': ['warn', 3], // Functions with many parameters are hard to use and often indicate a need for
      // object parameters or splitting functionality.
      // Example - Instead of:
      //   function updateUser(id, name, email, role, status)
      // Use:
      //   function updateUser({ id, name, email, role, status })

      'max-statements': ['warn', 15], // Warn on functions with too many statements. Large functions typically try to do
      // too much and should be split into focused, single-responsibility functions.

      // Code Quality & Style
      'max-len': [
        'error',
        {
          code: 100, // Standard line length limit
          tabWidth: 2,
          ignoreComments: false,
          ignoreTrailingComments: false,
          ignoreUrls: true,
          ignoreStrings: true,
          ignoreTemplateLiterals: true,
          ignoreRegExpLiterals: true,
        },
      ],

      'no-nested-ternary': 'error', // Nested ternaries are hard to read. Use if statements
      // or multiple assignments instead.

      'arrow-body-style': ['error', 'as-needed'], // Keep arrow functions concise. Only use blocks when necessary.
      // Example - Instead of: x => { return x + 1; }
      // Use: x => x + 1

      // Code Safety
      'max-classes-per-file': ['error', 1], // One class per file enforces single responsibility principle and
      // makes code easier to find and maintain.

      'no-multiple-empty-lines': [
        'warn',
        {
          max: 2, // Single blank line maximum
          maxEOF: 1, // Max blank lines at end of file
          maxBOF: 0, // No blank lines at start of file
        },
      ],
    },
  },

  // Include Vue.js recommended configuration directly
  ...pluginVue.configs['flat/strongly-recommended'],

  /**
   * Vue Component Rules
   * Specific rules for Vue single-file components
   */
  {
    files: ['src/**/*.vue', 'tests/**/*.{vue}'],
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
      tailwindcss: pluginTailwindCSS,
      '@typescript-eslint': tseslint,
      '@intlify/vue-i18n': pluginVueI18n,
    },
    rules: {
      'no-multiple-empty-lines': ['warn', { max: 1 }], // Limit empty lines to 1

      // Prefer camelCase over kebab-case
      // https://eslint.vuejs.org/rules/attribute-hyphenation.html
      'vue/attribute-hyphenation': [
        'warn',
        'always',
        {
          ignore: [],
        },
      ],

      // Ensure valid template root
      'vue/valid-template-root': 'error',
      // Configure self-closing tag behavior
      'vue/html-self-closing': [
        'error',
        {
          html: {
            void: 'always',
            normal: 'never',
            component: 'always',
          },
          svg: 'always',
          math: 'always',
        },
      ],
      // Avoid attribute clutter
      'vue/max-attributes-per-line': [
        'error',
        {
          singleline: 2,
          multiline: 1,
        },
      ],
      // Enforce consistent line breaks in template elements
      'vue/html-closing-bracket-newline': [
        'warn',
        {
          singleline: 'never',
          multiline: 'never',
          selfClosingTag: {
            singleline: 'never',
            multiline: 'always',
          },
        },
      ],
      'tailwindcss/classnames-order': 'warn', // Maintain consistent class ordering
      'tailwindcss/no-custom-classname': 'warn', // Flag undefined Tailwind classes

      'max-len': [
        'warn',
        {
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
        },
      ],

      // ...tseslint.configs.recommended.rules,
      '@typescript-eslint/no-unused-vars': 'error', // Prevent unused variables

      // Note: you must disable the base rule as it can report incorrect errors
      'no-unused-expressions': 'off',
      '@typescript-eslint/no-unused-expressions': [
        'error',
        {
          allowShortCircuit: true,
          allowTernary: true,
          allowTaggedTemplates: true,
        },
      ],

      // Only warn explicit any in declaration files
      '@typescript-eslint/no-explicit-any': 'warn',

      '@intlify/vue-i18n/no-deprecated-modulo-syntax': 'error', // Enforce modern i18n syntax
      // https://github.com/francoismassart/eslint-plugin-tailwindcss/tree/master/docs/rules
    },
  },
  /**
   * TypeScript Declaration Files
   * Specific configuration for .d.ts files
   */
  {
    files: ['**/*.d.ts'],
    languageOptions: {
      parserOptions: {
        ecmaVersion: 'latest',
        sourceType: 'module',
        project: './tsconfig.json',
      },
    },
    plugins: {
      '@typescript-eslint': tseslint,
    },
    rules: {
      ...tseslint.configs.recommended.rules,
      // Allow explicit any in declaration files
      '@typescript-eslint/no-explicit-any': 'off',
      // Allow empty interfaces in declaration files
      '@typescript-eslint/no-empty-interface': 'off',
    },
  },

  // Include Tailwind recommended configuration
  ...pluginTailwindCSS.configs['flat/recommended'],
  {
    settings: {
      tailwindcss: {
        // These are the default values but feel free to customize
        callees: ['classnames', 'clsx', 'ctl'],
        config: 'tailwind.config.ts', // returned from `loadConfig()` utility if not provided
        cssFiles: ['**/*.css', '!**/node_modules', '!**/.*', '!**/dist', '!**/build'],
        cssFilesRefreshRate: 5_000,
        removeDuplicates: true,
        skipClassAttribute: false,
        whitelist: [],
        tags: [], // can be set to e.g. ['tw'] for use in tw`bg-blue`
        classRegex: '^class(Name)?$', // can be modified to support custom attributes. E.g. "^tw$" for `twin.macro`
      },
    },
  },

  // Use this prettier plugin for eslint, which disables conflicting rules.
  // This plugin is a workaround for ESLint and Prettier conflicts. Simply,
  // uncomment the next line to enable it (don't forget to import it at the
  //  top): `import eslintConfigPrettier from 'eslint-config-prettier';
  // eslintConfigPrettier,

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

  /**
   * Test Files Configuration
   * Relaxes naming conventions and adds specific rules for test files
   */
  {
    files: ['tests/**/*.spec.{ts,vue,d.ts}', 'tests/**/*.{vue,d.ts}'],
    languageOptions: {
      parser: parserTs,
      parserOptions: {
        ecmaVersion: 'latest',
        sourceType: 'module',
        project: ['./tsconfig.json', './tsconfig.test.json'],
        extraFileExtensions: ['.vue'],
      },
      globals: {
        // Vitest globals
        vitest: true,
        describe: true,
        it: true,
        expect: true,
        vi: true,
        beforeEach: true,
        afterEach: true,
        beforeAll: true,
        afterAll: true,
        test: true,
        suite: true,
      },
    },
    plugins: {
      '@typescript-eslint': tseslint, // Add this line to properly register the plugin
      vue: pluginVue,
    },
    rules: {
      'vue/multi-word-component-names': 'off', // Allow single-word names for test components

      // Test structure rules
      'max-nested-callbacks': ['error', 6], // Prevent test suite organization from becoming too granular and hard to navigate.
      // Deep nesting often indicates over-categorization - prefer clear, descriptive test names instead.
      'max-lines-per-function': ['warn', { max: 300 }], // Keep test cases focused
      // ... existing code ...
      'padding-line-between-statements': [
        'error',
        { blankLine: 'always', prev: '*', next: 'block' },
        { blankLine: 'always', prev: 'block', next: '*' },
        { blankLine: 'always', prev: '*', next: 'function' },
        { blankLine: 'always', prev: 'function', next: '*' },
      ],

      // Note: you must disable the base rule as it can report incorrect errors
      'no-unused-expressions': 'off',
      '@typescript-eslint/no-unused-expressions': [
        'warn',
        {
          allowShortCircuit: true,
          allowTernary: true,
          allowTaggedTemplates: true,
        },
      ],

      // Common test patterns
      '@typescript-eslint/no-explicit-any': 'off', // Allow any for mocking
      '@typescript-eslint/no-empty-function': 'off', // Allow empty mock functions
      '@typescript-eslint/no-non-null-assertion': 'off', // Allow non-null assertions in tests
      'no-console': 'off', // Allow console usage in tests
    },
  },
];
