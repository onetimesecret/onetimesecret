// src/main.ts

// Ensures modulepreload works in all browsers, improving
// performance by preloading modules.
import { createApp } from 'vue';

import 'vite/modulepreload-polyfill';
import App from './App.vue';
import './assets/style.css';
import { AppInitializer } from './plugins/core/appInitializer';

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
app.use(AppInitializer, { debug: false });
app.mount('#app');

// Visual-archive backport (not in v0.25.11): the visual specs' readiness
// gate. Same semantics as current main.ts — flag only after the router has
// resolved and rendered the first navigation.
const router = app.config.globalProperties.$router;
if (router?.isReady) {
  void router.isReady().then(() => {
    document.documentElement.dataset.appReady = 'true';
  });
} else {
  document.documentElement.dataset.appReady = 'true';
}
