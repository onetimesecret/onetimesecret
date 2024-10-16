<template>
  <footer class="min-w-[320px] bg-gray-100 dark:bg-gray-800 py-8 overflow-visible w-full transition-all duration-300">
    <div class="container my-4 mx-auto px-4 max-w-2xl">
      <div v-if="displayLinks"
           class="grid grid-cols-2 md:grid-cols-3 gap-8 mb-8 py-10 pl-4 sm:pl-8 md:pl-16">

        <!-- Company links -->
        <div class="space-y-4">
          <h3 class="font-semibold text-gray-800 dark:text-gray-200 text-xl">Company</h3>
          <ul class="space-y-2">
            <li>
              <router-link to="/about"
                           class="text-gray-600 dark:text-gray-300 hover:text-brand-500 dark:hover:text-brand-400 transition-colors duration-300 text-base"
                           aria-label="Learn about our company">About</router-link>
            </li>
            <li v-if="plansEnabled && authentication.enabled">
              <router-link to="/pricing"
                           class="text-gray-600 dark:text-gray-300 hover:text-brand-500 dark:hover:text-brand-400 transition-colors duration-300 text-base"
                           aria-label="View our subscription pricing">Pricing</router-link>
            </li>
            <li v-if="supportHost">
              <a :href="`${supportHost}/blog`"
                 class="text-gray-600 dark:text-gray-300 hover:text-brand-500 dark:hover:text-brand-400 transition-colors duration-300 text-base"
                 aria-label="Read our latest blog posts"
                 target="_blank"
                 rel="noopener noreferrer">Blog</a>
            </li>
          </ul>
        </div>

        <!-- Resources links -->
        <div class="space-y-4">
          <h3 class="font-semibold text-gray-800 dark:text-gray-200 text-xl">Resources</h3>
          <ul class="space-y-2">
            <li>
              <a href="https://github.com/onetimesecret/onetimesecret"
                 class="text-gray-600 dark:text-gray-300 hover:text-brand-500 dark:hover:text-brand-400 transition-colors duration-300 text-base"
                 aria-label="View our source code on GitHub"
                 target="_blank"
                 rel="noopener noreferrer">GitHub</a>
            </li>
            <li v-if="supportHost">
              <a :href="`${supportHost}/docs`"
                 aria-label="Access our documentation"
                 class="text-gray-600 dark:text-gray-300 hover:text-brand-500 dark:hover:text-brand-400 transition-colors duration-300 text-base"
                 target="_blank"
                 rel="noopener noreferrer">Docs</a>
            </li>
            <li v-if="supportHost">
              <a :href="`${supportHost}/docs/rest-api`"
                 aria-label="Explore our API documentation"
                 class="text-gray-600 dark:text-gray-300 hover:text-brand-500 dark:hover:text-brand-400 transition-colors duration-300 text-base"
                 target="_blank"
                 rel="noopener noreferrer">API</a>
            </li>
            <li>
              <a href="https://status.onetimesecret.com/"
                 class="text-gray-600 dark:text-gray-300 hover:text-brand-500 dark:hover:text-brand-400 transition-colors duration-300 text-base"
                 aria-label="Check our service status"
                 target="_blank"
                 rel="noopener noreferrer">Status</a>
            </li>
          </ul>
        </div>

        <!-- Legal links -->
        <div class="space-y-4 col-span-2 md:col-span-1">
          <h3 class="font-semibold text-gray-800 dark:text-gray-200 text-xl">Legal</h3>
          <ul class="space-y-2">
            <li>
              <router-link to="/info/privacy"
                           class="text-gray-600 dark:text-gray-300 hover:text-brand-500 dark:hover:text-brand-400 transition-colors duration-300 text-base"
                           aria-label="Read our Privacy Policy">Privacy</router-link>
            </li>
            <li>
              <router-link to="/info/terms"
                           class="text-gray-600 dark:text-gray-300 hover:text-brand-500 dark:hover:text-brand-400 transition-colors duration-300 text-base"
                           aria-label="View our Terms and Conditions">Terms</router-link>
            </li>
            <li>
              <router-link to="/info/security"
                           class="text-gray-600 dark:text-gray-300 hover:text-brand-500 dark:hover:text-brand-400 transition-colors duration-300 text-base"
                           aria-label="Learn about our security measures">Security</router-link>
            </li>
          </ul>
        </div>
      </div>

      <div class="flex flex-col sm:flex-row justify-between items-center
                  border-t border-gray-200 dark:border-gray-700 pt-6">
        <div v-if="displayVersion"
             class="text-sm text-center sm:text-left mb-4 sm:mb-0
                    text-gray-500 dark:text-gray-400">
          &copy; {{ new Date().getFullYear() }} {{ companyName }}
        </div>
        <div v-if="displayToggles"
             class="flex flex-wrap items-center justify-center sm:justify-end space-x-4 mb-4 sm:mb-0">

          <div class="flex items-center space-x-2">
            <span class="text-sm font-medium text-gray-400 dark:text-gray-300">EU</span>
            <svg xmlns="http://www.w3.org/2000/svg"
                 class="h-5 w-5 text-slate-400"
                 viewBox="0 0 20 20"
                 fill="currentColor"
                 aria-hidden="true">
              <path fill-rule="evenodd"
                    d="M10 18a8 8 0 100-16 8 8 0 000 16zM4.332 8.027a6.012 6.012 0 011.912-2.706C6.512 5.73 6.974 6 7.5 6A1.5 1.5 0 019 7.5V8a2 2 0 004 0 2 2 0 011.523-1.943A5.977 5.977 0 0116 10c0 .34-.028.675-.083 1H15a2 2 0 00-2 2v2.197A5.973 5.973 0 0110 16v-2a2 2 0 00-2-2 2 2 0 01-2-2 2 2 0 00-1.668-1.973z"
                    clip-rule="evenodd" />
            </svg>
          </div>
          <ThemeToggle />

          <FeedbackToggle v-if="displayFeedback && authentication.enabled" />
        </div>
      </div>
    </div>
  </footer>
</template>


<script setup lang="ts">
import { ref } from 'vue'
import type { Props as DefaultProps } from '@/layouts/DefaultLayout.vue';
import FeedbackToggle from '@/components/FeedbackToggle.vue';
import ThemeToggle from '@/components/ThemeToggle.vue';
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

const companyName = ref('Onetime Secret');

</script>
