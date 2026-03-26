<!-- src/shared/components/ui/CopyToClipboardButton.vue -->

<script setup lang="ts">
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { useI18n } from 'vue-i18n';

  defineProps<{
    isCopied: boolean;
    testid?: string;
  }>();

  const { t } = useI18n();
</script>

<template>
  <button
    @click="$emit('click')"
    :data-testid="testid"
    class="rounded-md p-1.5 text-gray-500 transition-colors duration-150 hover:bg-gray-100 hover:text-gray-700 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 dark:text-gray-400 dark:hover:bg-gray-700 dark:hover:text-gray-200"
    :class="{
      'text-green-500 dark:text-green-400': isCopied,
    }"
    :title="isCopied ? t('web.COMMON.copied_to_clipboard') : t('web.COMMON.copy_to_clipboard')"
    :aria-label="isCopied ? t('web.COMMON.copied_to_clipboard') : t('web.COMMON.copy_to_clipboard')">
    <OIcon
      collection="material-symbols"
      :name="isCopied ? 'check' : 'content-copy-outline'"
      class="size-4" />
  </button>
</template>
