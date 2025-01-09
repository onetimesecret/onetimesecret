<!-- src/components/layout/DefaultFooter.vue -->

<script setup lang="ts">
import FooterLinkLists from '@/components/layout/FooterLinkLists.vue';
import ThemeToggle from '@/components/ThemeToggle.vue';
import { WindowService } from '@/services/window.service';
import type { LayoutProps } from '@/types/ui/layouts';

withDefaults(defineProps<LayoutProps>(), {
  displayFeedback: false,
  displayLinks: false,
  displayVersion: true,
  displayToggles: false,
});

const windowProps = WindowService.getMultiple([
  'regions_enabled', 'regions', 'authentication', 'site_host'
]);

</script>

<template>
  <footer class="w-full min-w-[320px] bg-gray-100 py-16 transition-all duration-300 dark:bg-gray-800"
          aria-label="Site footer">
    <div class="container mx-auto max-w-2xl px-4">
      <FooterLinkLists v-if="displayLinks"
                       v-bind="$props" />
    </div>

    <div class="

        flex-wrap items-center justify-center
        gap-4 text-center
        text-sm text-gray-500 dark:text-gray-400 md:w-auto md:justify-start md:text-left">
      <span v-if="displayVersion">
        <a :href="`https://${windowProps.site_host}`"
           class="hover:underline
            focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2"
           rel="noopener noreferrer"
           aria-label="Visit Onetime Secret homepage">
          Powered by Onetime Secret
        </a>
        <span aria-hidden="true">·</span>
      </span>
      <div v-if="!displayLinks"
           class="text-inherit">
        <router-link to="/info/terms"
                     class="transition-colors duration-200 hover:text-gray-800 dark:hover:text-gray-100">
          Terms
        </router-link>
        <span class="mx-2">·</span>
        <router-link to="/info/privacy"
                     class="transition-colors duration-200 hover:text-gray-800 dark:hover:text-gray-100">
          Privacy
        </router-link>
      </div>
    </div>

    <div v-if="displayToggles"
         class="container mx-auto max-w-2xl px-4">
      <div class="flex flex-wrap items-center justify-center space-x-4">
        <ThemeToggle class="text-gray-500 transition-colors duration-200 hover:text-gray-800 dark:text-gray-400 dark:hover:text-gray-100"
                     aria-label="Toggle dark mode" />
      </div>
    </div>
  </footer>
</template>
