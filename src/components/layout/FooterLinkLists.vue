<template>
  <div class="">
    <div class="grid grid-cols-2 md:grid-cols-3 gap-8 mb-8 py-6 pl-4 sm:pl-8 md:pl-16">

      <!-- Company links -->
      <div class="space-y-4">
        <h3 class="font-semibold text-gray-800 dark:text-gray-200 text-xl">Company</h3>
        <ul class="prose dark:prose-invert font-brand space-y-2">
          <li>
            <router-link to="/about"
                        class="text-gray-600 dark:text-gray-400 hover:text-brand-500 dark:hover:text-brand-400 transition-colors duration-300 text-xl md:text-lg"
                        aria-label="Learn about our company">About</router-link>
          </li>
          <li v-if="plansEnabled && authentication.enabled">
            <router-link to="/pricing"
                        class="text-gray-600 dark:text-gray-400 hover:text-brand-500 dark:hover:text-brand-400 transition-colors duration-300 text-xl md:text-lg"
                        aria-label="View our subscription pricing">Pricing</router-link>
          </li>
          <li v-if="supportHost">
            <a :href="`https://blog.onetimesecret.com`"
              class="text-gray-600 dark:text-gray-400 hover:text-brand-500 dark:hover:text-brand-400 transition-colors duration-300 text-xl md:text-lg"
              aria-label="Read our latest blog posts"
              target="_blank"
              rel="noopener noreferrer">Blog</a>
          </li>
        </ul>
      </div>

      <!-- Resources links -->
      <div class="space-y-4">
        <h3 class="font-semibold text-gray-800 dark:text-gray-200 text-xl">Resources</h3>
        <ul class="prose dark:prose-invert font-brand space-y-2">
          <li>
            <a href="https://github.com/onetimesecret/onetimesecret"
              class="text-gray-600 dark:text-gray-400 hover:text-brand-500 dark:hover:text-brand-400 transition-colors duration-300 text-xl md:text-lg"
              aria-label="View our source code on GitHub"
              target="_blank"
              rel="noopener noreferrer">GitHub</a>
          </li>
          <li v-if="supportHost">
            <a :href="`${supportHost}/docs`"
              aria-label="Access our documentation"
              class="text-gray-600 dark:text-gray-400 hover:text-brand-500 dark:hover:text-brand-400 transition-colors duration-300 text-xl md:text-lg"
              target="_blank"
              rel="noopener noreferrer">Docs</a>
          </li>
          <li v-if="supportHost">
            <a :href="`${supportHost}/docs/rest-api`"
              aria-label="Explore our API documentation"
              class="text-gray-600 dark:text-gray-400 hover:text-brand-500 dark:hover:text-brand-400 transition-colors duration-300 text-xl md:text-lg"
              target="_blank"
              rel="noopener noreferrer">API</a>
          </li>
          <li>
            <a href="https://status.onetimesecret.com/"
              class="text-gray-600 dark:text-gray-400 hover:text-brand-500 dark:hover:text-brand-400 transition-colors duration-300 text-xl md:text-lg"
              aria-label="Check our service status"
              target="_blank"
              rel="noopener noreferrer">Status</a>
          </li>
        </ul>
      </div>

      <!-- Legal links -->
      <div class="space-y-4 col-span-2 md:col-span-1">
        <h3 class="font-semibold text-gray-800 dark:text-gray-200 text-xl">Legals</h3>
        <ul class="prose dark:prose-invert font-brand space-y-2">
          <li>
            <router-link to="/info/privacy"
                        class="text-gray-600 dark:text-gray-400 hover:text-brand-500 dark:hover:text-brand-400 transition-colors duration-300 text-xl md:text-lg"
                        aria-label="Read our Privacy Policy">Privacy</router-link>
          </li>
          <li>
            <router-link to="/info/terms"
                        class="text-gray-600 dark:text-gray-400 hover:text-brand-500 dark:hover:text-brand-400 transition-colors duration-300 text-xl md:text-lg"
                        aria-label="View our Terms and Conditions">Terms</router-link>
          </li>
          <li>
            <router-link to="/info/security"
                        class="text-gray-600 dark:text-gray-400 hover:text-brand-500 dark:hover:text-brand-400 transition-colors duration-300 text-xl md:text-lg"
                        aria-label="Learn about our security measures">Security</router-link>
          </li>
        </ul>
      </div>

    </div>

    <!-- Border separator element -->
    <div class="border-t border-gray-200 dark:border-gray-700 my-2"></div>
  </div>
</template>

<script setup lang="ts">
import type { Props as DefaultProps } from '@/layouts/DefaultLayout.vue';
// Define the props for this layout, extending the DefaultLayout props
export interface Props extends DefaultProps {
  displayFeedback?: boolean
  displayLinks?: boolean
  displayVersion?: boolean
  displayToggles?: boolean
}

withDefaults(defineProps<Props>(), {
  displayFeedback: true,
  displayLinks: true,
  displayVersion: true,
  displayToggles: true,
});
</script>
