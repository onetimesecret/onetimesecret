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

// Handle Vite chunk loading failures that occur when cached HTML references
// stale chunk hashes after a deployment. Without this, users see a blank page.
// A single reload fetches the fresh HTML with correct chunk references.
window.addEventListener('vite:preloadError', (event) => {
  event.preventDefault();
  window.location.reload();
});

/**
 * Initialize the Vue application with all required plugins, then mount it
 * once the initial navigation, including the visitor's locale, has resolved.
 * startApp owns the order, the app-ready flag and the startup-failure flag.
 */
void startApp({ root: App, createRouter: createAppRouter, debug: false });
