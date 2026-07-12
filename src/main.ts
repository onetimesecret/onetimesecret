// src/main.ts

// Put Zod in jitless mode before any schema module loads. Zod v4's object parser
// probes for `new Function` support (its JIT fast path); under our CSP that probe
// trips a `script-src` violation. This side-effect import must stay first so the
// config is applied before any z.object() is constructed. See configureZod.ts.
import './plugins/core/configureZod';

// Ensures modulepreload works in all browsers, improving
// performance by preloading modules.
import { createApp } from 'vue';

import 'vite/modulepreload-polyfill';
import App from './App.vue';
import './assets/style.css';
import { createAppRouter } from './router';
import { AppInitializer } from './plugins/core/appInitializer';
import { loggingService } from './services/logging.service';

// Handle Vite chunk loading failures that occur when cached HTML references
// stale chunk hashes after a deployment. Without this, users see a blank page.
// A single reload fetches the fresh HTML with correct chunk references.
window.addEventListener('vite:preloadError', (event) => {
  event.preventDefault();
  window.location.reload();
});

/**
 * Initialize and mount the Vue application with all required plugins.
 */
const app = createApp(App);
app.use(AppInitializer, { router: createAppRouter(), debug: false });
app.mount('#app');

/**
 * Deterministic app-readiness signal for E2E tests
 * (e2e/docs/e2e-remediation-plan.md, Phase 2.2). Tests wait on
 * `html[data-app-ready="true"]` instead of `networkidle` or polling
 * `window.__BOOTSTRAP_ME__`.
 *
 * Why this flag is truthful at this point:
 * - `app.mount()` is synchronous and runs App.vue's setup(), which activates
 *   useBrandTheme(). Its `immediate: true` watcher applies the brand palette
 *   (or clears overrides) with no awaits before the DOM writes, sourced from
 *   bootstrap data consumed before Pinia install — so by the time mount()
 *   returns, the initial brand theme has been applied.
 * - The initial route resolution (including lazy-loaded route components) IS
 *   asynchronous, so gate the flag on router.isReady(): "ready" then also
 *   means the first navigation has been resolved and rendered.
 */
app.config.globalProperties.$router
  .isReady()
  .then(() => {
    document.documentElement.dataset.appReady = 'true';
  })
  .catch((error: unknown) => {
    // Deliberately do NOT set the flag: a failed initial navigation means the
    // app is not usable, and E2E waits should fail loudly with a trace.
    loggingService.error(
      error instanceof Error
        ? error
        : new Error(`[main] Initial navigation failed; app-ready flag not set: ${String(error)}`)
    );
  });
