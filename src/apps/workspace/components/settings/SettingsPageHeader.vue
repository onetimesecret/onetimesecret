<!-- src/apps/workspace/components/settings/SettingsPageHeader.vue -->

<script setup lang="ts">
import { useI18n } from 'vue-i18n';

const { t } = useI18n();

defineProps<{
  /** Page title (optional - defaults to Settings) */
  title?: string;
  /** Page subtitle/description (optional) */
  subtitle?: string;
}>();

defineSlots<{
  /** Optional actions slot for buttons/controls */
  actions?(): unknown;
}>();
</script>

<template>
  <div class="mb-8">
    <div class="flex items-start justify-between">
      <div>
        <h1 class="text-3xl font-bold text-gray-900 dark:text-white">
          {{ title ?? t('web.TITLES.account') }}
        </h1>
        <p
          v-if="subtitle"
          class="mt-2 text-sm text-gray-600 dark:text-gray-400">
          {{ subtitle }}
        </p>
        <p
          v-else
          class="mt-2 text-sm text-gray-600 dark:text-gray-400">
          {{ t('web.settings.manage_your_account_settings_and_preferences') }}
        </p>
      </div>
      <div v-if="$slots.actions">
        <slot name="actions" ></slot>
      </div>
    </div>
  </div>
</template>
