// https://eslint.org/docs/latest/use/getting-started
import globals from 'globals';
import pluginJs from '@eslint/js';
import tseslint from 'typescript-eslint';
import pluginVue from 'eslint-plugin-vue';

export default [
  {
    ignores: ['**/**', '!src/**'],
  },
  {
    files: ['src/**/*.{js,mjs,cjs,ts,vue}'],
  },// Ignore everything except src directory
  {
    files: ['src/**/*.js'],
    languageOptions: { sourceType: 'script' },
  },
  {
    languageOptions: { globals: globals.browser },
  },
  pluginJs.configs.recommended,
  //...tseslint.configs.recommended,
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
