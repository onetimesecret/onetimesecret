<!-- src/components/secrets/SecretDisplayHelpContent.vue -->

<script setup lang="ts">
  // Import for i18n but no need for direct t usage as we use template $t
  import { useI18n } from 'vue-i18n';
  useI18n();
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
          {{ $t('web.help.secret_view_faq.what_am_i_looking_at.title') }}
        </h3>
        <p>
          {{ $t('web.help.secret_view_faq.what_am_i_looking_at.description') }}
        </p>
      </div>

      <div
        class="rounded-lg bg-gray-50 p-4 ring-1 ring-gray-200
          dark:bg-gray-800/50 dark:ring-gray-700">
        <h3 class="mb-2 font-medium text-gray-900 dark:text-gray-100">
          {{ $t('web.help.secret_view_faq.can_i_view_again.title') }}
        </h3>
        <p>
          {{ $t('web.help.secret_view_faq.can_i_view_again.description') }}
        </p>
      </div>

      <div
        class="rounded-lg bg-gray-50 p-4 ring-1 ring-gray-200
          dark:bg-gray-800/50 dark:ring-gray-700">
        <h3 class="mb-2 font-medium text-gray-900 dark:text-gray-100">
          {{ $t('web.help.secret_view_faq.how_to_copy.title') }}
        </h3>
        <p>
          {{ $t('web.help.secret_view_faq.how_to_copy.description') }}
        </p>
      </div>

      <div
        class="rounded-lg bg-gray-50 p-4 ring-1 ring-gray-200
          dark:bg-gray-800/50 dark:ring-gray-700">
        <h3 class="mb-2 font-medium text-gray-900 dark:text-gray-100">
          {{ $t('web.help.secret_view_faq.is_my_viewing_tracked.title') }}
        </h3>
        <p>
          {{ $t('web.help.secret_view_faq.is_my_viewing_tracked.description') }}
        </p>
      </div>

      <div
        class="border-l-4 border-amber-400 bg-amber-50 p-4 text-amber-800
          dark:border-amber-500 dark:bg-amber-900 dark:text-amber-100"
        role="region"
        aria-label="Important information">
        <h4 class="font-medium">
          {{ $t('web.COMMON.warning') }}
        </h4>
        <p>{{ $t('web.help.secret_view_faq.one_time_warning') }}</p>
      </div>
    </div>
  </div>
</template>
