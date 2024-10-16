<template>
  <footer class="min-w-[320px] bg-gray-100 dark:bg-gray-800 py-8 overflow-visible w-full transition-all duration-300">
    <div class="container my-4 mx-auto px-4 max-w-2xl">
      <FooterLinkLists v-if="displayLinks" v-bind="$props" />

      <div class="flex flex-col sm:flex-row justify-between items-center pt-6">
        <!-- Footer content goes here -->
        <div v-if="displayVersion" class="text-sm text-center sm:text-left mb-4 sm:mb-0 text-gray-600 dark:text-gray-300">
          &copy; {{ new Date().getFullYear() }} {{ companyName }}. All rights reserved.
        </div>
        <div v-if="displayToggles" class="flex flex-wrap items-center justify-center sm:justify-end space-x-4 mb-4 sm:mb-0">
          <ThemeToggle class="text-gray-600 dark:text-gray-300 hover:text-gray-800 dark:hover:text-gray-100 transition-colors duration-200" />
          <div
               class="flex items-center space-x-2 bg-gray-100 dark:bg-gray-800 rounded-full px-3 py-1 text-xs font-medium text-gray-500 dark:text-gray-400">
            <span class="text-xs font-medium text-gray-600 dark:text-gray-300">EU</span>
            <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4 text-gray-500 dark:text-gray-400" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
              <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM4.332 8.027a6.012 6.012 0 011.912-2.706C6.512 5.73 6.974 6 7.5 6A1.5 1.5 0 019 7.5V8a2 2 0 004 0 2 2 0 011.523-1.943A5.977 5.977 0 0116 10c0 .34-.028.675-.083 1H15a2 2 0 00-2 2v2.197A5.973 5.973 0 0110 16v-2a2 2 0 00-2-2 2 2 0 01-2-2 2 2 0 00-1.668-1.973z" clip-rule="evenodd" />
            </svg>
          </div>
          <FeedbackToggle v-if="displayFeedback && authentication.enabled" class="text-gray-600 dark:text-gray-300 hover:text-gray-800 dark:hover:text-gray-100 transition-colors duration-200" />
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
import FooterLinkLists from '@/components/layout/FooterLinkLists.vue';

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
