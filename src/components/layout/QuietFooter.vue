<!-- src/components/layout/QuietFooter.vue -->

<script setup lang="ts">
  import FeedbackToggle from '@/components/FeedbackToggle.vue';
  import JurisdictionToggle from '@/components/JurisdictionToggle.vue';
  import LanguageToggle from '@/components/LanguageToggle.vue';
  import ThemeToggle from '@/components/ThemeToggle.vue';
  import { WindowService } from '@/services/window.service';
  import { useProductIdentity } from '@/stores/identityStore';
  import type { LayoutProps } from '@/types/ui/layouts';
  import { ref } from 'vue';

  const productIdentity = useProductIdentity();

  withDefaults(defineProps<LayoutProps>(), {});

  const windowProps = WindowService.getMultiple([
    'regions_enabled',
    'regions',
    'authentication',
    'i18n_enabled',
  ]);

  const companyName = ref('OnetimeSecret.com');
</script>
<template>
  <footer
    class="w-full min-w-[320px] bg-gray-100 py-6 transition-colors duration-300 dark:bg-gray-800"
    :aria-label="$t('site-footer')">
    <div
      v-if="productIdentity.isCanonical"
      class="container mx-auto max-w-2xl px-4">
      <div
        class="flex flex-col-reverse items-center justify-between space-y-6 space-y-reverse md:flex-row md:space-y-0">
        <div
          class="flex w-full flex-wrap items-center justify-center gap-4 text-center text-sm text-gray-500 dark:text-gray-400 md:w-auto md:justify-start md:text-left">
          <span v-if="displayVersion">
            &copy; {{ new Date().getFullYear() }} {{ companyName }}.
          </span>
        </div>

        <div
          v-if="displayToggles"
          class="flex items-center justify-center gap-4 md:w-auto md:justify-end">
          <JurisdictionToggle v-if="windowProps.regions_enabled && windowProps.regions" />

          <ThemeToggle
            class="text-gray-500 transition-colors duration-200 hover:text-gray-800 dark:text-gray-400 dark:hover:text-gray-100"
            :aria-label="$t('toggle-dark-mode')" />
          <LanguageToggle
            v-if="windowProps.i18n_enabled"
            :compact="true"
            max-height="max-h-dvh" />
          <FeedbackToggle
            v-if="displayFeedback && windowProps.authentication?.enabled"
            class="text-gray-500 transition-colors duration-200 hover:text-gray-800 dark:text-gray-400 dark:hover:text-gray-100"
            :aria-label="$t('provide-feedback')" />
        </div>
      </div>
    </div>
    <div
      v-else
      class="container mx-auto max-w-2xl px-4">
      <div class="flex flex-col items-center justify-center space-y-4">
        <!-- Theme Toggle -->
        <div
          v-if="displayToggles"
          class="flex w-full flex-nowrap items-center justify-center space-x-4 md:w-auto md:justify-end">
          <ThemeToggle
            class="text-gray-500 transition-colors duration-200 hover:text-gray-800 dark:text-gray-400 dark:hover:text-gray-100"
            :aria-label="$t('toggle-dark-mode')" />
          <LanguageToggle
            v-if="windowProps.i18n_enabled"
            :compact="true"
            max-height="max-h-dvh" />
        </div>
      </div>
    </div>
  </footer>
</template>
