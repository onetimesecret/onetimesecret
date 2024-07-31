<script setup lang="ts">
import CopyButton from './CopyButton.vue';

interface Props {
  label: string;
  value: string;
  appendix?: string;
}

defineProps<Props>();

</script>

<template>
  <div class="flex bg-white dark:bg-gray-600 rounded-md overflow-hidden">
    <div class="w-16 flex-shrink-0 flex items-center justify-end px-3 py-2 bg-gray-100 dark:bg-gray-700 border-r border-gray-200 dark:border-gray-500">
      <span class="text-sm font-medium text-gray-500 dark:text-gray-300">{{ label }}:</span>
    </div>
    <div class="flex-grow flex items-center justify-between p-3 relative">
      <span class="text-gray-800 dark:text-gray-200 min-w-0 flex-shrink truncate">
        {{ value }}<span v-if="appendix" class="text-gray-400">{{ appendix }}</span>
      </span>
      <div class="flex-shrink-0">
        <CopyButton :text="value" />
      </div>
    </div>
  </div>
</template>
