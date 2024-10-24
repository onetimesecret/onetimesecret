<template>
  <footer class="
    w-full min-w-[320px]
    py-8
    bg-gray-100 dark:bg-gray-800
    transition-all duration-300"
          aria-label="Site footer">
    <div class="container mx-auto px-4 max-w-2xl">
      <FooterLinkLists v-if="displayLinks"
                       v-bind="$props" />

      <div class="flex flex-col space-y-6 pt-6 mt-6">
        <div class="
          flex
          items-center justify-between
          w-full
          max-w-[400px]
          mx-auto">
          <JurisdictionFooterNotice v-if="regionsEnabled && regions" />

          <ThemeToggle class="
            text-gray-600 dark:text-gray-300
            hover:text-gray-800 dark:hover:text-gray-100
            transition-colors duration-200"
                       aria-label="Toggle dark mode" />

          <FeedbackToggle v-if="displayFeedback && authentication.enabled"
                          class="
            text-gray-600 dark:text-gray-300
            hover:text-gray-800 dark:hover:text-gray-100
            transition-colors duration-200"
                          aria-label="Provide feedback" />
        </div>

        <div v-if="displayVersion"
             class="
          w-full
          text-sm text-center
          text-gray-600 dark:text-gray-300">
          &copy; {{ new Date().getFullYear() }} {{ companyName }}.
          All rights reserved.
        </div>
      </div>
    </div>
  </footer>
</template>

<script setup lang="ts">
import { ref } from 'vue';
import type { Props as DefaultProps } from '@/layouts/DefaultLayout.vue';
import FeedbackToggle from '@/components/FeedbackToggle.vue';
import ThemeToggle from '@/components/ThemeToggle.vue';
import FooterLinkLists from '@/components/layout/FooterLinkLists.vue';
import JurisdictionFooterNotice from '@/components/JurisdictionFooterNotice.vue';
import { useWindowProps } from '@/composables/useWindowProps';

export interface Props extends DefaultProps {
  displayFeedback?: boolean;
  displayLinks?: boolean;
  displayVersion?: boolean;
  displayToggles?: boolean;
}

withDefaults(defineProps<Props>(), {
  displayFeedback: true,
  displayLinks: true,
  displayVersion: true,
  displayToggles: true,
});

const { regions_enabled: regionsEnabled, regions } = useWindowProps(['regions_enabled', 'regions']);
const companyName = ref('Onetime Secret');
</script>
