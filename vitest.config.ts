// vitest.config.ts

import vue from '@vitejs/plugin-vue';
import { resolve } from 'path';
import { defineConfig } from 'vitest/config';

// use mock service workers lib to mock API requests (any fetch or axios requests).

// test.environment is global setting. Can also use magic comments
// per file (see below) or setting test.environmentMatchGlobs.
//
//    @vitest-environment happy-dom
//    test('useTitle should work', () =>

// vi.mock needs to be a top level so they can override at start time
// and cannot use local variables (i.e. ones defined outside).

// Use vitest snapshots, inline snapshots. vitest -u to update snapshots.
// Inline snapshots can be used to test outputs in place of console.log.
// Check in snapshots to git. When updating automatically, can confirm
// before committing.

// @vitejs/plugin-vue is used to traspile composition API components to
// javascript. That's what makes them testable and allos import vue files.

// @vue/test-utils, mount function. Testing components with props.

// Functional components: <template functional>, uses `props.keyName`, context (listeners, slots, children etc)
export default defineConfig({
  plugins: [vue()],
  test: {
    globals: true,
    environment: 'jsdom',
    include: ['tests/unit/vue/**/*.spec.ts', '**/*.spec.vue'],
    exclude: [
      '**/node_modules/**',
      '**/.trunk/**',
      '**/dist/**',
      '**/.{idea,git,cache,output,temp}/**',
    ],
    setupFiles: [
      'tests/unit/vue/setup-env.ts',
      'tests/unit/vue/setup-stores.ts',
      'tests/unit/vue/setup-components.ts',
      'tests/unit/vue/setup.ts',
      'tests/unit/vue/setupWindow.ts',
      'tests/unit/vue/setupRouter.ts',
    ],
    sequence: {
      hooks: 'list', // runs beforeEachand afterEach in the order defined
    },
    typecheck: {
      enabled: false,
      tsconfig: './tsconfig.test.json',
    },
    // Reduce concurrency to prevent test runner crashes
    pool: 'forks',
    poolOptions: {
      forks: {
        singleFork: true, // Run tests in single process to avoid conflicts
      },
    },
    // Handle unhandled promise rejections
    onConsoleLog: () => false, // Suppress console logs that crash the reporter
  },
  resolve: {
    alias: {
      '@': resolve(process.cwd(), './src'),
      '@tests': resolve(process.cwd(), './tests'),
    },
  },
});
