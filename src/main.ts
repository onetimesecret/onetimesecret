// src/main.ts

// Put Zod in jitless mode before any schema module loads. Zod v4's object parser
// probes for `new Function` support (its JIT fast path); under our CSP that probe
// trips a `script-src` violation. This side-effect import must stay first so the
// config is applied before any z.object() is constructed. See configureZod.ts.
import './plugins/core/configureZod';

// Ensures modulepreload works in all browsers, improving
// performance by preloading modules.
import 'vite/modulepreload-polyfill';
import App from './App.vue';
import './assets/style.css';
import { startApp } from './plugins/core/startApp';
import { createAppRouter } from './router';
import { installPreloadErrorHandler } from './utils/preloadError';

// A lazy chunk that fails to load (typically a tab still running the previous
// build after a deployment) reloads the page once, through the ADR-046 forced
// page load bound so a chunk that keeps failing cannot reload the tab in a
// loop. See src/utils/preloadError.ts.
installPreloadErrorHandler();

/**
 * Initialize the Vue application with all required plugins, then mount it
 * once the initial navigation, including the visitor's locale, has resolved.
 * startApp owns the order, the app-ready flag and the startup-failure flag.
 */
void startApp({ root: App, createRouter: createAppRouter, debug: false });
