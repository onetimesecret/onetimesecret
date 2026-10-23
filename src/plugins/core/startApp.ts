// src/plugins/core/startApp.ts

import { createApp, type Component } from 'vue';
import { isNavigationFailure, NavigationFailureType, type Router } from 'vue-router';

import { AppInitializer, showConsoleWarning, type AppInitializerOptions } from './appInitializer';
import { reloadPending } from '@/utils/preloadError';

export interface StartAppOptions extends Omit<AppInitializerOptions, 'router'> {
  /** The entry's root component. */
  root: Component;
  /** Builds the entry's router. Called inside startup, so a throw flags the shell. */
  createRouter: () => Router;
}

/**
 * Starts an entry's app (src/main.ts, src/admin.ts), in this order:
 * 1. Install services and router guards (AppInitializer). Installing the
 *    router starts the initial navigation. install() is synchronous; nothing
 *    here relies on app.use() awaiting a plugin.
 * 2. Await router.isReady(): the first navigation has resolved, including
 *    its lazy route components and the activation of the visitor's locale,
 *    which the route guards await. The server-rendered shell stays on screen
 *    meanwhile.
 * 3. Mount, so the first render already has that locale's messages. English
 *    is bundled with the entry, but a visitor on /?locale=bg must not see it
 *    while Bulgarian loads.
 * 4. Run startup work that needs translations (the console warning).
 * 5. Mark the app ready.
 *
 * Kept in one place so both entries start the same way. Each entry passes
 * its own root component and router factory, so this module imports neither
 * route graph.
 */
export async function startApp(options: StartAppOptions): Promise<void> {
  const { root, createRouter, ...initializerOptions } = options;
  try {
    const app = createApp(root);
    const router = createRouter();
    app.use(AppInitializer, { ...initializerOptions, router });
    await router.isReady();
    app.mount('#app');
    showConsoleWarning();
  } catch (error) {
    // Two failures hand off to a document load, which replaces the page:
    // a guard aborts the first navigation only for a hard navigation out of
    // this bundle, and a failed chunk may have started a reload
    // (src/utils/preloadError.ts). Leave the shell up for that load; neither
    // mount nor flag.
    if (isNavigationFailure(error, NavigationFailureType.aborted) || reloadPending()) return;

    // Startup failed before the app took over #app: an initializer threw, or
    // the initial navigation failed (a guard threw, a route chunk or the
    // visitor's locale did not load). Flag the server-rendered shell: its
    // stalled-load notice (#4596) then switches from the timeout copy to a
    // detected failure and stops the orb. Rethrow so the error still reaches
    // the console and global handlers.
    document.documentElement.dataset.appFailed = 'true';
    throw error instanceof Error
      ? error
      : new Error(`[startApp] Startup failed; app-ready flag not set: ${String(error)}`);
  }

  /**
   * Deterministic app-readiness signal for E2E tests
   * (e2e/docs/e2e-remediation-plan.md, Phase 2.2). Tests wait on
   * `html[data-app-ready="true"]` instead of `networkidle` or polling
   * `window.__BOOTSTRAP_ME__`.
   *
   * Why this flag is truthful at this point:
   * - The first navigation has resolved: router.isReady() settled before
   *   mount, so its lazy-loaded route components are loaded and the
   *   visitor's locale is active.
   * - `app.mount()` is synchronous. It renders the first route's view in that
   *   locale and runs App.vue's setup(), which activates useBrandTheme(). Its
   *   `immediate: true` watcher applies the brand palette (or clears
   *   overrides) with no awaits before the DOM writes, sourced from bootstrap
   *   data consumed before Pinia install — so by the time mount() returns,
   *   the initial brand theme has been applied.
   * A failed start never sets it, so E2E waits fail loudly with a trace.
   */
  document.documentElement.dataset.appReady = 'true';
}
