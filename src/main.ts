// src/main.ts

// Ensures modulepreload works in all browsers, improving
// performance by preloading modules.
import i18n from '@/i18n';
import { GlobalErrorBoundary } from '@/plugins';
import { initWithPlugins } from '@/plugins/pinia/initPlugin';
import { DEBUG } from '@/utils/debug';
import 'vite/modulepreload-polyfill';
import { createApp } from 'vue';

import App from './App.vue';
import './assets/style.css';
import { createAppRouter } from './router';

/**
 * Initialize and mount the Vue application with all required services.
 *
 * Initialization sequence:
 * 1. Create Vue app instance
 * 2. Initialize Pinia store system
 *    - API service injection
 *    - Error handling setup
 *    - Authentication management
 *    - Synchronous store initialization
 * 3. Setup core application services
 *    - Global error boundary
 *    - Internationalization
 *    - Router with authenticated guards
 * 4. Mount application
 *
 * This strict ordering ensures:
 * - Store state is fully initialized before router guards execute
 * - Authentication status is valid before protected routes load
 * - Error handling is available throughout the initialization process
 *
 * The async function allows for potential future async initialization
 * steps while maintaining proper error handling via the catch block.
 */
async function initializeApp() {
  const app = createApp(App);

  // Initialize Pinia first so stores are ready before router creation
  // Store initialization happens synchronously during plugin setup
  const pinia = initWithPlugins({
    errorHandler: {
      notify: (message, severity) => console.log(`[notify] ${severity}: ${message}`),
      log: (error) => console.error('Error:', error),
    },
  });
  app.use(pinia);

  // Router must be created after Pinia to ensure store state is available
  // for route guards and navigation handling
  app.use(GlobalErrorBoundary, { debug: DEBUG });
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
