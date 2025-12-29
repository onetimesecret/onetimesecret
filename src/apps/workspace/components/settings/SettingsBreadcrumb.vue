<!-- src/apps/workspace/components/settings/SettingsBreadcrumb.vue -->

<script setup lang="ts">
import { useI18n } from 'vue-i18n';
import OIcon from '@/shared/components/icons/OIcon.vue';

const { t } = useI18n();

defineProps<{
  /** Current page title (optional - will show as final breadcrumb) */
  currentPage?: string;
}>();
</script>

<template>
  <nav class="mb-4 flex items-center text-sm text-gray-500 dark:text-gray-400">
    <router-link
      to="/account"
      class="hover:text-gray-700 dark:hover:text-gray-200">
      {{ t('web.account.your_account') }}
    </router-link>
    <OIcon
      collection="heroicons"
      name="chevron-right-solid"
      class="mx-2 size-4"
      aria-hidden="true" />
    <router-link
      to="/account/settings"
      class="hover:text-gray-700 dark:hover:text-gray-200">
      {{ t('web.account.settings') }}
    </router-link>
    <template v-if="currentPage">
      <OIcon
        collection="heroicons"
        name="chevron-right-solid"
        class="mx-2 size-4"
        aria-hidden="true" />
      <span class="text-gray-900 dark:text-white">{{ currentPage }}</span>
    </template>
    <template v-else>
      <OIcon
        collection="heroicons"
        name="chevron-right-solid"
        class="mx-2 size-4"
        aria-hidden="true" />
      <span class="text-gray-900 dark:text-white">{{ t('web.account.settings') }}</span>
    </template>
  </nav>
</template>
