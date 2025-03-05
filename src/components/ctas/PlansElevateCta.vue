<!-- PlansElevateCta.vue -->

<script setup lang="ts">
import { computed } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
const { t } = useI18n();

const router = useRouter();
const pricingLink = computed(() => router.resolve({ name: t('pricing') }).href);

</script>

<template>
  <section
    class="mb-8 rounded-lg bg-gradient-to-r from-brand-600 to-brand-800 p-6 text-white shadow-lg dark:from-brand-800 dark:to-brand-900">
    <h4 class="mb-2 text-xl font-semibold text-white">
      {{ $t('web.COMMON.custom_domains_title') }}
    </h4>
    <p class="mb-4 text-white/90 dark:text-white/80">
      {{ $t('web.COMMON.custom_domains_description') }}
    </p>
    <a
      :href="pricingLink"
      class="inline-flex items-center rounded-md border border-transparent bg-white px-4 py-2 font-brand text-sm text-brand-600
       transition-colors duration-200 hover:bg-gray-50 focus:outline-none
       focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 dark:bg-gray-800 dark:text-brand-400
       dark:hover:bg-gray-700 dark:focus:ring-brand-400">
      <svg
        class="mr-2 size-5"
        xmlns="http://www.w3.org/2000/svg"
        fill="none"
        viewBox="0 0 24 24"
        stroke="currentColor"
        aria-hidden="true"
        height="24"
        width="24">
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="2"
          d="M21 12a9 9 0 01-9 9m9-9a9 9 0 00-9-9m9 9H3m9 9a9 9 0 01-9-9m9 9c1.657 0 3-4.03 3-9s-1.343-9-3-9m0 18c-1.657 0-3-4.03-3-9s1.343-9 3-9m-9 9a9 9 0 019-9"
        />
      </svg>
      {{ $t('web.COMMON.get_started_button') }}
      <svg
        class="ml-2 size-4"
        fill="none"
        stroke="currentColor"
        height="20"
        width="20"
        viewBox="0 0 24 24"
        xmlns="http://www.w3.org/2000/svg">
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="2"
          d="M9 5l7 7-7 7"
        />
      </svg>
    </a>
  </section>
</template>
