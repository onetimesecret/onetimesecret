<template>
  <footer class="min-w-[320px] bg-gray-100 dark:bg-gray-800 py-8 w-full transition-all duration-300" aria-label="Site footer">
    <div class="container mx-auto px-4 max-w-2xl">
      <FooterLinkLists v-if="displayLinks" v-bind="$props" />

      <div class="flex flex-col sm:flex-row justify-between items-center pt-6">
        <div v-if="displayVersion" class="text-sm text-left w-full sm:w-auto mb-4 sm:mb-0 text-gray-600 dark:text-gray-300">
          &copy; {{ new Date().getFullYear() }} {{ companyName }}.
          <span class="hidden md:inline">All rights reserved.</span>
        </div>
        <div v-if="displayToggles" class="flex flex-wrap items-center justify-center sm:justify-end space-x-4">
          <JurisdictionFooterNotice v-if="regionsEnabled && regions" />

          <ThemeToggle
            class="text-gray-600 dark:text-gray-300 hover:text-gray-800 dark:hover:text-gray-100 transition-colors duration-200"
            aria-label="Toggle dark mode"
          />
          <FeedbackToggle
            v-if="displayFeedback && authentication.enabled"
            class="text-gray-600 dark:text-gray-300 hover:text-gray-800 dark:hover:text-gray-100 transition-colors duration-200"
            aria-label="Provide feedback"
          />
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
import JurisdictionFooterNotice from '@/components/JurisdictionFooterNotice.vue';
import { useWindowProps } from '@/composables/useWindowProps';

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

const { regions_enabled: regionsEnabled, regions } = useWindowProps(['regions_enabled', 'regions'])
const companyName = ref('Onetime Secret');
</script>
