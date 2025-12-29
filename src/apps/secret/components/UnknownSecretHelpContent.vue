<!-- src/apps/secret/components/UnknownSecretHelpContent.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';

const { t } = useI18n();

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
          {{ t('web.errors.why_is_this_secret_unavailable') }}
        </h3>
        <p>
          {{ t('web.errors.secrets_are_designed_to_be_viewed_only_once') }}
        </p>
      </div>

      <div
        class="rounded-lg bg-gray-50 p-4 ring-1 ring-gray-200
          dark:bg-gray-800/50 dark:ring-gray-700">
        <h3 class="mb-2 font-medium text-gray-900 dark:text-gray-100">
          {{ t('web.errors.what_should_i_do_now') }}
        </h3>
        <p>
          {{ t('web.errors.contact_the_person_who_sent_you_this_link') }}
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
    </div>
  </div>
</template>
