<!-- src/apps/secret/components/layout/SecretFooterAttribution.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import LegalLink from '@/shared/components/common/LegalLink.vue';
  import { NEUTRAL_BRAND_DEFAULTS } from '@/shared/constants/brand';
  import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
  import { storeToRefs } from 'pinia';
  import { computed } from 'vue';

const { t } = useI18n();
const bootstrapStore = useBootstrapStore();
const { brand_product_name } = storeToRefs(bootstrapStore);

// Legal URLs from site.legal (#4278). An unset URL removes the whole
// affordance (separator dot included) — never a dead link.
const termsUrl = computed(() => bootstrapStore.legalUrls.terms_url);
const privacyUrl = computed(() => bootstrapStore.legalUrls.privacy_url);

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
        :aria-label="t('web.layout.visit_onetime_secret_homepage', { product_name: brand_product_name ?? NEUTRAL_BRAND_DEFAULTS.product_name })">
        {{ t('web.branding.powered_by_onetime_secret', { product_name: brand_product_name ?? NEUTRAL_BRAND_DEFAULTS.product_name }) }}
      </a>

      <template v-if="showTerms">
        <template v-if="termsUrl">
          <span
            aria-hidden="true"
            class="text-gray-400 dark:text-gray-600"
            role="presentation">&middot;</span>
          <LegalLink
            :url="termsUrl"
            class="hover:underline focus:outline-none focus:ring-2 focus:ring-brand-500"
            :aria-label="t('web.layout.view_terms_of_service')">
            {{ t('web.footer.terms') }}
          </LegalLink>
        </template>
        <template v-if="privacyUrl">
          <span
            aria-hidden="true"
            class="text-gray-400 dark:text-gray-600"
            role="presentation">&middot;</span>
          <LegalLink
            :url="privacyUrl"
            class="hover:underline focus:outline-none focus:ring-2 focus:ring-brand-500"
            :aria-label="t('web.layout.view_privacy_policy')">
            {{ t('web.footer.privacy') }}
          </LegalLink>
        </template>
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
        :aria-label="t('web.layout.visit_onetime_secret_homepage', { product_name: brand_product_name ?? NEUTRAL_BRAND_DEFAULTS.product_name })">
        {{ t('web.branding.powered_by_onetime_secret', { product_name: brand_product_name ?? NEUTRAL_BRAND_DEFAULTS.product_name }) }}
      </a>
    </div>
  </footer>
</template>
