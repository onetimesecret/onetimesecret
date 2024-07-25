import { createApp, defineAsyncComponent, Component } from 'vue'
import Homepage from '@/views/Homepage.vue'
import Dashboard from '@/views/Dashboard.vue'
import GlobalBroadcast from '@/components/GlobalBroadcast.vue'
import ThemeToggle from '@/components/ThemeToggle.vue'
import { ref } from 'vue';
import './style.css'

// Define a type for the component map
type ComponentMap = {
  [key: string]: Component | (() => Promise<Component>)
}

/**
 * Main page component
 *
 * Each page generally has a main component that is mounted to
 * the root element (`<div id="app"></div>`) in the HTML template
 * generated by the ruby Rack app. The server injects the name of
 * the component to mount as a global variable "vue_component_name".
 * If that variable is not present, that means there is no main
 * Vue component on the page. In that case we skip ahead to creating
 * and mounting the common components which are part of the layout
 * (i.e. in the header or footer templates).
 *
 */

const componentMap: ComponentMap = {
  'Homepage': Homepage,
  'Dashboard': Dashboard,
  'Customize': defineAsyncComponent(() => import('@/views/Customize.vue')),
  'Account': defineAsyncComponent(() => import('@/views/Account.vue')),
  'Shared': defineAsyncComponent(() => import('@/views/Shared.vue')),
  'Private': defineAsyncComponent(() => import('@/views/Private.vue')),
  //'Pricing': defineAsyncComponent(() => import('@/views/Pricing.vue')),
  'Pricing': defineAsyncComponent(() => import('@/views/PricingDual.vue')),
  //'Signup': defineAsyncComponent(() => import('@/views/Signup.vue')),
  'Feedback': defineAsyncComponent(() => import('@/views/Feedback.vue')),
  'Forgot': defineAsyncComponent(() => import('@/components/PasswordStrengthChecker.vue')),
}

if (window.vue_component_name && window.vue_component_name in componentMap) {
  const Component = componentMap[window.vue_component_name]
  const pageContentApp = createApp(Component)
  pageContentApp.mount('#app')

} else {
  console.info(`No component for: ${window.vue_component_name}`)
}


/**
 * Common components
 *
 * These are components mounted within the layout of the page, such as
 * in the header or footer. They are not tied to a specific page and
 * are always present on the site.
 *
 **/
const showBanner = ref(false);
const broadcastApp = createApp(GlobalBroadcast, {
  content: 'This is a global broadcast',
  show: showBanner.value,
})
broadcastApp.mount('#broadcast')

const themeToggleElement = document.querySelector('#theme-toggle');
if (themeToggleElement) {
  const toggleApp = createApp(ThemeToggle);
  toggleApp.mount('#theme-toggle');
}

function deobfuscateEmails(): void {
  document.querySelectorAll<HTMLElement>('.email').forEach(el => {
    const email = el.textContent?.replace(/ &#65;&#84; /g, "@").replace(/ AT /g, "@").replace(/ D0T /g, ".") || '';
    const subject = el.getAttribute('data-subject');
    const subjectParam = subject ? `?subject=${encodeURIComponent(subject)}` : '';
    el.innerHTML = `<a href="mailto:${encodeURIComponent(email)}${subjectParam}">${email}</a>`;
  });
}

// Call this function when the DOM is ready or after dynamic content is loaded
document.addEventListener('DOMContentLoaded', deobfuscateEmails);
window.deobfuscateEmails = deobfuscateEmails;
