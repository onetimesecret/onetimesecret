// src/tests/setup.ts

import { autoInitPlugin } from '@/plugins/pinia/autoInitPlugin';
import { createTestingPinia } from '@pinia/testing';
import type { AxiosInstance } from 'axios';
import type AxiosMockAdapter from 'axios-mock-adapter';
import { setActivePinia } from 'pinia';
import { vi } from 'vitest';
import type { App, ComponentPublicInstance } from 'vue';
import { createApp, h } from 'vue';
import { createI18n } from 'vue-i18n';
import { createSharedApiInstance, installSharedAxiosMock } from './setup-stores';

// Use the shared axios instance that works with AxiosMockAdapter
const createApi = (): AxiosInstance => createSharedApiInstance();

//import type { BootstrapPayload } from '@/types/declarations/window';

// De
// fine minimal BootstrapPayload interface for testing purposes
interface BootstrapPayload {
  shrimp?: string;
  authenticated?: boolean;
  baseuri?: string;
  locale?: string;
  supported_locales?: string[];
  fallback_locale?: string;
  default_locale?: string;
  [key: string]: any;
}

// Mock global objects that JSDOM doesn't support
globalThis.fetch = vi.fn();
globalThis.Request = vi.fn() as typeof Request;
globalThis.Response = {
  error: vi.fn(),
  json: vi.fn(),
  redirect: vi.fn(),
  prototype: Response.prototype,
} as unknown as typeof Response;

/**
 * Minimal shape the test suite consumes from the pass-through i18n: a Vue
 * plugin (every consumer installs it) plus a string-keyed `global.t`.
 *
 * Declared explicitly, and the instance cast to it, so tests can call
 * `i18n.global.t('some.literal.key')` directly. Left as the natural
 * `createI18n` return type, `global.t` carries the project-wide
 * `DefineLocaleMessage` augmentation (see generated/types/i18n-keys.d.ts):
 * resolving a literal key against that ~9000-entry schema from test code trips
 * TypeScript's instantiation-depth limit (TS2589). Inside components `t` comes
 * from `useI18n()` and stays cheap; the raw `global.t` overload set is the one
 * that explodes, so we loosen it here at the shared factory.
 */
export type TestI18n = {
  install: (app: App, ...options: unknown[]) => void;
  global: { t: (key: string, params?: Record<string, string>) => string };
};

/**
 * Creates pass-through i18n instance for tests (ADR-014).
 * Keys render as-is; no translations applied.
 */
export function createTestI18n(): TestI18n {
  return createI18n({
    legacy: false,
    locale: 'en',
    missingWarn: false,
    fallbackWarn: false,
    missing: (_, key) => key,
    messages: { en: {} as never },
  }) as unknown as TestI18n;
}

/**
 * Like {@link createTestI18n}, but installs real message bundles so a spec can
 * assert on the copy the component actually ships (missing/stale keys still
 * render as the raw key path, so wiring assertions catch them). Returns the
 * same loosened {@link TestI18n} shape — usable both as a mount plugin and for
 * direct `i18n.global.t('literal.key')` calls.
 *
 * Two TS2589 escapes, both isolated here so consumers don't re-derive them:
 *   - `messages` is typed `unknown`: a `JSON.parse` bundle is `any`, and the
 *     generated `DefineLocaleMessage` augmentation builds `Composer['t']`'s
 *     key-path union by recursing whatever schema `messages` resolves to;
 *     recursing `any` never bottoms out ("excessively deep"). `never` at the
 *     boundary short-circuits it while accepting the real bundle at runtime.
 *   - the loosened return type means reading `.global.t` never materializes the
 *     exploding augmented overload set either.
 */
export function createRealI18n(messages: Record<string, unknown>): TestI18n {
  return createI18n({
    legacy: false,
    locale: 'en',
    messages: messages as never,
  }) as unknown as TestI18n;
}

export function createVueWrapper() {
  const app = createApp({
    render() {
      return h('div', [this.$slots.default?.()]);
    },
  });

  // Setup i18n with pass-through mode (ADR-014)
  const i18n = createTestI18n();

  app.use(i18n);

  return { app };
}

/**
 * Setup options for test Pinia instance
 */
export interface SetupTestPiniaOptions {
  /** Whether to stub Pinia actions (default: false) */
  stubActions?: boolean;
  /** Whether to create an axios mock adapter (default: true) */
  mockAxios?: boolean;
  /** Whether to mount the app to activate Vue context (default: true) */
  mountApp?: boolean;
  /**
   * Whether stores run `init()` on creation, as they do in the app
   * (default: true). Pass `false` only in a spec that is ABOUT `init()` —
   * one that calls it with its own options or timing, or asserts the state
   * before it has run. Everything else should see an initialized store.
   */
  autoInit?: boolean;
  /** Initial window state (default: stateFixture) */
  windowState?: BootstrapPayload;
}

/**
 * Result of setupTestPinia with all created test objects
 */
export interface TestPiniaSetup {
  /** The Pinia instance */
  pinia: ReturnType<typeof createTestingPinia>;
  /** The API instance (axios) */
  api: AxiosInstance;
  /** The axios mock adapter (if mockAxios is true) */
  axiosMock: AxiosMockAdapter | null;
  /** The Vue app instance */
  app: ReturnType<typeof createApp>;
  /** The mounted app instance (if mountApp is true) */
  appInstance: ComponentPublicInstance | null;
}

/**
 * Creates a test environment with Pinia store support, API mocking, and proper Vue context.
 *
 * @example
 * ```ts
 * // Basic usage
 * const { store, axiosMock } = await setupTestPinia();
 *
 * // With options
 * const { store, axiosMock } = await setupTestPinia({
 *   stubActions: true,
 *   mockAxios: true
 * });
 *
 * // Access the store
 * const store = useMyStore();
 * ```
 */
export async function setupTestPinia(options: SetupTestPiniaOptions = {}): Promise<TestPiniaSetup> {
  const {
    stubActions = false,
    mockAxios = true,
    mountApp = true,
    autoInit = true,
    windowState: _windowState = {}, // allow test cases to provide their own state
  } = options;

  try {
    // Create API and mock if requested
    // The shared instance is also what the `inject('api')` fallback returns
    // (setup-stores.ts), and the adapter installed here becomes the one
    // `getGlobalAxiosMock()` returns: one instance, one adapter, whichever way
    // a spec reaches them.
    const api = createApi();
    const axiosMock = mockAxios ? installSharedAxiosMock() : null;

    // Create Vue app context
    const { app } = createVueWrapper();

    // Create and register Pinia FIRST (before providing dependencies)
    // The REAL plugin, as appInitializer registers it: every store with an
    // `init()` runs it on creation. Production also passes the device locale;
    // it is not passed here, so a spec that needs a locale calls
    // `init({ deviceLocale })` itself.
    const pinia = createTestingPinia({
      stubActions,
      plugins: autoInit ? [autoInitPlugin()] : [],
      createSpy: vi.fn, // Use Vitest's spy function
    });

    app.use(pinia);

    // Provide API to Vue context AFTER Pinia is installed
    app.provide('api', api);

    // Optionally mount the app to activate full Vue context
    let appInstance: ComponentPublicInstance | null = null;
    if (mountApp) {
      const el = document.createElement('div');
      appInstance = app.mount(el);
    }

    // Set active pinia instance for proper injection context
    setActivePinia(pinia);

    // Allow async operations to complete
    await Promise.resolve();
    await new Promise((resolve) => setTimeout(resolve, 0));

    return {
      pinia,
      api,
      axiosMock,
      app,
      appInstance,
    };
  } catch (error) {
    // We used to revert window state on error here but now we don't need to
    // becasue we don't muck with window object directly. We stub it instead.

    throw error;
  }
}
