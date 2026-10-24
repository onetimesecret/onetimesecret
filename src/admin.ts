// src/admin.ts
//
// Second Rolldown entry: the isolated Colonel admin console bundle.
//
// This entry exists so admin code stops shipping in the customer bundle
// (`src/main.ts`). It mirrors main.ts's bootstrap shape but mounts an
// admin-only Vue app whose router (`createAdminRouter`) carries ONLY admin
// routes — it must never import `@/router` or `@/App`'s customer route
// graph, or the customer views would leak back into this entry's chunks (and
// vice versa). Both entries are built in one pass and share chunks for the
// code they have in common; see the CSP note in vite.config.ts for why the
// shared and lazy chunks need no nonce of their own.

// Put Zod in jitless mode before any schema module loads. Zod v4's object
// parser probes for `new Function` support (its JIT fast path); under our CSP
// that probe trips a `script-src` violation. This side-effect import must stay
// first so the config is applied before any z.object() is constructed.
import './plugins/core/configureZod';

import 'vite/modulepreload-polyfill';
import App from './App.vue';
import './assets/style.css';
import { createAdminRouter } from './apps/admin/router';
import { startApp } from './plugins/core/startApp';
import { installPreloadErrorHandler } from './utils/preloadError';

// A lazy chunk that fails to load reloads the page once, through the ADR-046
// forced page load bound (see src/main.ts and src/utils/preloadError.ts).
installPreloadErrorHandler();

/**
 * Initialize and mount the admin Vue application. Shares the customer app's
 * root component and startup sequence (startApp: mount after the initial
 * navigation, the app-ready and startup-failure flags), but is handed an
 * admin-only router so the chunk stays free of customer route code.
 */
void startApp({ root: App, createRouter: createAdminRouter, debug: false });
