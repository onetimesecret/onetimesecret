<!-- src/components/layout/DefaultFooter.vue -->

<script setup lang="ts">
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
    'regions_enabled',
    'regions',
    'authentication',
    'site_host',
  ]);
</script>
<template>
  <footer
    class="w-full min-w-[320px] bg-gray-100 py-8 transition-colors duration-300 dark:bg-gray-800"
    aria-label="Site footer">
    <div class="container mx-auto max-w-2xl px-4">
      <div class="flex flex-col items-center justify-center space-y-4">
        <!-- Links Section -->
        <div class="text-sm text-gray-500 dark:text-gray-400">
          <router-link
            to="/info/terms"
            class="transition-colors duration-200 hover:text-gray-800 dark:hover:text-gray-100 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2">
            Terms
          </router-link>
          <span
            class="mx-2 select-none"
            aria-hidden="true"
            >·</span
          >
          <router-link
            to="/info/privacy"
            class="transition-colors duration-200 hover:text-gray-800 dark:hover:text-gray-100 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2">
            Privacy
          </router-link>
        </div>
        <!-- Powered By Link -->
        <a
          v-if="displayPoweredBy"
          :href="`https://${windowProps.site_host}`"
          class="mt-2 text-xs text-gray-400 transition-colors duration-200 hover:text-gray-600 dark:text-gray-500 dark:hover:text-gray-300 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2"
          rel="noopener noreferrer"
          aria-label="Visit Onetime Secret homepage">
          Powered by Onetime Secret
        </a>


        <!-- Theme Toggle -->
        <ThemeToggle
          v-if="displayToggles"
          class="text-gray-500 transition-colors duration-200 hover:text-gray-800 dark:text-gray-400 dark:hover:text-gray-100"
          aria-label="Toggle dark mode" />

      </div>
    </div>
  </footer>
</template>
