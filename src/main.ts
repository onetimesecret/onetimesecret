// src/main.ts

// Ensures modulepreload works in all browsers, improving
// performance by preloading modules.
import 'vite/modulepreload-polyfill';
import { createApp } from 'vue';
import App from './App.vue';
import './assets/style.css';
import { AppInitializer } from './plugins/core/appInitializer';

// Parse server injected data from the HTML document
const initialData = document.getElementById('onetime-state')?.textContent;
window.__ONETIME_STATE__ = initialData ? JSON.parse(initialData) : {};

/**
 * Initialize and mount the Vue application with all required plugins.
 */
const app = createApp(App);
app.use(AppInitializer, { debug: false });
app.mount('#app');
