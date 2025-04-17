<!-- src/components/secrets/SecretRecipientHelpContent.vue -->

/** eslint-disable tailwindcss/classnames-order */
<script setup lang="ts">
  interface Props {}
  defineProps<Props>();
</script>

<template>
  <div class="space-y-6 text-sm text-gray-600 dark:text-gray-400">
    <div class="flex items-center justify-between">
      <h2 class="text-lg font-semibold text-gray-800 dark:text-gray-200">
        {{ $t('web.COMMON.faq_title') }}
      </h2>
    </div>

    <div class="space-y-4">
      <div
        class="rounded-lg bg-gray-50 p-4 ring-1 ring-gray-200
          dark:bg-gray-800/50 dark:ring-gray-700">
        <h3 class="mb-2 font-medium text-gray-900 dark:text-gray-100">
          {{ $t('what-is-this') }}
        </h3>
        <p>
          {{ $t('onetime-secret-is-a-secure-way-to-share-sensitiv') }}
        </p>
      </div>

      <div
        class="rounded-lg bg-gray-50 p-4 ring-1 ring-gray-200
          dark:bg-gray-800/50 dark:ring-gray-700">
        <h3 class="mb-2 font-medium text-gray-900 dark:text-gray-100">
          {{ $t('is-it-secure') }}
        </h3>
        <p>
          {{ $t('yes-after-viewing-the-secret-is-permanently-dele') }}
        </p>
      </div>

      <div
        class="rounded-lg bg-gray-50 p-4 ring-1 ring-gray-200
          dark:bg-gray-800/50 dark:ring-gray-700">
        <h3 class="mb-2 font-medium text-gray-900 dark:text-gray-100">
          {{ $t('what-happens-next') }}
        </h3>
        <p>
          {{ $t('when-ready-click-the-view-secret-button-at-the-t') }}
        </p>
      </div>
    </div>
  </div>
</template>
