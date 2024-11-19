<template>
  <footer class="
    w-full min-w-[320px]
    py-16
    bg-gray-100 dark:bg-gray-800
    transition-all duration-300"
          aria-label="Site footer">
    <div class="container mx-auto px-4 max-w-2xl">
      <FooterLinkLists v-if="displayLinks"
                       v-bind="$props" />

      <div class="
        flex flex-col-reverse
        justify-between items-center
        mt-6
        space-y-6 space-y-reverse md:space-y-0
        md:flex-row">
        <div class="
          w-full md:w-auto
          text-sm text-center md:text-left
          text-gray-500 dark:text-gray-400
          flex flex-wrap items-center justify-center md:justify-start gap-4">
          <span v-if="displayVersion">
            &copy; {{ new Date().getFullYear() }} {{ companyName }}.
          </span>
          <div v-if="!displayLinks" class="text-inherit">
            <router-link to="/info/terms" class="hover:text-gray-800 dark:hover:text-gray-100 transition-colors duration-200">Terms</router-link>
            <span class="mx-2">·</span>
            <router-link to="/info/privacy" class="hover:text-gray-800 dark:hover:text-gray-100 transition-colors duration-200">Privacy</router-link>
          </div>
        </div>

        <div v-if="displayToggles"
             class="
          flex flex-wrap
          items-center justify-center md:justify-end
          w-full md:w-auto
          space-x-4">
          <JurisdictionFooterNotice v-if="regionsEnabled && regions" />

          <ThemeToggle class="
            text-gray-500 dark:text-gray-400
            hover:text-gray-800 dark:hover:text-gray-100
            transition-colors duration-200"
                       aria-label="Toggle dark mode" />

          <FeedbackToggle v-if="displayFeedback && authentication.enabled"
                          class="
            text-gray-500 dark:text-gray-400
            hover:text-gray-800 dark:hover:text-gray-100
            transition-colors duration-200"
                          aria-label="Provide feedback" />
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
const companyName = ref('OnetimeSecret.com');
</script>
