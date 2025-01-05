// src/main.ts

// Ensures modulepreload works in all browsers, improving
// performance by preloading modules.
import 'vite/modulepreload-polyfill';
import { createApp } from 'vue';
import App from './App.vue';
import './assets/style.css';
import { initializeApp } from './plugins/core/appInitializer';

/**
 * Initialize and mount the Vue application with all required services.
 *
 */
const app = createApp(App);
initializeApp(app, { debug: false });
app.mount('#app');
