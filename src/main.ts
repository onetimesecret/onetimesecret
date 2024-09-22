
import App from './App.vue'
import router from '@/router';
import i18n from './i18n';
import { createApp } from 'vue';

import './assets/style.css';

/**
 * Hybrid SPA / Server-Rendered Page Initialization
 *
 * This code handles the initialization of our application, which uses a hybrid
 * approach combining Single Page Application (SPA) features with traditional
 * server-rendered pages. This approach allows for a gradual transition from a
 * fully server-rendered site to a more modern SPA architecture.
 *
 * The process works as follows:
 *
 * 1. If the current page has a corresponding Vue route:
 *    - We initialize the full Vue app with routing capabilities.
 *    - This allows for client-side navigation between Vue-powered pages.
 *
 * 2. If the current page doesn't have a Vue route, but has a Vue component:
 *    - We fall back to the older method of mounting a single Vue component.
 *    - This preserves functionality for pages that have been partially
 *      upgraded.
 *
 * 3. If neither a route nor a component exists:
 *    - The page remains a traditional server-rendered page.
 *
 * Short-term benefits:
 * - Allows use of Vue Router for navigation on new, Vue-powered pages.
 * - Maintains compatibility with existing server-rendered and partially-
 *   upgraded pages.
 * - Enables incremental migration to a full SPA architecture.
 *
 * Long-term considerations:
 * - This hybrid approach may lead to inconsistent user experiences between
 *   different parts of the site.
 * - As more pages are converted to Vue components, the codebase should be
 *   refactored towards a full SPA model.
 *
 * @param {string} vueComponentName - The name of the Vue component for the
 *                                    current page, set by the server.
 */

const app = createApp(App);
app.use(i18n)
app.use(router);
app.mount('#app');


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
