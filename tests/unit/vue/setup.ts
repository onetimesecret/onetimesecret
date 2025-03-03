// tests/unit/vue/setup.ts
/* global global */
import { autoInitPlugin } from '@/plugins/pinia/autoInitPlugin';
import { createApi } from '@/api';
import { createI18n } from 'vue-i18n';
import { createTestingPinia } from '@pinia/testing';
import { vi } from 'vitest';
import { createApp, h } from 'vue';
import type { ComponentPublicInstance } from 'vue';
import type { OnetimeWindow } from '@/types/declarations/window';
import { AxiosInstance } from 'axios';
import AxiosMockAdapter from 'axios-mock-adapter';

// Mock global objects that JSDOM doesn't support
global.fetch = vi.fn();
global.Request = vi.fn();
global.Response = {
  error: vi.fn(),
  json: vi.fn(),
  redirect: vi.fn(),
  prototype: Response.prototype,
} as unknown as typeof Response;

export function createVueWrapper() {
  const app = createApp({
    render() {
      return h('div', [this.$slots.default?.()]);
    },
  });

  // Setup i18n with composition API mode
  const i18n = createI18n({
    legacy: false,
    locale: 'en',
    fallbackLocale: 'en',
    messages: { en: {} },
  });

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
  /** Initial window state (default: stateFixture) */
  windowState?: OnetimeWindow;
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
    windowState = {}, // allow test cases to provide their own state
  } = options;

  try {
    // Create API and mock if requested
    const api = createApi();
    const axiosMock = mockAxios ? new AxiosMockAdapter(api) : null;

    // Create Vue app context
    const { app } = createVueWrapper();

    // Provide API to Vue context (critical for dependency injection)
    app.provide('api', api);

    // Create and register Pinia
    //
    // `createTestingPinia()` creates a testing version of Pinia that mocks all
    // actions by default. Use `createTestingPinia({ stubActions: false })` if
    // you want to test actions. Otherwise they don't actually get called.
    const pinia = createTestingPinia({
      stubActions,
      plugins: [autoInitPlugin()],
    });

    app.use(pinia);

    // Optionally mount the app to activate full Vue context
    let appInstance = null;
    if (mountApp) {
      const el = document.createElement('div');
      appInstance = app.mount(el);
    }

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
