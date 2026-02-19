<!-- src/apps/secret/components/layout/SecretFooterAttribution.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
  import { storeToRefs } from 'pinia';

const { t } = useI18n();
const { brand_product_name } = storeToRefs(useBootstrapStore());

  defineProps<{
    siteHost: string;
    showNav?: boolean;
    showTerms?: boolean;
  }>();
</script>

<template>
  <footer
    class="text-center text-xs text-gray-400 dark:text-gray-600"
    role="contentinfo">
    <nav
      v-if="showNav"
      class="flex flex-wrap justify-center gap-2 space-x-2"
      :aria-label="t('web.layout.footer_navigation')">
      <a
        :href="`https://${siteHost}`"
        class="hover:underline focus:outline-none focus:ring-2 focus:ring-brand-500"
        rel="noopener noreferrer"
        target="_blank"
        :aria-label="t('web.layout.visit_onetime_secret_homepage', { product_name: brand_product_name })">
        {{ t('web.branding.powered_by_onetime_secret', { product_name: brand_product_name }) }}
      </a>

      <template v-if="showTerms">
        <span
          aria-hidden="true"
          class="text-gray-400 dark:text-gray-600"
          role="presentation">&middot;</span>
        <router-link
          to="/info/terms"
          class="hover:underline focus:outline-none focus:ring-2 focus:ring-brand-500"
          :aria-label="t('web.layout.view_terms_of_service')">
          {{ t('terms') }}
        </router-link>
        <span
          aria-hidden="true"
          class="text-gray-400 dark:text-gray-600"
          role="presentation">&middot;</span>
        <router-link
          to="/info/privacy"
          class="hover:underline focus:outline-none focus:ring-2 focus:ring-brand-500"
          :aria-label="t('web.layout.view_privacy_policy')">
          {{ t('privacy') }}
        </router-link>
      </template>
    </nav>

    <div
      v-else
      class="text-center">
      <a
        :href="`https://${siteHost}`"
        class="inline-block px-2 py-1 text-[0.7rem] text-gray-400 transition-colors duration-200
          hover:text-gray-500 hover:underline focus:outline-none focus:ring-2 focus:ring-brand-500
          dark:text-gray-600 dark:hover:text-gray-500"
        rel="noopener noreferrer"
        target="_blank"
        :aria-label="t('web.layout.visit_onetime_secret_homepage', { product_name: brand_product_name })">
        {{ t('web.branding.powered_by_onetime_secret', { product_name: brand_product_name }) }}
      </a>
    </div>
  </footer>
</template>
