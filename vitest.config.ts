// vitest.config.ts

import vue from '@vitejs/plugin-vue';
import { resolve } from 'path';
import { defineConfig } from 'vitest/config';

// use mock service workers lib to mock API requests (any fetch or axios requests).

// test.environment is set per project (see `projects` below). Can also use
// magic comments per file:
//
//    @vitest-environment happy-dom
//    test('useTitle should work', () =>
//
// Note: test.environmentMatchGlobs was removed in vitest 4 along with
// test.workspace. test.projects is the only remaining mechanism.

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

// Anchored to this file, not process.cwd(), so the config resolves the same
// way when vitest is invoked from another working directory.
const ROOT = import.meta.dirname;

// Project entries do not inherit the root-level resolve.alias, so this map is
// repeated in each one below.
const alias = {
  '@': resolve(ROOT, './src'),
  '@tests': resolve(ROOT, './src/tests'),
  '@locales': resolve(ROOT, './locales'),
};

// Suites with no DOM dependency. Verified 2026-08-15: all 73 files pass under
// environment 'node' with no setupFiles, producing identical results.
//
// Caveat for anything added to these directories: the node project loads no
// setup files, so there are no globalThis.fetch/Request/Response stubs (those
// come from src/tests/setup.ts). A test here that calls fetch reaches the real
// network. It fails loudly rather than silently, but it will surprise you.
const NODE_GLOBS = [
  'src/tests/schemas/**/*.spec.ts', // 48
  'src/tests/contracts/**/*.spec.ts', // 10
  'src/tests/i18n/**/*.spec.ts', //  5
  'src/tests/scripts/**/*.spec.ts', //  4
  'src/tests/types/**/*.spec.ts', //  4
  'src/tests/build/**/*.spec.ts', //  2
];

const BASE_EXCLUDE = [
  '**/node_modules/**',
  '**/.trunk/**',
  '**/dist/**',
  '**/.{idea,git,cache,output,temp}/**',
  'src/tests/e2e/**', // Playwright E2E tests - run separately
];

// Shared by both projects. `globals: true` is load-bearing for at least
// src/tests/i18n/security-messages.spec.ts, which imports nothing from vitest.
const commonTestOptions = {
  globals: true,
  sequence: {
    hooks: 'list' as const, // runs beforeEachand afterEach in the order defined
  },
  typecheck: {
    enabled: false,
    tsconfig: './tsconfig.test.json',
  },
  // Reduce concurrency to prevent test runner crashes
  pool: 'forks' as const,
  // Handle unhandled promise rejections
  onConsoleLog: () => false, // Suppress console logs that crash the reporter
};

export default defineConfig({
  test: {
    // Stays at the root: one locales:sync for the whole run, not one per
    // project. Two projects racing on generated/locales/ is a write race.
    globalSetup: ['src/tests/globalSetup.ts'],
    coverage: {
      provider: 'v8',
      // Cobertura XML is uploaded to GitHub Code Quality; `text` prints a
      // summary in the CI log. Only emitted when run with --coverage.
      reporter: ['text', 'cobertura'],
      reportsDirectory: 'coverage',
      all: true, // include untested source files so they report as 0% covered
      include: ['src/**'],
      exclude: [
        'src/tests/**',
        'src/**/*.spec.ts',
        'src/**/*.spec.vue',
        'src/**/*.d.ts',
      ],
    },
    // ORDER MATTERS. With coverage.all, vitest transforms never-imported source
    // files to report them as 0% covered, and it does that through the FIRST
    // project whose root matches the file (BaseCoverageProvider
    // .createUncoveredFileTransformer). That project's environment picks the
    // vite transform mode: jsdom/happy-dom -> 'client', anything else -> 'ssr'.
    // With 'node' first, untested .vue files get SSR-transformed and several
    // report as 100% covered, inflating the totals (measured: line-rate
    // 0.6693 -> 0.6746, branch-rate 0.5605 -> 0.5757). Keeping 'dom' first
    // reproduces the single-project report, bar two .vue files the old config
    // dropped outright ("Failed to parse ... Excluding it from coverage") and
    // this one now reports at 0%: line-rate 0.6693 -> 0.6691.
    projects: [
      {
        plugins: [vue()],
        resolve: { alias },
        test: {
          ...commonTestOptions,
          name: 'dom',
          environment: 'jsdom',
          // The old config also included 'src/**/*.spec.vue', which matches
          // no files; dropped.
          include: ['src/tests/**/*.spec.ts'],
          // NODE_GLOBS must be excluded here or those files run in both
          // projects.
          exclude: [...BASE_EXCLUDE, ...NODE_GLOBS],
          setupFiles: [
            'src/tests/setup-env.ts',
            'src/tests/setup-stores.ts',
            'src/tests/setup-components.ts',
            'src/tests/setup.ts',
            'src/tests/setupRouter.ts',
          ],
        },
      },
      {
        plugins: [vue()],
        resolve: { alias },
        test: {
          ...commonTestOptions,
          name: 'node',
          environment: 'node',
          include: NODE_GLOBS,
          exclude: BASE_EXCLUDE,
          // All five setup files are window-dependent. Dropping them also
          // drops setup-env.ts's process-level unhandledRejection handler;
          // vitest's default handling applies here instead.
          setupFiles: [],
        },
      },
    ],
  },
});
