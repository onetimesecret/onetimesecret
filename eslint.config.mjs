// https://eslint.org/docs/latest/use/getting-started
// Run manually: pnpm run lint
import globals from 'globals';
import pluginJs from '@eslint/js';
import tseslint from 'typescript-eslint';
import pluginVue from 'eslint-plugin-vue';

export default [
  // Ignore everything except src directory
  {
    ignores: ['**/**', '!src/**', '!vite.config.ts'],
  },
  {
    files: ['src/**/*.{js,mjs,cjs,ts,vue}', 'vite.config.ts'],
  },
  {
    languageOptions: { globals: globals.browser },
  },
  ...tseslint.configs.recommended,
  ...pluginVue.configs['flat/essential'],
  {
    files: ['src/**/*.vue'],
    languageOptions: {
      parserOptions: {
        parser: tseslint.parser,
      },
    },
  },
  {
    rules: {
        "no-unused-vars": "error",
        "no-undef": "error"
    }
  },
  // Directly integrate what would have been an override
  {
    files: ["src/views/*.vue", "src/layouts/*.vue"], // Target files in the views directory
    rules: {
      "vue/multi-word-component-names": "off" // Turn off the rule
    }
  }
];
