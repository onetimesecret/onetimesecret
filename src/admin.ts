// src/admin.ts
//
// Second Rolldown entry: the isolated Colonel admin console bundle.
//
// This entry exists so admin code stops shipping in the customer bundle
// (`src/main.ts`). It mirrors main.ts's bootstrap shape but mounts an
// admin-only Vue app whose router (`createAdminRouter`) carries ONLY admin
// routes — it must never import `@/router` or `@/App`'s customer route
// graph, or the customer views would leak back into this chunk (and vice
// versa). The single-chunk CSP-nonce invariant holds because vite.config
// keeps `codeSplitting: false` for every entry.

// Put Zod in jitless mode before any schema module loads. Zod v4's object
// parser probes for `new Function` support (its JIT fast path); under our CSP
// that probe trips a `script-src` violation. This side-effect import must stay
// first so the config is applied before any z.object() is constructed.
import './plugins/core/configureZod';

import { createApp } from 'vue';

import 'vite/modulepreload-polyfill';
import App from './App.vue';
import './assets/style.css';
import { createAdminRouter } from './apps/admin/router';
import { AppInitializer } from './plugins/core/appInitializer';
import { loggingService } from './services/logging.service';

// Handle Vite chunk loading failures that occur when cached HTML references
// stale chunk hashes after a deployment. Without this, users see a blank page.
window.addEventListener('vite:preloadError', (event) => {
  event.preventDefault();
  window.location.reload();
});

/**
 * Initialize and mount the admin Vue application. Shares the customer app's
 * root component and initializer, but is handed an admin-only router so the
 * chunk stays free of customer route code.
 */
const app = createApp(App);
app.use(AppInitializer, { router: createAdminRouter(), debug: false });
app.mount('#app');

// Deterministic app-readiness signal for E2E tests (see src/main.ts for the
// rationale). Gated on router.isReady() so the initial admin route resolves.
app.config.globalProperties.$router
  .isReady()
  .then(() => {
    document.documentElement.dataset.appReady = 'true';
  })
  .catch((error: unknown) => {
    loggingService.error(
      error instanceof Error
        ? error
        : new Error(`[admin] Initial navigation failed; app-ready flag not set: ${String(error)}`)
    );
  });
