// src/plugins/pinia/autoInitPlugin.ts

import { PiniaPluginContext } from 'pinia';
import type { PiniaPluginOptions } from './types';

/**
 * Vue 3 Dependency Injection Architecture
 * ======================================
 *
 * Our application uses Vue's built-in dependency injection system for service access:
 *
 * 1. Core services are provided at the app level:
 *    ```
 *    // In app initialization (src/plugins/core/appInitializer.ts)
 *    app.provide('api', api);
 *    ```
 *
 * 2. Components and stores access services with inject():
 *    ```
 *    // In stores or components
 *    const $api = inject('api') as AxiosInstance;
 *    ```
 *
 * Store Initialization Best Practices
 * ----------------------------------
 * - Store initialization should be synchronous and focused on structure setup
 * - Keep initialization (init()) separate from data loading (loadXYZ())
 * - Use Vue's DI system for service access, not Pinia plugin options
 *
 * Example pattern:
 * ```
 * export const useDataStore = defineStore('data', () => {
 *   // Service access via Vue DI
 *   const $api = inject('api') as AxiosInstance;
 *
 *   // State
 *   const data = ref(null);
 *   const isLoading = ref(false);
 *   const error = ref(null);
 *
 *   // Synchronous initialization (structure only)
 *   function init() {
 *     // No API calls here
 *     return { isInitialized: true };
 *   }
 *
 *   // Async data loading (call after initialization)
 *   async function loadData() {
 *     isLoading.value = true;
 *     try {
 *       data.value = await $api.get('/endpoint');
 *     } catch (err) {
 *       error.value = err;
 *     } finally {
 *       isLoading.value = false;
 *     }
 *   }
 *
 *   return { data, isLoading, error, init, loadData };
 * });
 * ```
 *
 * Testing Considerations
 * ---------------------
 * 1. Always provide mock services in tests:
 *    ```
 *    const app = createApp();
 *    app.provide('api', mockApiInstance);
 *    ```
 *
 * 2. Test initialization and data loading separately:
 *    ```
 *    it('initializes correctly', () => {
 *      const store = useDataStore();
 *      store.init();
 *      expect(store.isInitialized).toBe(true);
 *    });
 *
 *    it('loads data', async () => {
 *      const store = useDataStore();
 *      await store.loadData();
 *      expect(store.data).toEqual(expectedData);
 *    });
 *    ```
 *
 * 3. When testing stores directly, ensure proper DI setup:
 *    ```
 *    // In setup.ts for tests
 *    export async function setupTestPinia() {
 *      const api = createApi();
 *      const { app } = createVueWrapper();
 *
 *      const pinia = createTestingPinia({ stubActions: false });
 *      app.provide('api', api); // Critical for DI to work
 *      app.use(pinia);
 *
 *      return { pinia, api, app };
 *    }
 *    ```
 */

/**
 * Store initialization must run synchronously to ensure store state
 * is ready before router guards or components access it.
 */
export function autoInitPlugin(options: PiniaPluginOptions = {}) {
  return ({ store }: PiniaPluginContext) => {
    if (typeof store.init === 'function') {
      store.init(options);
    }
  };
}
