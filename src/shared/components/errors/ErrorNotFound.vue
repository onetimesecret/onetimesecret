<!-- src/shared/components/errors/ErrorNotFound.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';

const { t } = useI18n();

</script>

<template>
  <div class="flex min-h-[70vh] flex-col items-center justify-center px-4 text-center">
    <div class="mb-8">
      <svg
        class="mx-auto size-32 text-brand-500 dark:text-brand-400"
        fill="none"
        stroke="currentColor"
        viewBox="0 0 24 24"
        xmlns="http://www.w3.org/2000/svg"
        width="128"
        height="128">
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="2"
          d="M9.172 16.172a4 4 0 015.656 0M9 10h.01M15 10h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
      </svg>
    </div>

    <h2 class="mb-4 text-3xl font-bold text-gray-800 dark:text-gray-200">
      {{ t('web.errors.t_web_common_oops_404', [t('web.COMMON.oops')]) }}
    </h2>

    <p class="mb-6 text-lg text-gray-600 dark:text-gray-400">
      {{ t('web.errors.the_page_youre_looking_for_doesnt_exist_or_has_b') }}
    </p>

    <a
      href="/"
      class="inline-block rounded-lg bg-brand-500 px-6 py-3 text-white shadow-md transition-colors duration-300 hover:bg-brand-600 hover:shadow-lg dark:bg-brand-600 dark:hover:bg-brand-700">
      {{ t('web.errors.go_share_a_secret') }}
    </a>
  </div>
</template>
