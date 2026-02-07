<!-- src/apps/secret/components/SecretRecipientHelpContent.vue -->

/** eslint-disable tailwindcss/classnames-order */
<script setup lang="ts">
  import { useBrandI18n } from '@/shared/composables/useBrandI18n';

const { t, bt } = useBrandI18n();

  interface Props {}
  defineProps<Props>();
</script>

<template>
  <div class="space-y-6 text-sm text-gray-600 dark:text-gray-400">
    <div class="flex items-center justify-between">
      <h2 class="text-lg font-semibold text-gray-800 dark:text-gray-200">
        {{ t('web.COMMON.faq_title') }}
      </h2>
    </div>

    <div class="space-y-4">
      <div
        class="rounded-lg bg-gray-50 p-4 ring-1 ring-gray-200
          dark:bg-gray-800/50 dark:ring-gray-700">
        <h3 class="mb-2 font-medium text-gray-900 dark:text-gray-100">
          {{ t('web.secrets.what_is_this') }}
        </h3>
        <p>
          {{ bt('web.secrets.onetime_secret_is_a_secure_way_to_share_sensitiv') }}
        </p>
      </div>

      <div
        class="rounded-lg bg-gray-50 p-4 ring-1 ring-gray-200
          dark:bg-gray-800/50 dark:ring-gray-700">
        <h3 class="mb-2 font-medium text-gray-900 dark:text-gray-100">
          {{ t('web.secrets.is_it_secure') }}
        </h3>
        <p>
          {{ t('web.secrets.yes_after_viewing_the_secret_is_permanently_dele') }}
        </p>
      </div>

      <div
        class="rounded-lg bg-gray-50 p-4 ring-1 ring-gray-200
          dark:bg-gray-800/50 dark:ring-gray-700">
        <h3 class="mb-2 font-medium text-gray-900 dark:text-gray-100">
          {{ t('web.secrets.what_happens_next') }}
        </h3>
        <p>
          {{ t('web.secrets.when_ready_click_the_view_secret_button_at_the_t') }}
        </p>
      </div>
    </div>
  </div>
</template>
