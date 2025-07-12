// src/main.ts

// Ensures modulepreload works in all browsers, improving
// performance by preloading modules.
import { createApp } from 'vue';
import 'vite/modulepreload-polyfill';
import App from './App.vue';
import './assets/style.css';
import { AppInitializer } from './plugins/core/appInitializer';

/**
 * Initialize and mount the Vue application with all required plugins.
 */
const app = createApp(App);
app.use(AppInitializer, { debug: false });
app.mount('#app');
