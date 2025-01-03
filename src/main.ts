// src/main.ts

// Ensures modulepreload works in all browsers, improving
// performance by preloading modules.
import i18n, { setLanguage } from '@/i18n';
import { ErrorHandlerPlugin } from '@/plugins';
import { initWithPlugins } from '@/plugins/pinia';
import { createAppRouter } from '@/router';
import {
  useAuthStore,
  useDomainsStore,
  useJurisdictionStore,
  useLanguageStore,
  useMetadataStore,
} from '@/stores';
import { AxiosInstance } from 'axios';
import 'vite/modulepreload-polyfill';
import { createApp, watch } from 'vue';

import App from './App.vue';
import './assets/style.css';
import { createApi } from './utils/api';

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
  app.use(ErrorHandlerPlugin, {
    debug: process.env.NODE_ENV === 'development',
  });
  app.use(i18n);
  app.use(createAppRouter());

  // Initialize core stores & language
  const api = createApi();

  // NOTE (Jan 3): Issue is here, comment out to remove brower console error.
  // Continue replacing WindowProps with WindowService
  initializeStores(api);

  app.mount('#app');
}

// Separate function to initialize stores
function initializeStores(api: AxiosInstance) {
  // Create stores in order of dependencies
  const jurisdictionStore = useJurisdictionStore();
  const authStore = useAuthStore();
  const languageStore = useLanguageStore();
  const metadataStore = useMetadataStore();
  const domainsStore = useDomainsStore();

  // Initialize stores in order
  jurisdictionStore.init(window.regions);
  authStore.init();

  // Language initialization
  languageStore.init();
  const initialLocale = languageStore.getCurrentLocale;
  setLanguage(initialLocale);
  languageStore.setCurrentLocale(initialLocale);

  // Set up watchers AFTER store initialization
  watch(
    () => languageStore.currentLocale,
    async (newLocale) => {
      if (newLocale) {
        await setLanguage(newLocale);
      }
    }
  );

  // Initialize API-dependent stores last
  metadataStore.setupErrorHandler(api);
  domainsStore.setupErrorHandler(api);
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
