<!-- src/shared/components/layout/TransactionalFooter.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import FeedbackToggle from '@/shared/components/ui/FeedbackToggle.vue';
  import JurisdictionToggle from '@/shared/components/ui/JurisdictionToggle.vue';
  import LanguageToggle from '@/shared/components/ui/LanguageToggle.vue';
  import FooterLinks from '@/shared/components/layout/FooterLinks.vue';
  import ThemeToggle from '@/shared/components/ui/ThemeToggle.vue';
  import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
  import { useProductIdentity } from '@/shared/stores/identityStore';
  import type { LayoutProps } from '@/types/ui/layouts';
  import { storeToRefs } from 'pinia';
  import { computed } from 'vue';

  withDefaults(defineProps<LayoutProps>(), {
    displayFeedback: true,
    displayFooterLinks: true,
    displayVersion: true,
    displayToggles: true,
    displayPoweredBy: true,
  });

  const { t } = useI18n();
  const bootstrapStore = useBootstrapStore();
  const {
    regions_enabled,
    regions,
    authentication,
    i18n_enabled,
    ot_version,
    ot_version_long,
    ui,
    brand_product_name,
  } = storeToRefs(bootstrapStore);

  const { isCustom } = useProductIdentity();

  // Hide regions toggle on custom domains (they're tied to a specific deployment)
  const showRegionsToggle = computed(
    () => regions_enabled.value && regions.value && !isCustom
  );
</script>

<template>
  <!-- prettier-ignore-attribute class -->
  <footer
    class="
    w-full min-w-[320px]
    bg-gray-100
    py-16 transition-all
    duration-300 dark:bg-gray-800"
    :aria-label="t('web.layout.site_footer')">
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
          displayFooterLinks && ui?.footer_links?.enabled
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
            :title="`${t('web.homepage.onetime_secret_literal', { product_name: brand_product_name })} Version`">
            <a
              :href="`https://github.com/onetimesecret/onetimesecret/releases/tag/v${ot_version}`"
              :aria-label="t('web.layout.release_notes')">
              v{{ ot_version_long }}
            </a>
          </span>
          <span
            v-if="displayVersion && displayPoweredBy"
            class="flex items-center justify-center px-2">
            -
          </span>
          <span
            v-if="displayPoweredBy"
            :title="`${t('web.homepage.onetime_secret_literal', { product_name: brand_product_name })} Version`">
            <a
              :href="t('web.COMMON.website_url')"
              target="_blank"
              rel="noopener noreferrer">
              {{ t('web.COMMON.powered_by') }}
              {{ t('web.homepage.onetime_secret_literal', { product_name: brand_product_name }) }}
            </a>
          </span>
        </div>

        <!-- Toggles Section -->
        <!-- prettier-ignore-attribute class -->
        <div
          v-if="displayToggles"
          class="flex w-full flex-row items-center justify-center gap-4 sm:w-auto sm:justify-end">
          <JurisdictionToggle v-if="showRegionsToggle" />

          <!-- prettier-ignore-attribute class -->
          <ThemeToggle
            class="text-gray-500 transition-colors duration-200
              hover:text-gray-800 dark:text-gray-400 dark:hover:text-gray-100"
            :aria-label="t('web.layout.toggle_dark_mode')" />

          <LanguageToggle
            v-if="i18n_enabled"
            :compact="true"
            max-height="max-h-dvh" />

          <!-- prettier-ignore-attribute class -->
          <FeedbackToggle
            v-if="displayFeedback && authentication?.enabled"
            class="text-gray-500 transition-colors duration-200
              hover:text-gray-800 dark:text-gray-400 dark:hover:text-gray-100"
            :aria-label="t('web.layout.provide_feedback')" />
        </div>
      </div>
    </div>
  </footer>
</template>
