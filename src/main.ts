// src/main.ts

// Ensures modulepreload works in all browsers, improving
// performance by preloading modules.
import i18n from '@/i18n';
import { initWithPlugins } from '@/plugins/pinia/initPlugin';
import { ErrorHandlerPlugin } from '@/plugins';
import { DEBUG } from '@/utils/debug';
import 'vite/modulepreload-polyfill';
import { createApp } from 'vue';

import App from './App.vue';
import './assets/style.css';
import { createAppRouter } from './router';

/**
 * Initialize and mount the Vue application with proper language settings.
 *
 * The initialization process follows these steps:
 * 1. Create the Vue app instance and Pinia store.
 * 2. Determine the initial locale based on user preference or system settings.
 * 3. Set the application language before mounting.
 * 4. Update the language store for consistency.
 * 5. Apply plugins (i18n, router).
 * 6. Mount the application.
 *
 * This order ensures that:
 * - The correct language is available from the first render.
 * - User language preferences are respected.
 * - The language store is consistent with the actual app language.
 * - All components have access to the correct translations immediately.
 *
 * Using an async function allows us to wait for language loading
 * before mounting the app, preventing any flash of untranslated content.
 */
async function initializeApp() {
  const app = createApp(App);

  // Initialize Pinia with plugins
  const pinia = initWithPlugins({
    errorHandler: {
      notify: (message, severity) => console.log(`[notify] ${severity}: ${message}`),
      log: (error) => console.error('Error:', error),
    },
  });
  app.use(pinia);

  // Core plugins
  app.use(ErrorHandlerPlugin, { debug: DEBUG });

  app.use(i18n);
  app.use(createAppRouter());

  app.mount('#app');
}

// Start the application initialization process
initializeApp().catch((error) => {
  console.error('Failed to initialize app:', error);
});

const notice = `
┏┓┳┓┏┓┏┳┓┳┳┳┓┏┓
┃┃┃┃┣  ┃ ┃┃┃┃┣
┗┛┛┗┗┛ ┻ ┻┛ ┗┗┛

`;

console.log(notice);
