import router from '@/router';
import i18n from '@/i18n';
import { createApp } from 'vue';
import { createPinia } from 'pinia'
import App from './App.vue'

import './assets/style.css';

/**
 * Vue Application Initialization
 *
 * This code initializes our Vue application with the following features:
 * - Routing: Using Vue Router for client-side navigation
 * - Internationalization: Using i18n for multi-language support
 * - Global styles: Importing the main style.css file
 *
 * The application is created and mounted to the '#app' element in the DOM.
 */
const app = createApp(App);
app.use(i18n);
app.use(router);
app.use(createPinia());
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
