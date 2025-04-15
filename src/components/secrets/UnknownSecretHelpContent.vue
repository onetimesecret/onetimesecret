<!-- src/components/secrets/UnknownSecretHelpContent.vue -->

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
          {{ $t('why-is-this-secret-unavailable') }}
        </h3>
        <p>
          {{ $t('secrets-are-designed-to-be-viewed-only-once') }}
        </p>
      </div>

      <div
        class="rounded-lg bg-gray-50 p-4 ring-1 ring-gray-200
          dark:bg-gray-800/50 dark:ring-gray-700">
        <h3 class="mb-2 font-medium text-gray-900 dark:text-gray-100">
          {{ $t('what-should-i-do-now') }}
        </h3>
        <p>
          {{ $t('contact-the-person-who-sent-you-this-link') }}
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
    </div>
  </div>
</template>
