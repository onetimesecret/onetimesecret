import { createApp } from 'vue';
import { createPinia } from 'pinia';
import router from '@/router';
import i18n, { setLanguage } from '@/i18n';
import App from './App.vue';
import { useLanguageStore } from '@/stores/languageStore';
//import { useCsrfStore } from '@/stores/csrfStore';

import './assets/style.css';

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
  // Create Vue app instance and Pinia store
  const app = createApp(App);
  const pinia = createPinia();
  app.use(pinia);

  // Initialize language store
  const languageStore = useLanguageStore();

  // Determine initial locale
  // Priority: 1. Stored preference, 2. Browser language, 3. Default locale
  const storedLocale = localStorage.getItem('selected.locale');
  const initialLocale = storedLocale || navigator.language.split('-')[0] || 'en';

  // Set language before mounting the app
  // This ensures correct translations are available for the initial render
  await setLanguage(initialLocale);

  // Update language store to maintain consistency across the app
  languageStore.setCurrentLocale(initialLocale);

  // Apply other plugins
  // i18n is applied after setting the language to ensure it uses the correct locale
  app.use(i18n);
  app.use(router);

  // Mount the application
  // This is done last to ensure all setup is complete before rendering
  app.mount('#app');
}

// Start the application initialization process
initializeApp();

/*
* Old-school global function. Actually the Altcha lib has a replacement
* for this, so we can 86 this in the future.
*/
function deobfuscateEmails(): void {
  document.querySelectorAll<HTMLElement>('.email').forEach(el => {
    const email = el.textContent?.replace(/ &#65;&#84; /g, "@").replace(/ AT /g, "@").replace(/ D0T /g, ".") || '';
    const subject = el.getAttribute('data-subject');
    const subjectParam = subject ? `?subject=${encodeURIComponent(subject)}` : '';
    el.innerHTML = `<a class="dark:text-gray-300" href="mailto:${encodeURIComponent(email)}${subjectParam}">${email}</a>`;
  });
}

// Call this function when the DOM is ready or after dynamic content is loaded
document.addEventListener('DOMContentLoaded', deobfuscateEmails);

// Add it to the global scope for use in other scripts
window.deobfuscateEmails = deobfuscateEmails;
