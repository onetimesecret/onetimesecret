// src/tests/utils/routerSetup.ts

import { config } from '@vue/test-utils';
import { beforeEach } from 'vitest';
import {
  createRouter,
  createWebHistory,
  routeLocationKey,
  routerKey,
  routerViewLocationKey,
} from 'vue-router';

export function setupRouter() {
  return createRouter({
    history: createWebHistory(),
    routes: [
      // Define your routes here
      { path: '/signin', name: 'SignIn', component: { template: '<div>Sign In</div>' } },
      // Add other routes as needed
    ],
  });
}

/**
 * For a test that mounts with a real router in `global.plugins`.
 *
 * src/tests/setupRouter.ts injects the router mock's values into
 * `config.global.provide` before every test. A real router provides the
 * same three keys when it installs, so Vue warned "App already provides
 * property" on every mount; the real router's values won either way.
 * Dropping the mock's copies first leaves exactly what each mount injected
 * before, without the warning. The mock's $router/$route mocks, its
 * RouterLink/RouterView stubs and matchedRouteKey (which the real router
 * does not provide at the app level) stay as they were. setupRouter.ts
 * injects them again before the next test.
 */
export function dropRouterMockProvides(): void {
  const provide = config.global.provide as Record<symbol, unknown>;
  delete provide[routerKey];
  delete provide[routeLocationKey];
  delete provide[routerViewLocationKey];
}

/** dropRouterMockProvides before every test in the file; call it at the top. */
export function useRealRouter(): void {
  beforeEach(dropRouterMockProvides);
}
