// src/build/eslint/index.ts

/**
 * Custom ESLint Rules for OneTime Secret
 *
 * This module exports custom ESLint rules as a plugin for use with flat config.
 *
 * Usage in eslint.config.ts:
 * ```typescript
 * import otsRules from './src/build/eslint';
 *
 * export default [
 *   {
 *     plugins: { ots: otsRules },
 *     rules: {
 *       'ots/no-internal-id-in-url': 'warn',
 *     },
 *   },
 * ];
 * ```
 */

import noInternalIdInUrl from './no-internal-id-in-url';

const plugin = {
  meta: {
    name: 'eslint-plugin-ots',
    version: '1.0.0',
  },
  rules: {
    'no-internal-id-in-url': noInternalIdInUrl,
  },
};

export default plugin;
