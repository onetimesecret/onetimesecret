<!-- src/apps/secret/components/layout/BrandedFooter.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import FeedbackToggle from '@/shared/components/ui/FeedbackToggle.vue';
  import JurisdictionToggle from '@/shared/components/ui/JurisdictionToggle.vue';
  import LanguageToggle from '@/shared/components/ui/LanguageToggle.vue';
  import ThemeToggle from '@/shared/components/ui/ThemeToggle.vue';
  import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
  import { useProductIdentity } from '@/shared/stores/identityStore';
  import { storeToRefs } from 'pinia';
  import type { LayoutProps } from '@/types/ui/layouts';

const { t } = useI18n();

  const productIdentity = useProductIdentity();

  withDefaults(defineProps<LayoutProps>(), {});

  const bootstrapStore = useBootstrapStore();
  const {
    regions_enabled,
    regions,
    authentication,
    i18n_enabled,
    ot_version,
    ot_version_long,
  } = storeToRefs(bootstrapStore);

</script>
<template>
  <footer
    class="w-full min-w-[320px] bg-gray-100 py-6 transition-colors duration-300 dark:bg-gray-800"
    :aria-label="t('web.layout.site_footer')">
    <div
      v-if="productIdentity.isCanonical"
      class="container mx-auto max-w-2xl px-4">
      <div
        class="flex flex-col-reverse items-center justify-between space-y-6 space-y-reverse md:flex-row md:space-y-0">
        <div
          class="flex w-full flex-wrap items-center justify-center gap-4 text-center text-sm text-gray-500 dark:text-gray-400 md:w-auto md:justify-start md:text-left">
          <span
            v-if="displayVersion"
            :title="`${t('web.homepage.onetime_secret_literal')} ${t('web.COMMON.version')}`">
            <a :href="`https://github.com/onetimesecret/onetimesecret/releases/tag/v${ot_version}`">v{{ ot_version_long }}</a>
          </span>
        </div>

        <div
          v-if="displayToggles"
          class="flex items-center justify-center gap-4 md:w-auto md:justify-end">
          <JurisdictionToggle v-if="regions_enabled && regions" />

          <ThemeToggle
            class="text-gray-500 transition-colors duration-200 hover:text-gray-800 dark:text-gray-400 dark:hover:text-gray-100"
            :aria-label="t('web.layout.toggle_dark_mode')" />
          <LanguageToggle
            v-if="i18n_enabled"
            :compact="true"
            max-height="max-h-dvh" />
          <FeedbackToggle
            v-if="displayFeedback && authentication?.enabled"
            class="text-gray-500 transition-colors duration-200 hover:text-gray-800 dark:text-gray-400 dark:hover:text-gray-100"
            :aria-label="t('web.layout.provide_feedback')" />
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
            :aria-label="t('web.layout.toggle_dark_mode')" />
          <LanguageToggle
            v-if="i18n_enabled"
            :compact="true"
            max-height="max-h-dvh" />
        </div>
      </div>
    </div>
  </footer>
</template>
