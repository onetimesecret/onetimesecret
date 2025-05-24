<!-- src/components/layout/DefaultFooter.vue -->

<script setup lang="ts">
  import FeedbackToggle from '@/components/FeedbackToggle.vue';
  import JurisdictionToggle from '@/components/JurisdictionToggle.vue';
  import LanguageToggle from '@/components/LanguageToggle.vue';
  import FooterLinks from '@/components/layout/FooterLinks.vue';

  import ThemeToggle from '@/components/ThemeToggle.vue';

  import { WindowService } from '@/services/window.service';

  import type { LayoutProps } from '@/types/ui/layouts';

  withDefaults(defineProps<LayoutProps>(), {
    displayFeedback: true,
    displayFooterLinks: true,
    displayVersion: true,
    displayToggles: true,
    displayPoweredBy: true,
  });

  const windowProps = WindowService.getMultiple([
    'regions_enabled',
    'regions',
    'authentication',
    'i18n_enabled',
    'ot_version',
    'ui',
  ]);
</script>

<template>
  <!-- prettier-ignore-attribute class -->
  <footer
    class="
    w-full min-w-[320px]
    bg-gray-100
    py-16 transition-all
    duration-300 dark:bg-gray-800"
    :aria-label="$t('site-footer')">
    <div class="container mx-auto max-w-2xl px-4">
      <!-- Footer Links Section -->
      <FooterLinks v-if="displayFooterLinks" />

      <!-- Existing Footer Content -->
      <!-- prettier-ignore-attribute class -->
      <div
        class="
        flex
        flex-col-reverse items-center
        justify-between
        space-y-6 space-y-reverse md:flex-row
        md:space-y-0"
        :class="
          displayFooterLinks && windowProps.ui?.footer_links?.enabled
            ? 'mt-8 border-t border-gray-200 pt-8 dark:border-gray-700'
            : ''
        ">
        <!-- Version and Powered By -->
        <!-- prettier-ignore-attribute class -->
        <div
          class="
          flex w-full
          flex-wrap items-center justify-center
          text-center
          text-xs text-gray-500 dark:text-gray-400 md:w-auto md:justify-start md:text-left">
          <span
            v-if="displayVersion"
            :title="`${$t('onetime-secret-literal')} Version`">
            <a
              :href="`https://github.com/onetimesecret/onetimesecret/releases/tag/v${windowProps.ot_version}`"
              :aria-label="$t('release-notes')">
              v{{ windowProps.ot_version }}
            </a>
          </span>
          <span
            v-if="displayVersion && displayPoweredBy"
            class="flex items-center justify-center px-2">
            -
          </span>
          <span
            v-if="displayPoweredBy"
            :title="`${$t('onetime-secret-literal')} Version`">
            {{ $t('web.COMMON.powered_by') }}
            <a
              :href="$t('web.COMMON.website_url')"
              target="_blank"
              rel="noopener noreferrer">
              {{ $t('onetime-secret-literal') }}
            </a>
          </span>
        </div>

        <!-- Toggles Section -->
        <!-- prettier-ignore-attribute class -->
        <div
          v-if="displayToggles"
          class="flex w-full flex-row items-center justify-center gap-4 sm:w-auto sm:justify-end">
          <JurisdictionToggle v-if="windowProps.regions_enabled && windowProps.regions" />

          <!-- prettier-ignore-attribute class -->
          <ThemeToggle
            class="text-gray-500 transition-colors duration-200
              hover:text-gray-800 dark:text-gray-400 dark:hover:text-gray-100"
            :aria-label="$t('toggle-dark-mode')" />

          <LanguageToggle
            v-if="windowProps.i18n_enabled"
            :compact="true"
            max-height="max-h-dvh" />

          <!-- prettier-ignore-attribute class -->
          <FeedbackToggle
            v-if="displayFeedback && windowProps.authentication?.enabled"
            class="text-gray-500 transition-colors duration-200
              hover:text-gray-800 dark:text-gray-400 dark:hover:text-gray-100"
            :aria-label="$t('provide-feedback')" />
        </div>
      </div>
    </div>
  </footer>
</template>
