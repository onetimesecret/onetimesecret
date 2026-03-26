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
