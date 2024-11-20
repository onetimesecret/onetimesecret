<template>
  <div class="">
    <div class="mb-8 grid grid-cols-2 gap-8 py-6 pl-4 sm:pl-8 md:grid-cols-3 md:pl-16">
      <!-- Company links -->
      <div class="space-y-4">
        <h3 class="text-xl font-semibold text-gray-800 dark:text-gray-200">
          Company
        </h3>
        <ul class="prose space-y-2 font-brand dark:prose-invert">
          <li>
            <router-link
              to="/about"
              class="text-xl text-gray-600 transition-colors duration-300 hover:text-brand-500 dark:text-gray-400 dark:hover:text-brand-400 md:text-lg"
              aria-label="Learn about our company">
              About
            </router-link>
          </li>
          <li v-if="plansEnabled && authentication.enabled">
            <router-link
              to="/pricing"
              class="text-xl text-gray-600 transition-colors duration-300 hover:text-brand-500 dark:text-gray-400 dark:hover:text-brand-400 md:text-lg"
              aria-label="View our subscription pricing">
              Pricing
            </router-link>
          </li>
          <li v-if="supportHost">
            <a
              :href="`https://blog.onetimesecret.com`"
              class="text-xl text-gray-600 transition-colors duration-300 hover:text-brand-500 dark:text-gray-400 dark:hover:text-brand-400 md:text-lg"
              aria-label="Read our latest blog posts"
              target="_blank"
              rel="noopener noreferrer">Blog</a>
          </li>
        </ul>
      </div>

      <!-- Resources links -->
      <div class="space-y-4">
        <h3 class="text-xl font-semibold text-gray-800 dark:text-gray-200">
          Resources
        </h3>
        <ul class="prose space-y-2 font-brand dark:prose-invert">
          <li>
            <a
              href="https://github.com/onetimesecret/onetimesecret"
              class="text-xl text-gray-600 transition-colors duration-300 hover:text-brand-500 dark:text-gray-400 dark:hover:text-brand-400 md:text-lg"
              aria-label="View our source code on GitHub"
              target="_blank"
              rel="noopener noreferrer">GitHub</a>
          </li>
          <li v-if="supportHost">
            <a
              :href="`${supportHost}/docs`"
              aria-label="Access our documentation"
              class="text-xl text-gray-600 transition-colors duration-300 hover:text-brand-500 dark:text-gray-400 dark:hover:text-brand-400 md:text-lg"
              target="_blank"
              rel="noopener noreferrer">Docs</a>
          </li>
          <li v-if="supportHost">
            <a
              :href="`${supportHost}/docs/rest-api`"
              aria-label="Explore our API documentation"
              class="text-xl text-gray-600 transition-colors duration-300 hover:text-brand-500 dark:text-gray-400 dark:hover:text-brand-400 md:text-lg"
              target="_blank"
              rel="noopener noreferrer">API</a>
          </li>
          <li>
            <a
              href="https://status.onetimesecret.com/"
              class="text-xl text-gray-600 transition-colors duration-300 hover:text-brand-500 dark:text-gray-400 dark:hover:text-brand-400 md:text-lg"
              aria-label="Check our service status"
              target="_blank"
              rel="noopener noreferrer">Status</a>
          </li>
        </ul>
      </div>

      <!-- Legal links -->
      <div class="col-span-2 space-y-4 md:col-span-1">
        <h3 class="text-xl font-semibold text-gray-800 dark:text-gray-200">
          Legals
        </h3>
        <ul class="prose space-y-2 font-brand dark:prose-invert">
          <li>
            <router-link
              to="/info/privacy"
              class="text-xl text-gray-600 transition-colors duration-300 hover:text-brand-500 dark:text-gray-400 dark:hover:text-brand-400 md:text-lg"
              aria-label="Read our Privacy Policy">
              Privacy
            </router-link>
          </li>
          <li>
            <router-link
              to="/info/terms"
              class="text-xl text-gray-600 transition-colors duration-300 hover:text-brand-500 dark:text-gray-400 dark:hover:text-brand-400 md:text-lg"
              aria-label="View our Terms and Conditions">
              Terms
            </router-link>
          </li>
          <li>
            <router-link
              to="/info/security"
              class="text-xl text-gray-600 transition-colors duration-300 hover:text-brand-500 dark:text-gray-400 dark:hover:text-brand-400 md:text-lg"
              aria-label="Learn about our security measures">
              Security
            </router-link>
          </li>
        </ul>
      </div>
    </div>

    <!-- Border separator element -->
    <div class="my-2 border-t border-gray-200 dark:border-gray-700"></div>
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
